import 'package:pronowin/l10n/app_strings.dart';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/dio_client.dart';
import '../../../../core/theme/app_theme.dart';

/// Signaler un commentaire, bloquer un membre (règle 1.2 de l'App Store,
/// contenus générés par les utilisateurs de Google Play).
///
/// Le serveur filtre à la publication, retire un commentaire signalé à
/// plusieurs reprises en attendant la modération, et ne montre plus à un
/// membre les commentaires de ceux qu'il a bloqués.

/// Les motifs, dans l'ordre où ils sont proposés. La clé part au serveur.
const motifsSignalement = <(String, String)>[
  ('spam',    'Spam ou publicité'),
  ('insulte', 'Insulte ou harcèlement'),
  ('haine',   'Propos haineux ou discriminatoires'),
  ('sexuel',  'Contenu sexuel'),
  ('autre',   'Autre'),
];

/// Le motif choisi, ou `null` si le membre renonce.
Future<({String motif, String? detail})?> demanderSignalement(BuildContext context) =>
    showModalBottomSheet<({String motif, String? detail})>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const _FeuilleSignalement(),
    );

class _FeuilleSignalement extends StatefulWidget {
  const _FeuilleSignalement();
  @override
  State<_FeuilleSignalement> createState() => _FeuilleSignalementState();
}

class _FeuilleSignalementState extends State<_FeuilleSignalement> {
  String? _motif;
  final _detail = TextEditingController();

  @override
  void dispose() {
    _detail.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: context.cl.bg,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28))),
    padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.of(context).viewInsets.bottom + 28),
    child: SingleChildScrollView(child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(child: Container(width: 40, height: 4,
          margin: const EdgeInsets.only(bottom: 20),
          decoration: BoxDecoration(color: context.cl.border, borderRadius: BorderRadius.circular(2)))),
        Text(tr(context, "Signaler ce commentaire"), style: TextStyle(
          color: context.cl.textP, fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(tr(context, "Notre équipe examine chaque signalement sous 24 heures. L'auteur ne saura pas qui l'a signalé."),
          style: TextStyle(color: context.cl.textS, fontSize: 13, height: 1.45)),
        const SizedBox(height: 12),
        RadioGroup<String>(
          groupValue: _motif,
          onChanged: (v) => setState(() => _motif = v),
          child: Column(children: [
            for (final (cle, libelle) in motifsSignalement)
              RadioListTile<String>(
                value: cle,
                contentPadding: EdgeInsets.zero,
                activeColor: AppColors.primary,
                title: Text(tr(context, libelle),
                  style: TextStyle(color: context.cl.textP, fontSize: 14)),
              ),
          ]),
        ),
        TextField(
          controller: _detail,
          maxLength: 500,
          maxLines: 2,
          style: TextStyle(color: context.cl.textP, fontSize: 14),
          decoration: InputDecoration(
            hintText: tr(context, "Précisions (facultatif)"),
            hintStyle: TextStyle(color: context.cl.textM),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(width: double.infinity, child: ElevatedButton(
          onPressed: _motif == null ? null : () => Navigator.pop(context, (
            motif: _motif!,
            detail: _detail.text.trim().isEmpty ? null : _detail.text.trim(),
          )),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.error,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Text(tr(context, "Signaler"), style: const TextStyle(fontWeight: FontWeight.w700)),
        )),
      ],
    )),
  );
}

/// `true` si le membre confirme le blocage.
Future<bool> confirmerBlocage(BuildContext context, String pseudo) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(ctx, "Bloquer {arg0} ?", [pseudo])),
        content: Text(tr(ctx, "Tu ne verras plus ses commentaires. Tu pourras le débloquer depuis les Paramètres.")),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr(ctx, "Annuler"))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr(ctx, "Bloquer"), style: const TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    ) ??
    false;

// ─── Appels au serveur ──────────────────────────────────────────────────────

Future<void> signalerCommentaire(Dio dio, String commentId, String motif, String? detail) =>
    dio.post('/moderation/signalements', data: {
      'comment_id': commentId,
      'motif': motif,
      'detail': ?detail,
    });

Future<void> bloquerMembre(Dio dio, String userId) =>
    dio.post('/moderation/blocages', data: {'user_id': userId});

Future<void> debloquerMembre(Dio dio, String userId) =>
    dio.delete('/moderation/blocages/$userId');

/// Un membre bloqué, tel que le serveur le décrit.
class MembreBloque {
  const MembreBloque({required this.userId, required this.pseudo});
  final String userId;
  final String pseudo;
}

final membresBloquesProvider = FutureProvider.autoDispose<List<MembreBloque>>((ref) async {
  final r = await ref.read(dioProvider).get('/moderation/blocages');
  return ((r.data as Map<String, dynamic>)['data'] as List)
      .map((m) => MembreBloque(
            userId: (m as Map<String, dynamic>)['user_id'] as String,
            pseudo: m['pseudo'] as String,
          ))
      .toList();
});

/// Le message à montrer quand le serveur refuse une action de modération ou
/// un commentaire. Les refus connus ont leur code, traduit ici ; les autres
/// gardent le message du serveur.
String messageRefus(BuildContext context, Object erreur) {
  if (erreur is DioException) {
    final data = erreur.response?.data;
    final code = data is Map ? data['code'] as String? : null;
    switch (code) {
      case 'TERMES_INTERDITS':
        return tr(context, "Ce commentaire contient des termes interdits par les règles de la communauté.");
      case 'LIEN_INTERDIT':
        return tr(context, "Les liens ne sont pas autorisés dans les commentaires.");
      case 'TELEPHONE_INTERDIT':
        return tr(context, "Les numéros de téléphone ne sont pas autorisés dans les commentaires.");
      case 'DEJA_SIGNALE':
        return tr(context, "Tu as déjà signalé ce commentaire.");
    }
    final message = data is Map ? data['message'] as String? : null;
    if (message != null && message.isNotEmpty) return message;
  }
  return tr(context, "L'action n'a pas abouti. Réessaie dans un instant.");
}

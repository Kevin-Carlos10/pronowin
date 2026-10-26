import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/dio_client.dart';
import '../../core/theme/app_theme.dart';
import '../../features/parametres/presentation/providers/settings_provider.dart';
import '../../l10n/app_strings.dart';

/// Les alertes au choix pour un match suivi (27 octobre 2026), comme sur
/// Sofascore.
///
/// Suivre un match envoyait tout : coup d'envoi, compositions, buts, cartons,
/// mi-temps, fin du match, résumé. Sur la semaine du 19 octobre, 145 alertes
/// de but pour 8 lues — trop, et le risque qu'on coupe toutes les
/// notifications. Le match suivi, la cloche de sa fiche ouvre cette feuille :
/// une alerte par interrupteur, trois raccourcis, et « Ne plus suivre ».
const categoriesAlerte = ['coup_envoi', 'compositions', 'buts', 'cartons', 'mi_temps', 'fin_de_match', 'resume'];

String libelleAlerte(BuildContext context, String c) => switch (c) {
  'coup_envoi'   => tr(context, "Coup d'envoi"),
  'compositions' => tr(context, "Compositions officielles"),
  'buts'         => tr(context, "Buts"),
  'cartons'      => tr(context, "Cartons rouges"),
  'mi_temps'     => tr(context, "La mi-temps"),
  'fin_de_match'     => tr(context, "Fin du match et résultat"),
  'resume'       => tr(context, "Résumé du match"),
  _              => c,
};

IconData iconeAlerte(String c) => switch (c) {
  'coup_envoi'   => Icons.sports_rounded,
  'compositions' => Icons.groups_rounded,
  'buts'         => Icons.sports_soccer_rounded,
  'cartons'      => Icons.style_rounded,
  'mi_temps'     => Icons.timelapse_rounded,
  'fin_de_match'     => Icons.sports_score_rounded,
  'resume'       => Icons.article_rounded,
  _              => Icons.notifications_rounded,
};

/// Les alertes gardées pour ce match ; null si le serveur ne répond pas.
final alertesMatchProvider = FutureProvider.autoDispose.family<List<String>?, String>((ref, matchId) async {
  try {
    final r = await ref.read(dioProvider).get('/favorites/$matchId/alertes');
    return List<String>.from((r.data as Map)['alertes'] as List);
  } on DioException {
    return null;
  }
});

/// Enregistre le choix ; rend les alertes gardées. Lève [DioException].
final choisirAlertesProvider = Provider<Future<List<String>> Function(String matchId, List<String> alertes)>((ref) =>
  (matchId, alertes) async {
    final r = await ref.read(dioProvider).put('/favorites/$matchId/alertes', data: {'alertes': alertes});
    return List<String>.from((r.data as Map)['alertes'] as List);
  });

/// Ouvre la feuille des alertes de [matchId]. [onNePlusSuivre] : retirer le
/// match des matchs suivis — la feuille se ferme d'abord.
Future<void> ouvrirAlertesMatch(BuildContext context, {
  required String matchId, required String titre, required VoidCallback onNePlusSuivre,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  builder: (_) => FeuilleAlertes(matchId: matchId, titre: titre, onNePlusSuivre: onNePlusSuivre),
);

@visibleForTesting
class FeuilleAlertes extends ConsumerStatefulWidget {
  final String matchId, titre;
  final VoidCallback onNePlusSuivre;
  const FeuilleAlertes({super.key, required this.matchId, required this.titre, required this.onNePlusSuivre});

  @override
  ConsumerState<FeuilleAlertes> createState() => _FeuilleAlertesState();
}

class _FeuilleAlertesState extends ConsumerState<FeuilleAlertes> {
  /// Le choix affiché : celui du serveur, puis chaque changement aussitôt.
  List<String>? _alertes;
  String? _erreur;

  Future<void> _enregistrer(List<String> nouvelles) async {
    final avant = _alertes;
    final message = tr(context, "Choix non enregistré. Réessaie.");
    HapticFeedback.selectionClick();
    // Dans l'ordre du catalogue.
    final ordonnees = categoriesAlerte.where(nouvelles.contains).toList();
    setState(() { _alertes = ordonnees; _erreur = null; });
    try {
      final gardees = await ref.read(choisirAlertesProvider)(widget.matchId, ordonnees);
      if (mounted) setState(() => _alertes = gardees);
    } catch (_) {
      if (mounted) setState(() { _alertes = avant; _erreur = message; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final lu = ref.watch(alertesMatchProvider(widget.matchId));
    final alertes = _alertes ?? lu.valueOrNull;
    final coupees = !ref.watch(settingsProvider).notifMatch;
    bool memes(List<String> a) => alertes != null && alertes.length == a.length && a.every(alertes.contains);

    final raccourcis = [
      ('tout', tr(context, "Tout"), categoriesAlerte),
      ('buts', tr(context, "Buts seulement"), const ['buts']),
      ('fin_de_match', tr(context, "Résultat seulement"), const ['fin_de_match']),
    ];

    return Container(
      key: const Key('feuille-alertes'),
      decoration: BoxDecoration(
        color: context.cl.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
      child: SafeArea(top: false, child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Center(child: Container(width: 36, height: 4,
            decoration: BoxDecoration(color: context.cl.border, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 14),
          Semantics(header: true, child: Text(tr(context, "Alertes pour ce match"),
            style: TextStyle(color: context.cl.textP, fontSize: 18, fontWeight: FontWeight.w800))),
          const SizedBox(height: 2),
          Text(widget.titre, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(color: context.cl.textM, fontSize: 13)),
          if (coupees) ...[
            const SizedBox(height: 10),
            Text(tr(context, "Les alertes de match sont coupées dans les Paramètres : rien ne partira."),
              key: const Key('alertes-coupees'),
              style: TextStyle(color: context.cl.warning, fontSize: 12.5, fontWeight: FontWeight.w600)),
          ],
          const SizedBox(height: 14),
          if (alertes == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(child: lu.isLoading
                  ? const CircularProgressIndicator(color: AppColors.primary)
                  : Text(tr(context, "Alertes indisponibles pour l'instant."),
                      style: TextStyle(color: context.cl.textS))),
            )
          else ...[
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final (cle, libelle, liste) in raccourcis)
                ChoiceChip(
                  key: Key('alertes-raccourci-$cle'),
                  label: Text(libelle),
                  selected: memes(liste),
                  onSelected: (_) => _enregistrer(liste),
                ),
            ]),
            const SizedBox(height: 8),
            for (final c in categoriesAlerte)
              SwitchListTile.adaptive(
                key: Key('alerte-$c'),
                contentPadding: EdgeInsets.zero,
                secondary: Icon(iconeAlerte(c), color: context.cl.textS),
                title: Text(libelleAlerte(context, c),
                  style: TextStyle(color: context.cl.textP, fontSize: 14.5, fontWeight: FontWeight.w600)),
                value: alertes.contains(c),
                onChanged: (on) => _enregistrer(on ? [...alertes, c] : alertes.where((a) => a != c).toList()),
              ),
            if (alertes.isEmpty)
              Text(tr(context, "Aucune alerte : le match reste dans tes matchs suivis, sans notification."),
                style: TextStyle(color: context.cl.textM, fontSize: 12.5)),
          ],
          if (_erreur != null) ...[
            const SizedBox(height: 8),
            Text(_erreur!, key: const Key('alertes-erreur'),
              style: TextStyle(color: context.cl.error, fontSize: 12.5)),
          ],
          const SizedBox(height: 8),
          Center(child: TextButton.icon(
            key: const Key('alertes-ne-plus-suivre'),
            onPressed: () {
              Navigator.of(context).pop();
              widget.onNePlusSuivre();
            },
            icon: Icon(Icons.notifications_off_rounded, color: context.cl.error, size: 18),
            label: Text(tr(context, "Ne plus suivre ce match"),
              style: TextStyle(color: context.cl.error, fontWeight: FontWeight.w700)),
          )),
        ]),
      )),
    );
  }
}

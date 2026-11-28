import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pronowin/l10n/app_strings.dart';

import '../../../../core/network/dio_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/utils/devise.dart';
import '../../../../shared/utils/messages.dart';
import '../../../../shared/utils/montant.dart';
import '../../domain/couverture.dart';
import '../providers/bankroll_provider.dart';

/// « Couvrir ma mise » (26 novembre 2026, complété le 27) — partagé par la
/// fiche du match (mise simple) et le détail d'un combiné.
///
/// [donnees] : la réponse du serveur (`GET /bankroll/couverture/:id` ou
/// `GET /bankroll/combines/:id/couverture`). La carte montre l'inverse et sa
/// cote du moment, laisse choisir entre le gain égal et la mise remboursée,
/// refait le calcul sur la cote saisie, et enregistre la couverture placée
/// (« J'ai couvert »). Une fois enregistrée, elle la montre à la place.
class CarteCouverture extends ConsumerStatefulWidget {
  final Map<String, dynamic> donnees;
  /// Suffixe des clés : `couverture-<cle>`, `couverture-cote-<cle>`.
  final String cle;
  final bool combine;
  /// Après un « J'ai couvert » réussi : rafraîchir ce qui doit l'être.
  final VoidCallback? apresEnregistrement;

  const CarteCouverture({
    super.key, required this.donnees, required this.cle, this.combine = false, this.apresEnregistrement,
  });

  @override
  ConsumerState<CarteCouverture> createState() => _CarteCouvertureState();
}

class _CarteCouvertureState extends ConsumerState<CarteCouverture> {
  final _cote = TextEditingController();
  StrategieCouverture _strategie = StrategieCouverture.gainEgal;

  @override
  void dispose() {
    _cote.dispose();
    super.dispose();
  }

  double? get _coteSaisie {
    final v = double.tryParse(_cote.text.trim().replaceAll(',', '.'));
    return v != null && v > 1 && v <= 1000 ? v : null;
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.donnees;
    final anglais = AppStrings.of(context).locale.languageCode == 'en';
    final enregistree = CouvertureEnregistree.depuis(d['enregistree']);
    final code = d['devise'] as String?;
    final devise = nomDevise(code);

    final titre = widget.combine ? tr(context, "COUVRIR MON COMBINÉ") : tr(context, "COUVRIR MA MISE");
    if (enregistree != null) return _cadre(context, titre, false, [_Enregistree(h: enregistree, devise: devise)]);

    final inverse = (anglais ? d['inverse_en'] : d['inverse_fr']) as String? ?? '';
    final selection = (anglais ? d['selection_en'] : d['selection_fr']) as String? ?? '';
    final mise = (d['mise'] as num?)?.toDouble() ?? 0;
    final cote = (d['cote'] as num?)?.toDouble() ?? 0;
    final seuil = (d['seuil'] as num?)?.toInt() ?? 50;
    final coteServeur = (d['cote_inverse'] as num?)?.toDouble();
    final coteInverse = _coteSaisie ?? coteServeur;
    final pas = pasDeDevise(code);
    final calcul = coteInverse == null ? null : calculerCouverture(mise, cote, coteInverse, pas: pas, strategie: _strategie);
    // Le seuil se lit toujours sur le gain égal : c'est ce que la couverture
    // garantit au mieux.
    final egal = coteInverse == null ? null : calculerCouverture(mise, cote, coteInverse, pas: pas);
    final atteint = egal?.atteint(seuil) ?? false;
    final remboursement = (anglais ? d['note_remboursement_en'] : d['note_remboursement_fr']) as String?;

    final source = switch (d['source']) {
      'direct' => d['minute'] is num
          ? tr(context, "en direct, {arg0}e minute", [(d['minute'] as num).toInt()])
          : tr(context, "en direct"),
      'avant_match' => tr(context, "avant le match"),
      _ => null,
    };

    return _cadre(context, titre, atteint, [
      Text(
        widget.combine
            ? tr(context, "Ton combiné : {arg0} {arg1}, cote restante {arg2}", [montantExact(mise), devise, cote.toStringAsFixed(2)])
            : tr(context, "Ta mise : {arg0} {arg1} à {arg2}", [montantExact(mise), devise, cote.toStringAsFixed(2)]),
        style: TextStyle(color: context.cl.textS, fontSize: 13)),
      const SizedBox(height: 4),
      Text(
        coteServeur != null
            ? (source == null
                ? tr(context, "« {arg0} » est à {arg1}.", [inverse, coteServeur.toStringAsFixed(2)])
                : tr(context, "« {arg0} » est à {arg1} ({arg2}).", [inverse, coteServeur.toStringAsFixed(2), source]))
            : tr(context, "Cote de « {arg0} » indisponible pour l’instant : saisis celle qu’on te propose.", [inverse]),
        style: TextStyle(color: context.cl.textP, fontSize: 14, fontWeight: FontWeight.w600, height: 1.35)),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        _Choix(
          cle: 'couverture-strategie-gain_egal',
          libelle: tr(context, "Gain égal"),
          choisi: _strategie == StrategieCouverture.gainEgal,
          onTap: () => setState(() => _strategie = StrategieCouverture.gainEgal)),
        _Choix(
          cle: 'couverture-strategie-mise_remboursee',
          libelle: tr(context, "Récupérer ma mise"),
          choisi: _strategie == StrategieCouverture.miseRemboursee,
          onTap: () => setState(() => _strategie = StrategieCouverture.miseRemboursee)),
      ]),
      if (calcul != null) ...[
        const SizedBox(height: 12),
        if ((egal?.gainGaranti ?? 0) <= 0)
          Text(
            tr(context, "Couvrir maintenant ne garantit aucun gain : attends que la cote de « {arg0} » monte.", [inverse]),
            key: const Key('couverture-pas-encore'),
            style: TextStyle(color: context.cl.textS, fontSize: 13, height: 1.4))
        else ...[
          Text(tr(context, "Mise {arg0} {arg1} sur « {arg2} »", [montantExact(calcul.miseCouverture), devise, inverse]),
            key: const Key('couverture-mise'),
            style: TextStyle(color: context.cl.textP, fontSize: 18, fontWeight: FontWeight.w800, height: 1.25)),
          const SizedBox(height: 4),
          Text(
            _strategie == StrategieCouverture.gainEgal
                ? tr(context, "Gain garanti : +{arg0} {arg1}, quel que soit le résultat ({arg2} % du gain potentiel)",
                    [montantExact(calcul.gainGaranti), devise, (calcul.part * 100).round()])
                : tr(context, "Si « {arg0} » passe : +{arg1} {arg2}. Sinon, tu récupères ta mise ({arg3} {arg4}).",
                    [selection, montantExact(calcul.siSelection),
                     devise, calcul.siInverse >= 0 ? '+${montantExact(calcul.siInverse)}' : montantExact(calcul.siInverse), devise]),
            key: const Key('couverture-gain'),
            style: TextStyle(color: atteint ? context.cl.success : context.cl.textS,
              fontSize: 13, fontWeight: FontWeight.w600, height: 1.35)),
          if (remboursement != null) ...[
            const SizedBox(height: 6),
            Text(remboursement, key: const Key('couverture-remboursement'),
              style: TextStyle(color: context.cl.textS, fontSize: 12, height: 1.4)),
          ],
        ],
      ],
      const SizedBox(height: 12),
      TextField(
        key: Key('couverture-cote-${widget.cle}'),
        controller: _cote,
        onChanged: (_) => setState(() {}),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
        style: TextStyle(color: context.cl.textP, fontSize: 15, fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          isDense: true,
          // Court : le nom de l'évènement est juste au-dessus, et un long
          // libellé se tronquait.
          labelText: tr(context, "La cote qu’on te propose"),
          hintText: coteServeur?.toStringAsFixed(2),
        ),
      ),
      if (calcul != null && (egal?.gainGaranti ?? 0) > 0) ...[
        const SizedBox(height: 12),
        SizedBox(width: double.infinity, child: OutlinedButton.icon(
          key: const Key('couverture-jai-couvert'),
          icon: const Icon(Icons.shield_outlined, size: 18),
          label: Text(tr(context, "J’ai couvert")),
          onPressed: () => _enregistrer(context, inverse, calcul.miseCouverture, coteInverse!),
        )),
      ],
      const SizedBox(height: 10),
      Text(tr(context, "Vérifie la cote proposée avant de miser : le gain n’est garanti que si les deux mises sont placées à ces cotes."),
        style: TextStyle(color: context.cl.textM, fontSize: 11, height: 1.4)),
    ]);
  }

  Widget _cadre(BuildContext context, String titre, bool atteint, List<Widget> contenu) => Padding(
    key: Key('couverture-${widget.cle}'),
    padding: const EdgeInsets.only(bottom: 16),
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cl.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: atteint ? context.cl.success.withValues(alpha: 0.55) : context.cl.border,
          width: atteint ? 1.2 : 0.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.swap_horiz_rounded, color: context.cl.textM, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Semantics(header: true, child: Text(titre, style: TextStyle(
            color: context.cl.textM, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1)))),
          if (atteint)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: context.cl.success.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(8)),
              child: Text(tr(context, "Seuil atteint"), style: TextStyle(
                color: context.cl.success, fontSize: 11, fontWeight: FontWeight.w700)),
            ),
        ]),
        const SizedBox(height: 10),
        ...contenu,
      ]),
    ),
  );

  /// « J'ai couvert » : la mise réellement placée sur l'inverse, et sa cote.
  Future<void> _enregistrer(BuildContext context, String inverse, double mise, double cote) async {
    final saisie = await showDialog<({double mise, double cote})>(
      context: context,
      builder: (_) => _DialogueCouverture(inverse: inverse, mise: mise, cote: cote),
    );
    if (saisie == null || !context.mounted) return;
    final d = widget.donnees;
    try {
      await ref.read(dioProvider).post('/bankroll/couvertures', data: {
        if (d['pari_id'] is String) 'pari_id': d['pari_id'],
        if (d['combine_id'] is String && d['pari_id'] is! String) 'combine_id': d['combine_id'],
        'mise': saisie.mise,
        'cote': saisie.cote,
        'strategie': (saisie.mise - mise).abs() < 1e-9 && (saisie.cote - cote).abs() < 1e-9 ? _strategie.code : 'libre',
      });
      if (!context.mounted) return;
      afficherMessage(context, tr(context, "Couverture enregistrée : elle se règlera avec le match."), type: TypeMessage.succes);
      ref.invalidate(bankrollProvider);
      widget.apresEnregistrement?.call();
    } catch (e) {
      if (!context.mounted) return;
      final message = e is DioException ? e.response?.data is Map ? (e.response!.data as Map)['message'] as String? : null : null;
      afficherMessage(context, message ?? tr(context, "La couverture n’a pas pu être enregistrée. Réessaie."), type: TypeMessage.erreur);
    }
  }
}

/// Une couverture déjà enregistrée.
class _Enregistree extends StatelessWidget {
  final CouvertureEnregistree h;
  final String devise;
  const _Enregistree({required this.h, required this.devise});

  @override
  Widget build(BuildContext context) {
    final anglais = AppStrings.of(context).locale.languageCode == 'en';
    final etat = switch (h.result) {
      'WIN' => tr(context, "gagnée"),
      'LOSS' => tr(context, "perdue"),
      'PUSH' => tr(context, "remboursée"),
      _ => tr(context, "en cours"),
    };
    return Column(key: const Key('couverture-enregistree'), crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Icons.shield_rounded, size: 18, color: context.cl.success),
        const SizedBox(width: 8),
        Expanded(child: Text(
          tr(context, "Couverture enregistrée : {arg0} {arg1} sur « {arg2} » à {arg3}",
            [montantExact(h.mise), devise, h.selection(anglais), h.cote.toStringAsFixed(2)]),
          style: TextStyle(color: context.cl.textP, fontSize: 14, fontWeight: FontWeight.w600, height: 1.35))),
      ]),
      const SizedBox(height: 6),
      Text(
        h.profit == null
            ? tr(context, "Couverture {arg0} : elle se règle avec le match.", [etat])
            : tr(context, "Couverture {arg0} : {arg1} {arg2}.", [etat, '${h.profit! >= 0 ? '+' : ''}${montantExact(h.profit!)}', devise]),
        style: TextStyle(color: context.cl.textS, fontSize: 12, height: 1.4)),
    ]);
  }
}

class _Choix extends StatelessWidget {
  final String cle;
  final String libelle;
  final bool choisi;
  final VoidCallback onTap;
  const _Choix({required this.cle, required this.libelle, required this.choisi, required this.onTap});

  @override
  Widget build(BuildContext context) => ChoiceChip(
    key: Key(cle),
    label: Text(libelle),
    selected: choisi,
    onSelected: (_) => onTap(),
    showCheckmark: false,
    labelStyle: TextStyle(
      color: choisi ? context.cl.textP : context.cl.textS,
      fontSize: 12, fontWeight: choisi ? FontWeight.w700 : FontWeight.w500),
  );
}

/// La mise placée sur l'inverse et sa cote, à confirmer ou corriger.
class _DialogueCouverture extends StatefulWidget {
  final String inverse;
  final double mise;
  final double cote;
  const _DialogueCouverture({required this.inverse, required this.mise, required this.cote});

  @override
  State<_DialogueCouverture> createState() => _DialogueCouvertureState();
}

class _DialogueCouvertureState extends State<_DialogueCouverture> {
  late final _mise = TextEditingController(text: _texte(widget.mise));
  late final _cote = TextEditingController(text: widget.cote.toStringAsFixed(2));

  static String _texte(double n) => n == n.roundToDouble() ? n.toStringAsFixed(0) : n.toStringAsFixed(2);

  @override
  void dispose() {
    _mise.dispose();
    _cote.dispose();
    super.dispose();
  }

  double? _lire(TextEditingController c) => double.tryParse(c.text.trim().replaceAll(',', '.').replaceAll(' ', ''));

  @override
  Widget build(BuildContext context) {
    final mise = _lire(_mise);
    final cote = _lire(_cote);
    final valide = mise != null && mise > 0 && cote != null && cote >= 1.01 && cote <= 1000;
    return AlertDialog(
      backgroundColor: context.cl.surface,
      title: Text(tr(context, "J’ai couvert"), style: TextStyle(color: context.cl.textP, fontWeight: FontWeight.w700)),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr(context, "Enregistre la mise que tu as réellement placée sur « {arg0} ». Elle sort de ton solde et se règle avec le match.", [widget.inverse]),
          style: TextStyle(color: context.cl.textS, fontSize: 13, height: 1.4)),
        const SizedBox(height: 12),
        TextField(
          key: const Key('couverture-dialogue-mise'),
          controller: _mise,
          onChanged: (_) => setState(() {}),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
          decoration: InputDecoration(labelText: tr(context, "Mise placée")),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('couverture-dialogue-cote'),
          controller: _cote,
          onChanged: (_) => setState(() {}),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
          decoration: InputDecoration(labelText: tr(context, "Cote obtenue")),
        ),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr(context, "Annuler"))),
        TextButton(
          key: const Key('couverture-enregistrer'),
          onPressed: valide ? () => Navigator.pop(context, (mise: mise, cote: cote)) : null,
          child: Text(tr(context, "Enregistrer"), style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}

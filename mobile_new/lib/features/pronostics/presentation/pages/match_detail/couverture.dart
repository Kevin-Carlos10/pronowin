// « Couvrir ma mise » — l'alerte de couverture dans la fiche du match
// (26 novembre 2026).
//
// `part` et non un fichier autonome : la fiche garde ses classes privées.
part of '../match_detail_page.dart';

/// La couverture de sa mise sur un pronostic, maintenant (serveur).
final couvertureMiseProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>?, String>((ref, pronosticId) async {
  try {
    final r = await ref.read(dioProvider).get('/bankroll/couverture/$pronosticId');
    return Map<String, dynamic>.from(r.data as Map);
  } catch (_) {
    return null;
  }
});

/// Pour une sélection enregistrée dans la bankroll et encore ouverte :
/// l'évènement inverse, sa cote du moment, combien miser dessus et ce qui est
/// alors garanti. L'abonné peut saisir la cote de son propre bookmaker : le
/// calcul se refait sur place.
///
/// Rien sans mise ouverte, pour un marché qui n'a pas d'inverse exact, une
/// fois le match terminé, et sur l'iPhone sans pari. Porte sa propre marge.
class _CarteCouverture extends ConsumerStatefulWidget {
  final String pronosticId;
  final MatchEntity match;
  const _CarteCouverture({required this.pronosticId, required this.match});

  @override
  ConsumerState<_CarteCouverture> createState() => _CarteCouvertureState();
}

class _CarteCouvertureState extends ConsumerState<_CarteCouverture> {
  final _cote = TextEditingController();

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
    if (ref.watch(sansPariProvider) || widget.match.status == MatchStatus.finished) {
      return const SizedBox.shrink();
    }
    if (!ref.watch(hasBetOnPronosticProvider(widget.pronosticId))) return const SizedBox.shrink();
    final d = ref.watch(couvertureMiseProvider(widget.pronosticId)).valueOrNull;
    if (d == null || !(d['disponible'] == true || d['raison'] == 'cote')) return const SizedBox.shrink();

    final anglais = AppStrings.of(context).locale.languageCode == 'en';
    final inverse = (anglais ? d['inverse_en'] : d['inverse_fr']) as String? ?? '';
    final mise = (d['mise'] as num?)?.toDouble() ?? 0;
    final cote = (d['cote'] as num?)?.toDouble() ?? 0;
    final code = d['devise'] as String?;
    final devise = nomDevise(code);
    final seuil = (d['seuil'] as num?)?.toInt() ?? 50;
    final coteServeur = (d['cote_inverse'] as num?)?.toDouble();
    final coteInverse = _coteSaisie ?? coteServeur;
    final calcul = coteInverse == null
        ? null : calculerCouverture(mise, cote, coteInverse, pas: pasDeDevise(code));
    final atteint = calcul?.atteint(seuil) ?? false;

    final source = switch (d['source']) {
      'direct' => tr(context, "en direct"),
      'avant_match' => tr(context, "avant le match"),
      _ => null,
    };

    return Padding(
      key: Key('couverture-${widget.pronosticId}'),
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
            Expanded(child: Semantics(header: true, child: Text(tr(context, "COUVRIR MA MISE"), style: TextStyle(
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
          Text(tr(context, "Ta mise : {arg0} {arg1} à {arg2}", [montantExact(mise), devise, cote.toStringAsFixed(2)]),
            style: TextStyle(color: context.cl.textS, fontSize: 13)),
          const SizedBox(height: 4),
          Text(
            coteServeur != null
                ? (source == null
                    ? tr(context, "« {arg0} » est à {arg1}.", [inverse, coteServeur.toStringAsFixed(2)])
                    : tr(context, "« {arg0} » est à {arg1} ({arg2}).", [inverse, coteServeur.toStringAsFixed(2), source]))
                : tr(context, "Cote de « {arg0} » indisponible pour l’instant : saisis celle qu’on te propose.", [inverse]),
            style: TextStyle(color: context.cl.textP, fontSize: 14, fontWeight: FontWeight.w600, height: 1.35)),
          if (calcul != null) ...[
            const SizedBox(height: 12),
            if (calcul.gainGaranti <= 0)
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
                tr(context, "Gain garanti : +{arg0} {arg1}, quel que soit le résultat ({arg2} % du gain potentiel)",
                  [montantExact(calcul.gainGaranti), devise, (calcul.part * 100).round()]),
                key: const Key('couverture-gain'),
                style: TextStyle(color: atteint ? context.cl.success : context.cl.textS,
                  fontSize: 13, fontWeight: FontWeight.w600, height: 1.35)),
            ],
          ],
          const SizedBox(height: 12),
          TextField(
            key: Key('couverture-cote-${widget.pronosticId}'),
            controller: _cote,
            onChanged: (_) => setState(() {}),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            style: TextStyle(color: context.cl.textP, fontSize: 15, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              isDense: true,
              // Court : le nom de l'évènement est juste au-dessus, et un long
              // libellé se tronquait (« chez ton boo… »).
              labelText: tr(context, "La cote qu’on te propose"),
              hintText: coteServeur?.toStringAsFixed(2),
            ),
          ),
          const SizedBox(height: 10),
          Text(tr(context, "Vérifie la cote proposée avant de miser : le gain n’est garanti que si les deux mises sont placées à ces cotes."),
            style: TextStyle(color: context.cl.textM, fontSize: 11, height: 1.4)),
        ]),
      ),
    );
  }
}

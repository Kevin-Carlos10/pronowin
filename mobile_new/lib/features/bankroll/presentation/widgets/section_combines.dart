import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pronowin/l10n/app_strings.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/utils/devise.dart';
import '../../../../shared/utils/montant.dart';
import '../pages/combines_pages.dart';
import '../providers/bankroll_provider.dart';

/// Les combinés dans la page bankroll (27 novembre 2026) : le bouton pour en
/// composer un, et la liste.
class SectionCombines extends StatelessWidget {
  final BankrollData bankroll;
  const SectionCombines({super.key, required this.bankroll});

  @override
  Widget build(BuildContext context) {
    final combines = bankroll.combines;
    return Column(key: const Key('bankroll-combines'), crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(tr(context, "Combinés"),
          style: TextStyle(color: context.cl.textP, fontSize: 15, fontWeight: FontWeight.w700))),
        OutlinedButton.icon(
          key: const Key('bankroll-nouveau-combine'),
          onPressed: () => context.push('/bankroll/combine/nouveau'),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: Text(tr(context, "Nouveau combiné")),
        ),
      ]),
      const SizedBox(height: 6),
      if (combines.isEmpty)
        Text(tr(context, "Combine de 2 à 10 sélections en un seul coupon : pronostics PronoWin ou sélections libres."),
          style: TextStyle(color: context.cl.textM, fontSize: 12, height: 1.4))
      else
        for (final c in combines) _CarteCombine(combine: c),
    ]);
  }
}

class _CarteCombine extends StatelessWidget {
  final BankrollCombine combine;
  const _CarteCombine({required this.combine});

  @override
  Widget build(BuildContext context) {
    final c = combine;
    final couleur = couleurResultat(context, c.result);
    final devise = nomDevise(c.currency);
    final net = c.resultatNet;
    return Semantics(
      button: true,
      label: tr(context, "Combiné de {arg0} sélections, cote {arg1}, {arg2}", [c.selections.length, c.oddsUsed.toStringAsFixed(2), libelleResultat(context, c.result)]),
      excludeSemantics: true,
      child: GestureDetector(
        key: Key('combine-${c.id}'),
        onTap: () => context.push('/bankroll/combine/${c.id}'),
        child: Container(
          margin: const EdgeInsets.only(top: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: context.cl.surface, borderRadius: BorderRadius.circular(14),
            border: Border.all(color: couleur.withValues(alpha: 0.35), width: 0.8)),
          child: Row(children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(color: couleur.withValues(alpha: 0.12), shape: BoxShape.circle),
              child: Icon(Icons.layers_rounded, color: couleur, size: 18)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr(context, "{arg0} sélections · cote {arg1}", [c.selections.length, c.oddsUsed.toStringAsFixed(2)]),
                style: TextStyle(color: context.cl.textP, fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 3),
              Text(
                c.result == null
                    ? tr(context, "{arg0} à jouer", [c.restantes])
                    : libelleResultat(context, c.result),
                style: TextStyle(color: context.cl.textM, fontSize: 11)),
              if (c.couvertureEnregistree != null) ...[
                const SizedBox(height: 3),
                Text(tr(context, "Couvert"), style: TextStyle(color: context.cl.success, fontSize: 11, fontWeight: FontWeight.w700)),
              ],
            ])),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(tr(context, "Mise {arg0}", [montantExact(c.stakedAmount)]),
                style: TextStyle(color: context.cl.textP, fontSize: 12, fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text(
                net != null
                    ? tr(context, "Net {arg0}", ['${net >= 0 ? '+' : ''}${montantExact(net)}'])
                    : tr(context, "Brut potentiel {arg0}", [montantExact(c.potentialGain)]),
                style: TextStyle(
                  color: net == null ? context.cl.textM : (net >= 0 ? context.cl.success : context.cl.error),
                  fontSize: 12, fontWeight: FontWeight.w700)),
              Text(devise, style: TextStyle(color: context.cl.textM, fontSize: 11)),
            ]),
          ]),
        ),
      ),
    );
  }
}

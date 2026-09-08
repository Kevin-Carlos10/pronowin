import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Un seul prix d'accroche, et il connaît le canal.
///
/// `premiumMonthlyPriceLabel` porte la règle, et sa documentation nomme
/// l'usage : « prix mensuel à afficher sur les écrans d'accroche (« à partir
/// de X ») ». Elle sait que le tarif est majoré sur un build store pour
/// absorber la commission Google, et que le prix Mobile Money y annoncerait
/// moins que le montant réellement débité.
///
/// Trois écrans l'utilisaient. `premium_gate_sheet.dart` — la feuille qui
/// s'ouvre quand on touche un match VIP, c'est-à-dire *l'écran d'accroche* —
/// ne l'utilisait pas. Elle composait « À partir de 4 500 FCFA » à partir de
/// la grille du canal direct, en codant la devise en dur.
///
/// Sur le build destiné à Google Play, cela donnait deux prix contradictoires
/// dans la même application : 4 500 FCFA pour convaincre, 15 $ à la caisse.
/// Ce ne sont même pas des montants équivalents — 4 500 FCFA valent environ
/// 7,50 $. L'accroche promettait la moitié du prix.
///
/// Ce fichier a déjà porté un correctif : le montant y était écrit « 5 000 »
/// en dur, corrigé en minimum calculé. La correction n'était pas allée
/// jusqu'au canal.
void main() {
  const feuille = 'lib/shared/widgets/premium_gate_sheet.dart';
  final source = File(feuille).readAsStringSync();

  String codeSeul() => source
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('//'))
      .join('\n');

  test('la feuille d\'accroche existe toujours', () {
    expect(source, contains('À partir de'));
  });

  test('elle emploie le prix partagé, qui connaît le canal', () {
    expect(codeSeul(), contains('premiumMonthlyPriceLabel'),
      reason: 'la feuille compose son propre prix : il divergera de celui '
              'que le store débite');
  });

  test('elle ne code aucune devise en dur', () {
    // Le libellé rendu par `premiumMonthlyPriceLabel` porte déjà sa devise.
    // En accoler une seconde suppose le canal, ce qui est précisément le
    // défaut corrigé.
    final code = codeSeul();
    for (final devise in ['FCFA', 'XOF', 'EUR', '€']) {
      expect(code.contains(devise), isFalse,
        reason: '« $devise » est écrit en dur dans l\'écran d\'accroche');
    }
  });

  test('elle ne lit plus la grille du canal direct', () {
    expect(codeSeul().contains('minMensuel'), isFalse,
      reason: 'cette grille est en FCFA et ne vaut que pour le canal direct');
  });
}

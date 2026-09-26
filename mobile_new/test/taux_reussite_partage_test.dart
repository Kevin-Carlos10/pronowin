import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/shared/utils/bilan_paris.dart';

/// Un seul endroit décide quand un taux de réussite peut être énoncé.
///
/// `BilanParis` porte la règle : en deçà de cinq paris tranchés, le taux vaut
/// `null` et l'écran affiche un tiret. Elle existe parce qu'un seul pari gagné
/// affichait « 100 % de réussite » — un chiffre exact et sans aucun sens, sur
/// la statistique qui fait croire à quelqu'un que sa méthode fonctionne.
///
/// La règle avait été appliquée à l'onglet Compte et oubliée dans l'onglet
/// Bankroll, qui recalculait son propre pourcentage avec un garde-fou à zéro.
/// Les deux écrans affichaient donc deux vérités sur les mêmes paris : « — »
/// d'un côté, « 50 % » de l'autre.
///
/// Ce n'est pas une phrase fausse, c'est une règle tenue à deux endroits. Le
/// contrôle vérifie qu'il n'en reste qu'un.
void main() {
  group('la règle du seuil', () {
    test('refuse un taux sous cinq paris tranchés', () {
      const bilan = BilanParis(
        suivis: 2, gagnes: 1, perdus: 1, tauxBrut: 50, serie: 0);
      expect(bilan.taux, isNull,
        reason: 'deux paris ne mesurent rien — c\'est le cas exact observé '
                'sur l\'émulateur');
    });

    test('refuse « 100 % » après un seul pari gagné', () {
      // Le défaut d'origine, dans sa forme la plus trompeuse.
      const bilan = BilanParis(
        suivis: 1, gagnes: 1, perdus: 0, tauxBrut: 100, serie: 0);
      expect(bilan.taux, isNull);
    });

    test('énonce le taux dès que l\'échantillon suffit', () {
      // Et l'autre sens : une règle qui ne dirait jamais rien serait inutile.
      const bilan = BilanParis(
        suivis: 5, gagnes: 3, perdus: 2, tauxBrut: 60, serie: 1);
      expect(bilan.taux, 60);
    });
  });

  test('aucun écran ne recalcule son propre taux', () {
    // Le premier motif visait `/ decisive * 100`, la formulation exacte des
    // trois cas connus. Un quatrième existait — la carte bankroll de
    // l'accueil — écrit `/ settled.length * 100`, et il est passé au travers
    // jusqu'à ce qu'on le voie à l'écran, affichant « 50% win » à côté du
    // « — » que les autres montraient enfin.
    //
    // Le motif ne nomme donc plus le dénominateur : toute division suivie
    // d'une multiplication par cent est un taux calculé sur place.
    final motif = RegExp(r'/[^;/]*\*\s*100\b');

    /// Les calculs locaux légitimes, chacun avec sa raison.
    ///
    /// Élargir le motif a fait apparaître deux cas dans la page d'historique.
    /// Le premier — le palmarès du modèle — a été corrigé : il applique
    /// maintenant le seuil commercial de dix, comme le backend. Le second est
    /// une courbe, et une courbe n'est pas une affirmation.
    const permises = <String>[
      // Taux cumulé point par point : le premier point vaut forcément 0 % ou
      // 100 %, c'est la nature d'une série cumulative. Le lecteur voit une
      // tendance, pas un chiffre mis en avant — et la masquer reviendrait à
      // amputer le début du graphe.
      'spots.add(FlSpot(i.toDouble(), wins / (i + 1) * 100));',
      // Palmarès du modèle : conditionné juste au-dessus par
      // `total >= echantillonCommercial`, la ligne du calcul reste locale.
      '? (won / total * 100).round()',
    ];

    final fautes = <String>[];

    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      if (f.path.replaceAll('\\', '/').endsWith('shared/utils/bilan_paris.dart')) {
        continue;
      }
      final lignes = f.readAsLinesSync();
      for (var i = 0; i < lignes.length; i++) {
        if (lignes[i].trimLeft().startsWith('//')) continue;   // les commentaires l'expliquent
        // `tauxBrut:` est l'argument de `BilanParis` lui-même : c'est la
        // valeur brute qu'on lui confie, précisément pour qu'il décide s'il
        // est permis de l'énoncer. L'accuser reviendrait à interdire d'entrer
        // dans la règle.
        if (lignes[i].contains('tauxBrut:')) continue;
        if (permises.contains(lignes[i].trim())) continue;
        if (motif.hasMatch(lignes[i])) {
          fautes.add('${f.path}:${i + 1} ${lignes[i].trim()}');
        }
      }
    }

    expect(fautes, isEmpty,
      reason: 'un écran calcule son taux hors de BilanParis : il rejouera le '
              'défaut du garde-fou à zéro');
  });
}

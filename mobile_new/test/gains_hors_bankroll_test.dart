import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Un gain ne s'affiche que là où il correspond à une mise réelle.
///
/// La fiche de match affichait « AURAIT RAPPORTÉ +790 F » sous le pronostic
/// d'un match joué. Le montant était calculé sur une mise de référence de
/// 1 000 F — donc vrai pour une mise que personne n'avait posée. Celui qui
/// avait misé 200 F lisait un gain quatre fois trop grand ; celui qui n'avait
/// rien misé lisait un gain tout court.
///
/// Un gain n'a de sens que rapporté à une bankroll, et la bankroll a son
/// propre écran, avec les vrais montants et les paris réellement enregistrés.
/// La fiche de match dit ce qui s'est passé ; elle ne chiffre pas ce qui
/// aurait pu arriver.
///
/// Le contrôle ne vise que les écrans de match. La bankroll, elle, doit
/// continuer d'afficher des montants : ce sont les siens.
void main() {
  const ecrans = [
    'lib/features/pronostics/presentation/pages/match_detail_page.dart',
    'lib/features/accueil/presentation/pages/accueil/carte_prono.dart',
  ];

  test('les écrans contrôlés existent toujours', () {
    for (final f in ecrans) {
      expect(File(f).existsSync(), isTrue, reason: '$f a disparu');
    }
  });

  test('aucune fiche de match ne chiffre un gain hypothétique', () {
    // Les formulations qui annoncent un montant non posé. « mise de
    // référence » est le mécanisme qui les produisait.
    final interdits = <RegExp>[
      RegExp(r'AURAIT\s+(RAPPORT|CO[UÛ]T)', caseSensitive: false),
      RegExp(r'_miseReference'),
    ];

    final fautes = <String>[];
    for (final chemin in ecrans) {
      final lignes = File(chemin).readAsLinesSync();
      for (var i = 0; i < lignes.length; i++) {
        // Les commentaires citent la formule pour expliquer son retrait.
        if (lignes[i].trimLeft().startsWith('//')) continue;
        for (final motif in interdits) {
          if (motif.hasMatch(lignes[i])) {
            fautes.add('$chemin:${i + 1} ${lignes[i].trim()}');
          }
        }
      }
    }

    expect(fautes, isEmpty,
      reason: 'un gain chiffré sur une mise de référence : il sera faux pour '
              'tout le monde sauf pour celui qui a misé exactement ce '
              'montant');
  });
}

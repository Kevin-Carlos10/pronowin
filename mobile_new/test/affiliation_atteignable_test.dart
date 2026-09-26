import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Un point d'entrée vers le bookmaker doit rester atteignable au doigt **et**
/// à la voix.
///
/// `Semantics(excludeSemantics: true)` supprime toute la sémantique de ses
/// descendants. Placer un bouton d'affiliation sous un tel nœud le rend
/// invisible aux lecteurs d'écran : il s'affiche, il réagit au toucher, mais il
/// n'existe plus pour qui navigue à la voix. Rien ne le signale — ni le
/// compilateur, ni `flutter analyze`, ni une capture d'écran.
///
/// C'est exactement le piège rencontré sur la carte PRONOSTIC, dont l'annonce
/// fusionnée couvrait la carte entière. Ce contrôle relit la source pour que la
/// correction ne soit pas défaite par mégarde.
void main() {
  // Un seul écran porte encore un lien affilié : le bandeau 1xBet de l'onglet
  // Cotes. Le bouton ajouté un temps sous la carte PRONOSTIC a été retiré, son
  // rendu ne convenant pas — mais la règle vaut pour tout point d'entrée à
  // venir, et ce fichier est là pour l'appliquer.
  const fichiers = [
    'lib/features/pronostics/presentation/pages/match_detail/bookmaker_cotes.dart',
  ];

  test('aucun point d\'entrée affilié n\'est noyé dans un excludeSemantics',
      () {
    final fautifs = <String>[];

    for (final chemin in fichiers) {
      final lignes = File(chemin).readAsLinesSync();

      for (var i = 0; i < lignes.length; i++) {
        if (!lignes[i].contains('BookmakerAffiliation.ouvrir') &&
            !lignes[i].contains('BookmakerCotes.ouvrirLien')) {
          continue;
        }

        // Remonter jusqu'au `Semantics(` englobant le plus proche, en suivant
        // l'indentation : un bloc moins indenté qui ouvre un Semantics est un
        // ancêtre.
        final marge = lignes[i].length - lignes[i].trimLeft().length;
        for (var j = i - 1; j >= 0 && j > i - 40; j--) {
          final l = lignes[j];
          if (l.trim().isEmpty) continue;
          final m = l.length - l.trimLeft().length;
          if (m >= marge) continue;

          if (l.contains('Semantics(')) {
            // Ancêtre trouvé : ses options se lisent sur les lignes suivantes.
            final options = lignes.sublist(j, i).join(' ');
            final exclut = options.contains('excludeSemantics: true');
            final bouton = options.contains('button: true');
            if (exclut && !bouton) {
              fautifs.add('$chemin:${i + 1} — sous un Semantics '
                  'excludeSemantics sans button:true (ligne ${j + 1})');
            }
            break;
          }
        }
      }
    }

    expect(fautifs, isEmpty,
        reason: 'Un lecteur d\'écran ne pourrait pas atteindre ces boutons :\n'
            '${fautifs.join('\n')}');
  });

}

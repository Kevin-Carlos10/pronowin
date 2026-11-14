import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Un pronostic remboursé ne s'affiche pas « Perdu ».
///
/// Lens 2-1 Lyon, « Total buts extérieur : plus de 1 » : Lyon marque un but,
/// la mise est rendue. La fiche du match disait « Pronostic remboursé » ; la
/// carte de l'accueil, pour le même pronostic, disait « Perdu » en rouge. Son
/// badge ne connaissait que WIN, et rangeait tout le reste parmi les pertes.
///
/// Le bilan « Hier · X sur Y gagnés » faisait la même confusion par l'autre
/// bout : un remboursement comptait au dénominateur, donc comme un échec.
void main() {
  const carte = 'lib/features/accueil/presentation/pages/accueil/carte_prono.dart';
  const bilan = 'lib/features/accueil/presentation/pages/accueil/preuve.dart';

  String code(String chemin) => File(chemin)
      .readAsLinesSync()
      .where((l) => !l.trimLeft().startsWith('//'))
      .join('\n');

  test('le badge de la carte d\'accueil nomme le remboursement', () {
    final src = code(carte);
    final debut = src.indexOf('class _ResultBadge');
    expect(debut, isNot(-1), reason: '_ResultBadge a disparu de $carte');
    final badge = src.substring(debut, src.indexOf('\nclass ', debut + 1));

    expect(badge, contains("'PUSH'"),
        reason: 'sans cas PUSH, un remboursement tombe dans « Perdu »');
    expect(badge, contains('"Remboursé"'));
  });

  test('le bilan d\'hier ne compte que les pronostics tranchés', () {
    final src = code(bilan);
    expect(src, isNot(contains("p['result'] != null")),
        reason: 'un remboursement compté au dénominateur se lit comme un échec');
    expect(src, contains("p['result'] == 'LOSS'"));
  });
}

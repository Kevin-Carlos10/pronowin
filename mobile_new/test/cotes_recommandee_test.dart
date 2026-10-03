import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// La tuile de la cote recommandée portait quatre signaux pour une seule
/// information : fond vert, bordure verte, chiffre vert, et une coche de neuf
/// pixels collée au « 1 ».
///
/// La coche est partie — mais elle était aussi le seul élément non coloré, et
/// la couleur ne s'entend pas. Sans repère sonore, un lecteur d'écran
/// annonçait « 1, 1.34 » à l'identique pour les trois cotes.
void main() {
  final code = File(
    'lib/features/pronostics/presentation/pages/match_detail_page.dart',
  ).readAsStringSync()
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('//'))
      .join('\n');

  /// Le corps de `_OddPill`, isolé de ses voisins.
  ///
  /// Ancré sur la classe et non sur `isRecommended` : ce mot apparaît aussi
  /// aux trois points d'appel, cent lignes plus haut, et mon extraction
  /// rapportait alors le mauvais bloc.
  String tuile() {
    final debut = code.indexOf('class _OddPill');
    expect(debut, greaterThan(-1), reason: '_OddPill a été renommée');
    final fin = code.indexOf('\nclass ', debut + 10);
    return code.substring(debut, fin == -1 ? code.length : fin);
  }

  test('plus de coche à côté du libellé', () {
    expect(tuile().contains('Icons.check_circle_rounded'), isFalse,
      reason: 'le fond, la bordure et la couleur du chiffre le disent déjà');
  });

  test('la recommandation reste annoncée aux lecteurs d\'écran', () {
    final t = tuile();
    expect(t.contains('Semantics('), isTrue,
      reason: 'la couleur ne s\'entend pas : sans libellé, les trois cotes '
              'sont annoncées à l\'identique');
    expect(t.contains('recommandée'), isTrue);
  });

  test('une cote indisponible est annoncée comme telle', () {
    expect(tuile().contains('indisponible'), isTrue,
      reason: '« — » ne se prononce pas');
  });
}

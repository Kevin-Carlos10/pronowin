import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/features/pronostics/domain/entities/verdict_comparaison.dart';

VerdictComparaison _v(double dom, double ext) => VerdictComparaison(
      domicile: dom, exterieur: ext,
      nomDomicile: 'Elche', nomExterieur: 'Barcelona');

void main() {
  group('le verdict nomme le bon favori', () {
    test('le cas de la capture : 17 / 83 pour l\'extérieur', () {
      final v = _v(17, 83);
      expect(v.favori, 'Barcelona');
      expect(v.partFavori, 83);
      expect(v.favoriADomicile, isFalse);
      expect(v.titre, 'Le modèle penche pour Barcelona');
    });

    test('un avantage à domicile désigne l\'équipe qui reçoit', () {
      final v = _v(78, 22);
      expect(v.favori, 'Elche');
      expect(v.partFavori, 78);
      expect(v.favoriADomicile, isTrue);
    });
  });

  group('un écart faible n\'est pas un penchant', () {
    test('52 contre 48 : le modèle ne départage pas', () {
      // Annoncer « le modèle penche pour Elche » sur quatre points d'écart
      // fabriquerait une conviction que le modèle n'a pas.
      final v = _v(52, 48);
      expect(v.indecis, isTrue);
      expect(v.favori, isNull);
      expect(v.partFavori, isNull);
      expect(v.titre, 'Le modèle ne départage pas les deux équipes');
    });

    test('une égalité parfaite ne désigne personne', () {
      final v = _v(50, 50);
      expect(v.indecis, isTrue);
      expect(v.favori, isNull);
    });

    test('le seuil est franchi à dix points d\'écart', () {
      expect(_v(54.5, 45.5).indecis, isTrue,  reason: '9 points : trop peu');
      expect(_v(55, 45).indecis,     isFalse, reason: '10 points : départagé');
    });

    test('le titre ne nomme jamais d\'équipe quand le modèle hésite', () {
      for (final v in [_v(50, 50), _v(52, 48), _v(47, 53)]) {
        expect(v.titre, isNot(contains('Elche')));
        expect(v.titre, isNot(contains('Barcelona')));
      }
    });
  });

  group('l\'écart est symétrique', () {
    test('17/83 et 83/17 donnent le même écart', () {
      expect(_v(17, 83).ecart, _v(83, 17).ecart);
    });

    test('mais pas le même favori', () {
      expect(_v(17, 83).favori, 'Barcelona');
      expect(_v(83, 17).favori, 'Elche');
    });
  });

  group('la couleur suit l\'équipe, pas le hasard', () {
    test('favoriADomicile correspond toujours au camp qui domine', () {
      expect(_v(83, 17).favoriADomicile, isTrue);
      expect(_v(17, 83).favoriADomicile, isFalse);
    });
  });
}

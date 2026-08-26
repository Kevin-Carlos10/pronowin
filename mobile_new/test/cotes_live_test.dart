import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/features/pronostics/presentation/providers/pronostics_provider.dart';

/// L'écran affichait « Over 7.50 » sur un marché de buts — 7,50 étant la
/// **cote**, pas le seuil. Le flux `/odds/live` ne place pas le seuil dans le
/// libellé, contrairement au flux pré-match pour lequel l'analyseur avait été
/// écrit, et il était donc perdu en chemin.
void main() {
  group('libellé d\'une cote en direct', () {
    test('porte le seuil quand il existe', () {
      const v = LiveOddValue(value: 'Over', odd: 1.90, ligne: '2.5');
      expect(v.libelle, 'Over 2.5');
    });

    test('reste inchangé quand le marché n\'a pas de seuil', () {
      const v = LiveOddValue(value: 'Home', odd: 1.45);
      expect(v.libelle, 'Home');
    });

    test('distingue deux lignes du même marché', () {
      const a = LiveOddValue(value: 'Over', odd: 1.48, ligne: '1.5');
      const b = LiveOddValue(value: 'Over', odd: 2.60, ligne: '3.5');
      expect(a.libelle, isNot(b.libelle),
        reason: 'sans le seuil, trois lignes Over/Under formaient trois '
                'rangées interchangeables');
    });

    test('un seuil négatif de handicap est conservé', () {
      const v = LiveOddValue(value: 'Home', odd: 1.95, ligne: '-0.5');
      expect(v.libelle, 'Home -0.5');
    });
  });

  group('lecture de la réponse serveur', () {
    Map<String, dynamic> reponse(List<Map<String, dynamic>> valeurs) => {
      'elapsed': 45,
      'opening_odd': 1.9,
      'markets': [ { 'name': 'Plus / Moins de buts', 'values': valeurs } ],
    };

    test('reprend le seuil publié', () {
      final d = LiveOddsData.fromJson(reponse([
        {'value': 'Over',  'odd': 1.9, 'ligne': '2.5'},
        {'value': 'Under', 'odd': 1.9, 'ligne': '2.5'},
      ]));
      expect(d.markets.first.values.first.libelle, 'Over 2.5');
      expect(d.elapsed, 45);
    });

    test('absence de seuil : le libellé ne s\'invente rien', () {
      final d = LiveOddsData.fromJson(reponse([{'value': 'Yes', 'odd': 1.7}]));
      expect(d.markets.first.values.first.ligne, isNull);
      expect(d.markets.first.values.first.libelle, 'Yes');
    });

    // Une chaîne vide n'est pas un seuil : la traiter comme tel produirait un
    // libellé « Over  » avec une espace suspendue.
    test('un seuil vide est traité comme absent', () {
      final d = LiveOddsData.fromJson(reponse([{'value': 'Over', 'odd': 1.9, 'ligne': ''}]));
      expect(d.markets.first.values.first.ligne, isNull);
      expect(d.markets.first.values.first.libelle, 'Over');
    });

    test('le nom du marché arrive déjà traduit du serveur', () {
      final d = LiveOddsData.fromJson(reponse([{'value': 'Over', 'odd': 1.9, 'ligne': '2.5'}]));
      expect(d.markets.first.name, 'Plus / Moins de buts');
    });
  });
}

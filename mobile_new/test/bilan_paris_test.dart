import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/shared/utils/bilan_paris.dart';

/// Ce que la carte « Mes stats bankroll » a le droit d'affirmer.
///
/// Le défaut corrigé ici : l'API renvoie `taux_reussite: 0` tant qu'aucun pari
/// n'est tranché, et l'écran affichait ce 0 comme un résultat mesuré — en
/// orange, à côté d'une série à 0 en rouge. Un compte qui venait de poser son
/// premier pari lisait « 0 % de réussite » là où il n'y avait pas de résultat.
void main() {
  group('BilanParis — un taux exige un dénominateur', () {
    test('le cas signalé : un seul pari, encore en attente', () {
      // Exactement les chiffres de l'écran rapporté : 1 pari joué, 0 gagné,
      // 0 perdu, et une API qui renvoie donc taux_reussite = 0.
      final b = BilanParis.depuisApi(const {
        'pronostics_suivis': 1,
        'paris_gagnes': 0,
        'paris_perdus': 0,
        'taux_reussite': 0.0,
        'serie_gagnante': 0,
      });

      expect(b.regles, 0, reason: 'aucun pari tranché');
      expect(b.enAttente, 1);
      expect(b.vierge, isTrue);
      expect(b.taux, isNull,
          reason: 'sans pari réglé, il n\'existe pas de taux de réussite');
      expect(b.sansAucunPari, isFalse, reason: 'la carte doit rester visible');
    });

    test('deux paris tranchés ne suffisent pas à énoncer un taux', () {
      // Ancienne règle : un taux dès le premier pari réglé. L'écran affichait
      // alors « 100 % de réussite » sur un unique pari gagné — exact, et sans
      // aucun sens, sur la statistique qui fait croire qu'une méthode marche.
      final b = BilanParis.depuisApi(const {
        'pronostics_suivis': 3,
        'paris_gagnes': 1,
        'paris_perdus': 1,
        'taux_reussite': 50.0,
        'serie_gagnante': 0,
      });

      expect(b.vierge, isFalse, reason: 'des paris sont bien tranchés');
      expect(b.taux, isNull, reason: 'deux réglés sous le seuil de cinq');
      expect(b.enAttente, 1, reason: '3 posés − 2 réglés');
      // Les comptes bruts restent disponibles : ils informent sans mesurer.
      expect(b.gagnes, 1);
      expect(b.perdus, 1);
    });

    test('le taux apparaît à partir du seuil', () {
      final b = BilanParis.depuisApi({
        'pronostics_suivis': BilanParis.echantillonMinimal,
        'paris_gagnes': 3,
        'paris_perdus': BilanParis.echantillonMinimal - 3,
        'taux_reussite': 60.0,
        'serie_gagnante': 2,
      });

      expect(b.echantillonSuffisant, isTrue);
      expect(b.taux, 60.0);
    });

    test('un pari de moins que le seuil se tait encore', () {
      final b = BilanParis.depuisApi({
        'pronostics_suivis': BilanParis.echantillonMinimal - 1,
        'paris_gagnes': BilanParis.echantillonMinimal - 1,
        'paris_perdus': 0,
        'taux_reussite': 100.0,
        'serie_gagnante': 4,
      });

      expect(b.echantillonSuffisant, isFalse);
      expect(b.taux, isNull, reason: 'c\'est ce « 100 % » qui trompait');
    });

    test('un taux réellement nul se distingue d\'un taux absent', () {
      // Un 0 % mesuré doit se distinguer d'un 0 % par défaut — mais il lui
      // faut d'abord assez de paris. Sur un seul perdu, « 0 % » serait aussi
      // trompeur que « 100 % » sur un seul gagné.
      final b = BilanParis.depuisApi({
        'pronostics_suivis': BilanParis.echantillonMinimal,
        'paris_gagnes': 0,
        'paris_perdus': BilanParis.echantillonMinimal,
        'taux_reussite': 0.0,
        'serie_gagnante': 0,
      });

      expect(b.vierge, isFalse);
      expect(b.taux, 0.0, reason: '0 % mesuré n\'est pas 0 % inconnu');
    });

    test('les paris remboursés comptent comme non tranchés', () {
      // 2 posés, 1 gagné, 0 perdu : le pari manquant est un PUSH. Il ne doit
      // pas gonfler le dénominateur du taux.
      final b = BilanParis.depuisApi(const {
        'pronostics_suivis': 2,
        'paris_gagnes': 1,
        'paris_perdus': 0,
        'taux_reussite': 100.0,
        'serie_gagnante': 1,
      });

      expect(b.regles, 1);
      expect(b.enAttente, 1);
      // C'est exactement l'état vu à l'écran — 2 joués, 1 gagné, 0 perdu —
      // qui affichait « 100 % de réussite ». Un seul pari tranché ne mesure
      // rien : le propos de ce test reste le dénominateur, pas le taux.
      expect(b.taux, isNull);
    });

    test('aucun pari du tout : la carte ne s\'affiche pas', () {
      final b = BilanParis.depuisApi(const {
        'pronostics_suivis': 0,
        'paris_gagnes': 0,
        'paris_perdus': 0,
        'taux_reussite': 0.0,
        'serie_gagnante': 0,
      });

      expect(b.sansAucunPari, isTrue);
    });

    test('des champs absents ou mal typés ne font pas tomber la lecture', () {
      final b = BilanParis.depuisApi(const {'pronostics_suivis': 4});

      expect(b.suivis, 4);
      expect(b.gagnes, 0);
      expect(b.vierge, isTrue);
      expect(b.taux, isNull);
    });

    test('enAttente ne devient jamais négatif si l\'API se contredit', () {
      // Défensif : si le serveur renvoyait plus de paris réglés que de paris
      // posés, mieux vaut 0 en attente qu'un nombre négatif affiché.
      final b = BilanParis.depuisApi(const {
        'pronostics_suivis': 1,
        'paris_gagnes': 3,
        'paris_perdus': 2,
        'taux_reussite': 60.0,
        'serie_gagnante': 1,
      });

      expect(b.enAttente, 0);
    });
  });
}

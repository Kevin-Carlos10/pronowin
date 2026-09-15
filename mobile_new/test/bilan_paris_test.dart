import 'dart:io';
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

  // ── Ce qu'on dit quand on ne dit pas le taux ────────────────────────────
  //
  // Le tiret est le bon choix sous le seuil, mais il laissait l'utilisateur
  // devant une case vide sans raison. La phrase a d'abord été écrite sur
  // l'écran du compte ; la carte qui la portait en est partie, et les deux
  // autres écrans qui affichent le même tiret ne disaient toujours rien. Elle
  // vit désormais ici, une fois, pour les trois.
  group('mention avant le taux', () {
    BilanParis b(int gagnes, int perdus, {int suivis = 0}) => BilanParis(
          suivis: suivis == 0 ? gagnes + perdus : suivis,
          gagnes: gagnes, perdus: perdus, tauxBrut: 0, serie: 0);

    test('au-dessus du seuil, on ne dit rien', () {
      // Une explication affichée en permanence serait un reproche permanent.
      expect(b(6, 2).mentionAvantLeTaux, isNull);
      expect(b(3, 2).mentionAvantLeTaux, isNull);
    });

    test('un seul pari manque : on le dit au singulier', () {
      expect(b(3, 1).mentionAvantLeTaux,
          'Taux de réussite dès le prochain pari tranché');
    });

    test('plusieurs manquent : on les compte', () {
      expect(b(1, 0).mentionAvantLeTaux, contains('encore 4'));
      expect(b(1, 0).mentionAvantLeTaux, contains('5 paris tranchés'));
    });

    test('aucun pari tranché : on nomme l attente, pas le seuil', () {
      // Annoncer « encore 5 » à quelqu'un dont les paris ne sont pas encore
      // joués lui reprocherait de ne pas avoir assez parié.
      expect(b(0, 0, suivis: 3).mentionAvantLeTaux,
          '3 paris en attente de résultat');
      expect(b(0, 0, suivis: 1).mentionAvantLeTaux,
          'Pari en attente de résultat');
    });

    test('aucun pari du tout : la carte ne s affiche pas', () {
      // Contrepartie : sans ce point, un compte vierge afficherait
      // « Pari en attente » sans avoir jamais parié.
      expect(b(0, 0).sansAucunPari, isTrue);
    });
  });

  // ── Les deux écrans qui retiennent le taux ──────────────────────────────
  //
  // Contrôle de source, et il faut le dire : aucun banc ne monte ces écrans,
  // donc rien ne prouve ici que la phrase s'affiche vraiment. Il attrape une
  // suppression, pas une régression d'affichage. C'est peu — c'est mieux que
  // rien, et la règle elle-même est éprouvée juste au-dessus.
  test('les écrans qui retiennent le taux ne laissent pas un tiret nu', () {
    final bankroll = File(
      'lib/features/bankroll/presentation/pages/bankroll_page.dart',
    ).readAsStringSync();
    expect(bankroll, contains('mentionAvantLeTaux'),
        reason: 'cet écran est désormais le seul endroit où ce bilan se lit ; '
                'il doit dire pourquoi le taux est retenu');

    final accueil = File(
      'lib/features/accueil/presentation/pages/accueil/encarts.dart',
    ).readAsStringSync();
    expect(accueil, contains('if (bilanCarte.taux != null)'),
        reason: 'la carte est trop étroite pour expliquer : elle masque le '
                'taux plutôt que de montrer un « — win » qui reste muet');
  });
}

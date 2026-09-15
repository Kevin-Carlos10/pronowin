import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/shared/utils/resume_paris.dart';

/// Disponible, engagé, résultat net : trois grandeurs, trois noms.
///
/// ── Le chiffre le plus visible disait le contraire de la situation ────────
///
/// La carte affichait `solde − budget` sous une flèche verte ou rouge, comme
/// un gain. Or la mise part du solde **au moment où le pari est posé** :
/// engager 2 000 sur un budget de 10 000 faisait afficher « −2 000 » en rouge
/// alors que rien n'était perdu, et que les paris pouvaient tous être
/// gagnants. La barre de progression reculait pour la même raison.
///
/// ── Et la courbe racontait une quatrième histoire ─────────────────────────
///
/// Intitulée « Évolution du solde », elle partait du budget initial et y
/// ajoutait le profit de chaque pari réglé. Elle ne déduisait pas les mises en
/// cours — son dernier point ne correspondait donc pas au solde affiché juste
/// au-dessus. Elle ignorait aussi les réinitialisations : après un
/// « Réinitialiser », elle repartait de l'ancien budget comme si de rien
/// n'était.
///
/// Une vraie courbe de solde demanderait un journal des mouvements, qui
/// n'existe pas et qu'on ne peut pas reconstituer pour le passé — les
/// réinitialisations n'ont jamais été enregistrées. Elle montre donc ce
/// qu'elle sait : le résultat net cumulé, en partant de zéro, et elle le dit.
void main() {
  group('le résumé porte les trois grandeurs', () {
    test('les mises en cours sont lues', () {
      final r = ResumeParis.depuisApi(const {
        'total': 9,
        'profit_net': 1500,
        'mises_en_cours': 4000,
      });

      expect(r.misesEnCours, 4000);
      expect(r.profitNet, 1500);
    });

    test('un backend plus ancien les met à zéro', () {
      // Le repli doit être neutre : compter un engagement inconnu fausserait
      // la barre dans l'autre sens.
      final r = ResumeParis.depuisApi(const {'total': 3});

      expect(r.misesEnCours, 0);
    });
  });

  group('la carte nomme ce qu\'elle affiche', () {
    late String page;

    setUpAll(() {
      page = File('lib/features/bankroll/presentation/pages/bankroll_page.dart')
          .readAsStringSync();
    });

    test('« solde − budget » ne sert plus de résultat', () {
      // C'est le calcul fautif. Il ne doit plus exister sur cette page.
      expect(
        page.contains('bankroll.currentBalance - bankroll.totalBudget'),
        isFalse,
        reason: 'ce calcul comptait les mises en cours comme une perte',
      );
    });

    test('les trois grandeurs sont distinctes et nommées', () {
      expect(page, contains('Disponible'));
      expect(page, contains("Key('bankroll-engage')"));
      expect(page, contains("Key('bankroll-resultat-net')"));
      expect(page, contains('de résultat net'));
    });

    test('l\'engagé vient du résumé, avec repli local', () {
      expect(page, contains('resume?.misesEnCours'));
      expect(page, contains('b.stakedAmount'),
          reason: 'le repli somme les mises en cours depuis la liste');
    });

    test('la barre compte le capital, pas le seul disponible', () {
      // `disponible / budget` reculait dès qu'un pari était posé.
      expect(page, contains('bankroll.currentBalance + misesEnCours'));
    });
  });

  group('la courbe dit ce qu\'elle montre', () {
    late String page;

    setUpAll(() {
      page = File('lib/features/bankroll/presentation/pages/bankroll_page.dart')
          .readAsStringSync();
    });

    test('elle ne s\'intitule plus « Évolution du solde »', () {
      expect(page.contains("Text('Évolution du solde'"), isFalse);
      expect(page, contains('Résultat net cumulé'));
    });

    test('elle part de zéro, pas du budget', () {
      // Partir du budget en faisait une courbe de solde qui n'en était pas
      // une : elle ne déduisait jamais les mises en cours.
      expect(page, contains('const FlSpot(0, 0)'));
      expect(page.contains('double running = bankroll.totalBudget;'), isFalse);
    });

    test('son sous-titre écarte la lecture « solde »', () {
      expect(page, contains('hors mises en cours'));
    });
  });
}

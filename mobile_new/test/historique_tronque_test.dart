import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/features/bankroll/presentation/providers/bankroll_provider.dart';
import 'package:pronowin/shared/utils/resume_paris.dart';

/// Un bilan porte sur tout l'historique ; la liste, sur ce qu'on affiche.
///
/// L'API renvoie au plus cinquante paris. La limite n'était pas le défaut —
/// charger mille lignes sur un téléphone n'a pas de sens. Le défaut était
/// qu'elle ne se voyait pas : l'écran calculait ses compteurs, son taux de
/// réussite et sa courbe **depuis cette liste**, et les présentait comme le
/// bilan complet.
///
/// Au cinquante-et-unième pari, tous ces chiffres devenaient faux, sans
/// avertissement, sans « 50 derniers », sans période.
///
/// Le pendant serveur est `backend/src/__tests__/resume_paris.test.ts`.
void main() {
  /// Une réponse d'API minimale, avec [affiches] paris dans la liste.
  Map<String, dynamic> reponse({
    required int total,
    required int affiches,
    Map<String, dynamic>? resume,
  }) =>
      {
        'id': 'b1',
        'total_budget': 100000,
        'current_balance': 98000,
        'currency': 'XOF',
        if (resume != null || total > 0)
          'resume': resume ??
              {
                'total': total,
                'gagnes': 70,
                'perdus': 40,
                'rembourses': 5,
                'en_attente': total - 115,
                'taux_reussite': 64,
                'profit_net': 12000,
              },
        'paris_affiches': affiches,
        'bets': List.generate(
          affiches,
          (i) => {
            'id': 'bet$i',
            'pronostic_id': 'p$i',
            'staked_amount': 1000,
            'suggested_amount': 1000,
            'odds_used': 2.0,
            'potential_gain': 2000,
            'result': 'WIN',
            'profit': 1000,
            'created_at': '2026-09-01T12:00:00.000Z',
            'match': {
              'id': 'm$i',
              'home_team': 'A',
              'away_team': 'B',
              'match_date': '2026-09-01T18:00:00.000Z',
              'league': 'L1',
            },
            'prediction_label': '1X2',
            'confidence_score': 4,
          },
        ),
      };

  group('le bilan du serveur est retenu', () {
    test('il porte sur tout, la liste sur une partie', () {
      final d = BankrollData.fromJson(reponse(total: 120, affiches: 50));

      expect(d.resume, isNotNull);
      expect(d.resume!.total, 120);
      expect(d.bets.length, 50);
      expect(d.parisAffiches, 50);
      expect(d.historiqueTronque, isTrue);
    });

    test('rien n\'est tronqué quand tout tient', () {
      // Contrepartie : la mention ne doit pas s'afficher en permanence. Un
      // avertissement qui apparaît toujours cesse d'être lu.
      final d = BankrollData.fromJson(reponse(total: 12, affiches: 12));

      expect(d.historiqueTronque, isFalse);
    });

    test('un backend plus ancien ne vide pas la page', () {
      // Le mobile est publié séparément. Sans repli, une réponse sans `resume`
      // laisserait l'écran sans aucun chiffre.
      final brut = reponse(total: 0, affiches: 3)..remove('resume');
      final d = BankrollData.fromJson(brut);

      expect(d.resume, isNull);
      expect(d.bets.length, 3);
      expect(d.parisAffiches, 3, reason: 'à défaut, la longueur de la liste');
      expect(d.historiqueTronque, isFalse,
          reason: 'sans bilan complet, on ne peut rien affirmer de tronqué');
    });
  });

  group('le résumé se lit sans supposer les clés', () {
    test('les valeurs sont reprises telles quelles', () {
      final r = ResumeParis.depuisApi(const {
        'total': 120,
        'gagnes': 70,
        'perdus': 40,
        'rembourses': 5,
        'en_attente': 5,
        'taux_reussite': 64,
        'profit_net': 12000.5,
      });

      expect(r.total, 120);
      expect(r.gagnes, 70);
      expect(r.perdus, 40);
      expect(r.rembourses, 5);
      expect(r.enAttente, 5);
      expect(r.tauxBrut, 64);
      expect(r.profitNet, 12000.5);
    });

    test('une clé manquante vaut zéro, sans lever', () {
      // Un bilan partiel vaut mieux qu'un écran en erreur.
      final r = ResumeParis.depuisApi(const {'total': 3});

      expect(r.total, 3);
      expect(r.gagnes, 0);
      expect(r.profitNet, 0);
    });
  });

  /// Le modèle ne sert à rien si l'écran continue de compter tout seul.
  group("l'écran s'appuie sur le bilan complet", () {
    late String page;

    setUpAll(() {
      page = File('lib/features/bankroll/presentation/pages/bankroll_page.dart')
          .readAsStringSync();
    });

    test('le bilan affiché vient de `resume`', () {
      expect(page, contains('bankroll.resume'));
      expect(page, contains('resume.total'));
    });

    test('la troncature est dite à l\'écran', () {
      expect(page, contains('historiqueTronque'));
      expect(page, contains("Key('bankroll-historique-tronque')"));
    });

    test('le repli local subsiste', () {
      // Retirer le repli rendrait la page vide — ou la ferait lever — devant
      // un backend plus ancien.
      //
      // Chercher `resume != null` ne suffisait pas : une assertion non nulle
      // (`bankroll.resume!`) laisse cette chaîne en place tout en supprimant
      // le repli. Vérifié en l'introduisant. On compte donc les deux branches.
      final branches = 'BilanParis('.allMatches(page).length;
      expect(branches, greaterThanOrEqualTo(2),
          reason: 'il faut le bilan du serveur ET le calcul de repli');

      expect(page.contains('bankroll.resume!;'), isFalse,
          reason: 'une assertion non nulle supprime le repli');
    });
  });
}

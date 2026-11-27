import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pronowin/core/theme/app_theme.dart';
import 'package:pronowin/features/bankroll/domain/historique.dart';
import 'package:pronowin/features/bankroll/presentation/pages/bankroll_page.dart';
import 'package:pronowin/features/bankroll/presentation/providers/bankroll_provider.dart';

import 'aides/banc_ecran.dart';

/// La courbe du résultat net et « Cette semaine » (27 novembre 2026).
///
/// L'écran les calculait sur les cinquante dernières mises simples reçues,
/// sans les combinés ni les couvertures : depuis la 1.0.42, la courbe ne
/// finissait plus sur le résultat net affiché juste au-dessus. Le serveur les
/// calcule désormais sur tout l'historique
/// (`backend/src/__tests__/historique_bankroll.test.ts`) ; l'écran ne fait
/// plus qu'afficher, et ne recalcule que face à un serveur plus ancien.
void main() {
  setUpAll(preparerBanc);

  final maintenant = DateTime(2026, 11, 27, 12);

  Map<String, dynamic> pari(String id, {String? result, double? profit, DateTime? regle, DateTime? pose, Map<String, dynamic>? couverture}) => {
        'id': id, 'pronostic_id': 'p$id', 'staked_amount': 1000, 'suggested_amount': 1000,
        'odds_used': 2.0, 'potential_gain': 2000, 'result': result, 'profit': profit,
        'settled_at': regle?.toUtc().toIso8601String(),
        'created_at': (pose ?? maintenant.subtract(const Duration(days: 12))).toUtc().toIso8601String(),
        'couverture_enregistree': couverture,
        'match': {'id': 'm$id', 'home_team': 'A', 'away_team': 'B', 'match_date': '2026-11-20T18:00:00.000Z', 'league': 'L1'},
        'prediction_label': 'Plus de 2,5 buts', 'confidence_score': 4,
      };

  Map<String, dynamic> couverture(double profit) => {
        'id': 'c', 'selection_fr': 'Moins de 2,5 buts', 'selection_en': 'Under 2.5 goals', 'strategie': 'gain_egal',
        'mise': 300, 'cote': 4, 'result': profit > 0 ? 'WIN' : 'LOSS', 'profit': profit,
      };

  Map<String, dynamic> reponse({Map<String, dynamic>? courbe, Map<String, dynamic>? semaine}) => {
        'id': 'b1', 'total_budget': 10000, 'current_balance': 12100, 'currency': 'XOF',
        'paris_affiches': 3,
        'bets': [
          // Posé il y a dix jours, gagné hier : il compte dans la semaine.
          pari('1', result: 'WIN', profit: 1000, regle: maintenant.subtract(const Duration(days: 1)),
              pose: maintenant.subtract(const Duration(days: 10))),
          // Gagné, mais couvert : +800 − 300.
          pari('2', result: 'WIN', profit: 800, regle: maintenant.subtract(const Duration(days: 2)), couverture: couverture(-300)),
          // Réglé il y a huit jours : hors de la semaine.
          pari('3', result: 'LOSS', profit: -500, regle: maintenant.subtract(const Duration(days: 8))),
        ],
        'combines': [
          {
            'id': 'k1', 'staked_amount': 500, 'odds_used': 5.0, 'potential_gain': 2500, 'note_retenue': 3,
            'result': 'WIN', 'retour': 2500, 'profit': 2000,
            'settled_at': maintenant.subtract(const Duration(days: 4)).toUtc().toIso8601String(),
            'created_at': maintenant.subtract(const Duration(days: 25)).toUtc().toIso8601String(),
            'couverture_enregistree': null, 'selections': <Map<String, dynamic>>[],
          },
        ],
        'courbe': ?courbe,
        'semaine': ?semaine,
      };

  group('le repli local, face à un serveur qui n\'envoie pas la courbe', () {
    test('dans l\'ordre des règlements, combinés et couvertures compris', () {
      final d = BankrollData.fromJson(reponse());
      expect(d.courbeServeur, isNull);
      expect(d.courbe.reglees, 4);
      // −500 (il y a 8 j), +2 000 (combiné, 4 j), +500 (couvert, 2 j), +1 000 (hier).
      expect(d.courbe.points.map((p) => p.cumul), [-500, 1500, 2000, 3000]);
      expect(d.courbe.points[1].combine, isTrue);
      expect(d.courbe.tronquee, isFalse);
    });

    test('la semaine d\'après la date du règlement', () {
      final s = BankrollData.fromJson(reponse()).semaine(maintenant);
      expect([s.paris, s.gagnes, s.perdus, s.combines, s.combinesGagnes], [2, 2, 0, 1, 1]);
      expect(s.profit, 3500);
    });
  });

  group('ce que le serveur envoie est retenu', () {
    test('la courbe et la semaine', () {
      final d = BankrollData.fromJson(reponse(
        courbe: {
          'reglees': 250, 'cumul_depart': 600,
          'points': [
            {'le': '2026-11-25T10:00:00.000Z', 'cumul': 1100, 'genre': 'pari'},
            {'le': '2026-11-26T10:00:00.000Z', 'cumul': 2100, 'genre': 'combine'},
          ],
        },
        semaine: {'paris': 3, 'gagnes': 2, 'perdus': 0, 'rembourses': 1, 'combines': 1, 'combines_gagnes': 1, 'profit': 2900},
      ));
      expect(d.courbe.reglees, 250);
      expect(d.courbe.depart, 600);
      expect(d.courbe.fin, 2100);
      expect(d.courbe.tronquee, isTrue);
      expect(d.courbe.points.last.combine, isTrue);
      final s = d.semaine(maintenant);
      expect([s.paris, s.rembourses, s.combines], [3, 1, 1]);
      expect(s.profit, 2900);
    });

    test('une semaine sans règlement est vide', () {
      expect(BilanSemaine.depuisApi(const {'paris': 0, 'combines': 0, 'profit': 0}).vide, isTrue);
      expect(BilanSemaine.locale(const [], maintenant).vide, isTrue);
    });
  });

  testWidgets('la page : le nombre de mises, la mention des dernières, et la ligne des combinés', (t) async {
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final d = BankrollData.fromJson(reponse(
      courbe: {
        'reglees': 250, 'cumul_depart': 600,
        'points': [
          {'le': '2026-11-25T10:00:00.000Z', 'cumul': 1100, 'genre': 'pari'},
          {'le': '2026-11-26T10:00:00.000Z', 'cumul': 2100, 'genre': 'combine'},
        ],
      },
      semaine: {'paris': 3, 'gagnes': 2, 'perdus': 0, 'rembourses': 1, 'combines': 1, 'combines_gagnes': 1, 'profit': 2900},
    ));
    await t.pumpWidget(ProviderScope(
      overrides: [...donneesCommunes(), bankrollProvider.overrideWith((ref) async => d)],
      child: MaterialApp(theme: AppTheme.light, home: const BankrollPage()),
    ));
    await t.pump();
    await t.pump(const Duration(seconds: 1));

    expect(find.text('250 mises réglées'), findsOneWidget);
    expect(find.text('Les 2 dernières mises sur 250'), findsOneWidget);
    expect(find.byKey(const Key('semaine-paris')), findsOneWidget);
    expect(find.text('Combinés : 1 · Gagnés : 1'), findsOneWidget);
    // Le résultat de la semaine, combiné compris, tel que le serveur le donne.
    final profit = t.widget<Text>(find.byKey(const Key('semaine-profit'))).data!;
    expect(profit.startsWith('+'), isTrue);
    expect(profit.replaceAll(RegExp(r'\D'), ''), '2900');
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronowin/core/config/sans_pari.dart';
import 'package:pronowin/core/theme/app_theme.dart';
import 'package:pronowin/features/bankroll/domain/couverture.dart';
import 'package:pronowin/features/bankroll/presentation/providers/bankroll_provider.dart';
import 'package:pronowin/features/parametres/presentation/pages/reglages_sous_pages.dart';
import 'package:pronowin/features/pronostics/data/models/match_model.dart';
import 'package:pronowin/features/pronostics/presentation/pages/match_detail_page.dart';
import 'package:pronowin/features/pronostics/presentation/providers/fiche_match_provider.dart';
import 'package:pronowin/features/pronostics/presentation/providers/pronostics_provider.dart';

import 'aides/banc_ecran.dart';

/// L'alerte de couverture (26 novembre 2026) : combien miser sur l'évènement
/// inverse d'une sélection enregistrée, quand les cotes bougent.
void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR');
    await initializeDateFormatting('fr');
    await preparerBanc();
  });

  group('le calcul, le même que le serveur', () {
    test('1 000 F à 2,00 ; l\'inverse à 4,00 : 500 F dessus, +500 F garantis', () {
      final c = calculerCouverture(1000, 2, 4)!;
      expect([c.miseCouverture, c.gainGaranti, c.gainPotentiel, c.part], [500, 500, 1000, 0.5]);
      expect(c.atteint(50), isTrue);
      expect(c.atteint(70), isFalse);
    });

    test('arrondi au franc, au centime pour l\'euro ; cotes resserrées : rien de garanti', () {
      expect(calculerCouverture(1000, 1.85, 3.1)!.miseCouverture, 597);
      expect(calculerCouverture(10, 2, 3, pas: pasDeDevise('EUR'))!.miseCouverture, closeTo(6.67, 0.001));
      expect(pasDeDevise('XOF'), 1);
      final serre = calculerCouverture(1000, 2, 1.9)!;
      expect(serre.gainGaranti, lessThan(0));
      expect(serre.atteint(30), isFalse);
      expect(calculerCouverture(0, 2, 3), isNull);
    });

    test('l\'iPhone reste sans pari par défaut : la compilation seule le change', () {
      expect(sansPariIos, isTrue);
    });
  });

  group('la carte « Couvrir ma mise »', () {
    Map<String, dynamic> fiche() => {
      'id': 'm', 'league': 'Premier League', 'league_country': 'GB',
      'home_team': 'Arsenal', 'away_team': 'Chelsea', 'status': 'live',
      'match_date': DateTime.now().subtract(const Duration(minutes: 20)).toUtc().toIso8601String(),
      'home_score': 1, 'away_score': 0,
      'has_pronostic': true, 'prediction_type': 'over25', 'prediction_label': 'Total buts : Plus de 2.5',
      'odds_recommended': 2.0, 'confidence_score': 4, 'is_premium': false,
    };
    final pari = BankrollBet(
      id: 'b1', pronosticId: 'm', matchId: 'm', stakedAmount: 1000, suggestedAmount: 1000,
      oddsUsed: 2, potentialGain: 2000, createdAt: DateTime(2026, 11, 26), homeTeam: 'Arsenal',
      awayTeam: 'Chelsea', league: 'Premier League', predictionLabel: 'Plus de 2.5', confidenceScore: 4,
      currency: 'XOF');

    Future<void> ouvrir(WidgetTester t, Map<String, dynamic>? couverture,
        {bool avecPari = true, bool iphone = false}) async {
      SharedPreferences.setMockInitialValues({'astuce_suivre_match_vue': true});
      t.view.physicalSize = const Size(1170, 2532); t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(ProviderScope(overrides: [...donneesCommunes(),
        sansPariProvider.overrideWithValue(iphone),
        bankrollProvider.overrideWith((ref) async => BankrollData(
          id: 'br', totalBudget: 100000, currentBalance: 99000, currency: 'XOF',
          bets: avecPari ? [pari] : const [])),
        couvertureMiseProvider('m').overrideWith((ref) async => couverture),
        matchDetailProvider('m').overrideWith((ref) async => MatchModel.fromJson(fiche())),
        matchStatsProvider('m').overrideWith((ref) async => null),
        lineupsProvider('m').overrideWith((ref) async => const LineupsData(available: false)),
        injuriesProvider('m').overrideWith((ref) async => []),
        h2hProvider('m').overrideWith((ref) async => throw Exception('none')),
        playerRatingsProvider('m').overrideWith((ref) async => []),
        articlesDuMatchProvider('m').overrideWith((ref) async => null),
      ], child: MaterialApp.router(theme: AppTheme.light, routerConfig: GoRouter(routes: [
        GoRoute(path: '/', builder: (_, _) => const MatchDetailPage(matchId: 'm')),
      ]))));
      for (var i = 0; i < 20; i++) { await t.pump(const Duration(milliseconds: 100)); }
    }

    final serveur = {
      'disponible': true, 'mise': 1000, 'cote': 2, 'devise': 'XOF', 'seuil': 50,
      'inverse_fr': 'Moins de 2,5 buts', 'inverse_en': 'Under 2.5 goals', 'source': 'direct',
      'cote_inverse': 4.0, 'mise_couverture': 500, 'gain_garanti': 500, 'gain_potentiel': 1000,
      'part': 0.5, 'seuil_atteint': true,
    };
    Finder carte(Finder f) => find.descendant(of: find.byKey(const Key('couverture-m')), matching: f);

    testWidgets('la cote du moment : combien miser, et ce qui est garanti', (t) async {
      await ouvrir(t, serveur);
      expect(find.byKey(const Key('couverture-m')), findsOneWidget);
      expect(carte(find.text('Seuil atteint')), findsOneWidget);
      expect(carte(find.textContaining('« Moins de 2,5 buts » est à 4.00 (en direct)')), findsOneWidget);
      expect(t.widget<Text>(find.byKey(const Key('couverture-mise'))).data, contains('Mise 500'));
      expect(t.widget<Text>(find.byKey(const Key('couverture-gain'))).data, contains('+500'));
      expect(t.takeException(), isNull);
    });

    testWidgets('la cote de son bookmaker refait le calcul ; trop basse, rien de garanti', (t) async {
      await ouvrir(t, serveur);
      final champ = find.byKey(const Key('couverture-cote-m'));
      await t.ensureVisible(champ);
      await t.enterText(champ, '5');
      await t.pump();
      expect(t.widget<Text>(find.byKey(const Key('couverture-mise'))).data, contains('Mise 400'));
      await t.enterText(champ, '1,8');
      await t.pump();
      expect(find.byKey(const Key('couverture-pas-encore')), findsOneWidget);
      expect(carte(find.text('Seuil atteint')), findsNothing);
    });

    testWidgets('cote indisponible : la carte demande celle du bookmaker', (t) async {
      await ouvrir(t, {...serveur, 'disponible': false, 'raison': 'cote', 'cote_inverse': null, 'source': null});
      expect(carte(find.textContaining('indisponible pour l’instant')), findsOneWidget);
      expect(find.byKey(const Key('couverture-mise')), findsNothing);
    });

    testWidgets('sans mise, marché sans inverse, ou iPhone sans pari : pas de carte', (t) async {
      await ouvrir(t, serveur, avecPari: false);
      expect(find.byKey(const Key('couverture-m')), findsNothing);
      await t.pumpWidget(const SizedBox());
      await ouvrir(t, {'disponible': false, 'raison': 'marche'});
      expect(find.byKey(const Key('couverture-m')), findsNothing);
      await t.pumpWidget(const SizedBox());
      await ouvrir(t, serveur, iphone: true);
      expect(find.byKey(const Key('couverture-m')), findsNothing);
    });
  });

  group('les réglages', () {
    Future<void> monter(WidgetTester t, {bool iphone = false}) async {
      SharedPreferences.setMockInitialValues({});
      await t.pumpWidget(ProviderScope(
        overrides: [...donneesCommunes(), sansPariProvider.overrideWithValue(iphone)],
        child: MaterialApp(theme: AppTheme.light, home: const NotificationsReglagesPage()),
      ));
      await t.pumpAndSettle();
    }

    testWidgets('l\'alerte et son seuil (50 % par défaut)', (t) async {
      await monter(t);
      await t.scrollUntilVisible(find.byKey(const Key('notif-couverture')), 200);
      expect(find.text('Alerte de couverture'), findsOneWidget);
      expect(find.text('Dès 50 % du gain potentiel garantis'), findsOneWidget);
    });

    testWidgets('pas sur l\'iPhone sans pari', (t) async {
      await monter(t, iphone: true);
      expect(find.byKey(const Key('notif-couverture')), findsNothing);
    });
  });
}

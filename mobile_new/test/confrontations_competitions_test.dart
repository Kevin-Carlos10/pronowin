import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronowin/core/theme/app_theme.dart';
import 'package:pronowin/features/auth/presentation/providers/auth_provider.dart';
import 'package:pronowin/features/pronostics/domain/entities/match_entity.dart';
import 'package:pronowin/features/pronostics/presentation/pages/confrontation_page.dart';
import 'package:pronowin/features/pronostics/presentation/pages/match_detail_page.dart';
import 'package:pronowin/features/pronostics/presentation/pages/search_page.dart';
import 'package:pronowin/features/pronostics/presentation/providers/pronostics_provider.dart';
import 'package:pronowin/features/pronostics/presentation/providers/recherche_provider.dart';

import 'aides/banc_ecran.dart';

/// Les confrontations directes s'ouvrent en détail, et un championnat se
/// cherche et se suit depuis la recherche (15 novembre 2026).
void main() {
  setUpAll(() async => preparerBanc());

  final apercu = H2HMatchResult(
    date: DateTime(2025, 3, 1, 20), homeTeam: 'Arsenal', awayTeam: 'Chelsea',
    homeScore: 2, awayScore: 1, winner: 'HOME_TEAM', league: 'Premier League', fixtureId: 777);

  Confrontation detail({String? matchId}) => Confrontation(
    fixtureId: 777, matchId: matchId, date: DateTime(2025, 3, 1, 20),
    league: 'Premier League', round: 'Regular Season - 27', venue: 'Emirates Stadium',
    homeTeam: 'Arsenal', awayTeam: 'Chelsea', homeScore: 2, awayScore: 1, mtHome: 1, mtAway: 0,
    stats: const MatchStatsData(
      fixtureId: 777, homeTeam: 'Arsenal', awayTeam: 'Chelsea',
      events: [
        MatchEvent(minute: 12, team: 'Arsenal', player: 'B. Saka', type: 'Goal', detail: 'Normal Goal'),
        MatchEvent(minute: 55, team: 'Chelsea', player: 'C. Palmer', type: 'Goal', detail: 'Normal Goal'),
        MatchEvent(minute: 80, team: 'Arsenal', player: 'K. Havertz', type: 'Goal', detail: 'Normal Goal'),
      ],
      stats: [MatchStat(label: 'Ball Possession', home: '58%', away: '42%'),
              MatchStat(label: 'Total Shots', home: 14, away: 9)],
    ),
  );

  testWidgets('une confrontation s\'ouvre en détail : score, mi-temps, faits, statistiques', (t) async {
    await t.pumpWidget(ProviderScope(
      overrides: [
        h2hProvider('m').overrideWith((ref) async => H2HData(
          homeTeam: 'Arsenal', awayTeam: 'Chelsea', homeWins: 1, awayWins: 0, draws: 0,
          totalMatches: 1, matches: [apercu])),
        confrontationProvider((matchId: 'm', fixtureId: 777)).overrideWith((ref) async => detail()),
      ],
      child: MaterialApp(theme: AppTheme.dark,
        home: Scaffold(body: SingleChildScrollView(child: confrontationsSeules('m')))),
    ));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('confrontation-777')));
    await t.pumpAndSettle();
    expect(find.byType(ConfrontationPage), findsOneWidget);
    expect(find.text('2 - 1'), findsWidgets);
    expect(find.byKey(const Key('confrontation-mi-temps')), findsOneWidget);
    expect(find.byKey(const Key('confrontation-faits')), findsOneWidget);
    expect(find.text('B. Saka'), findsOneWidget);
    await t.scrollUntilVisible(find.byKey(const Key('confrontation-stats')), 200,
        scrollable: find.byType(Scrollable).last);
    expect(find.byKey(const Key('confrontation-stats')), findsOneWidget);
    // Pas dans notre base : pas de fiche complète à proposer.
    expect(find.byKey(const Key('confrontation-fiche')), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('dans notre base, la fiche complète du match est proposée', (t) async {
    await t.pumpWidget(ProviderScope(
      overrides: [confrontationProvider((matchId: 'm', fixtureId: 777)).overrideWith((ref) async => detail(matchId: 'loc'))],
      child: MaterialApp(theme: AppTheme.dark,
        home: ConfrontationPage(matchId: 'm', fixtureId: 777, apercu: apercu)),
    ));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('confrontation-fiche')), findsOneWidget);
  });

  testWidgets('sans identifiant (ancien serveur), la ligne ne s\'ouvre pas', (t) async {
    final sansId = H2HMatchResult(date: DateTime(2025, 3, 1), homeTeam: 'Arsenal', awayTeam: 'Chelsea',
      homeScore: 2, awayScore: 1, winner: 'HOME_TEAM', league: 'Premier League');
    await t.pumpWidget(ProviderScope(
      overrides: [h2hProvider('m').overrideWith((ref) async => H2HData(
        homeTeam: 'Arsenal', awayTeam: 'Chelsea', homeWins: 1, awayWins: 0, draws: 0,
        totalMatches: 1, matches: [sansId]))],
      child: MaterialApp(theme: AppTheme.dark,
        home: Scaffold(body: SingleChildScrollView(child: confrontationsSeules('m')))),
    ));
    await t.pumpAndSettle();
    expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
  });

  group('chercher et suivre une compétition', () {
    Future<void> monter(WidgetTester t, {bool connecte = true}) async {
      SharedPreferences.setMockInitialValues({});
      await t.pumpWidget(ProviderScope(
        overrides: [
          ...donneesCommunes(),
          if (!connecte) effectiveLoggedInProvider.overrideWithValue(false),
          rechercheMatchsProvider.overrideWith((ref, terme) async => const <MatchEntity>[]),
          rechercheEquipesJoueursProvider.overrideWith((ref, terme) async => const ResultatsRecherche(
            competitions: [CompetitionTrouvee(code: 'PD', nom: 'La Liga', logo: 'es.png', pays: 'Spain')])),
        ],
        child: MaterialApp(theme: AppTheme.dark, home: const SearchPage()),
      ));
      await t.pump();
      await t.enterText(find.byType(TextField), 'liga');
      for (var i = 0; i < 5; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('la compétition apparaît, et se suit d\'une touche', (t) async {
      await monter(t);
      expect(find.text('COMPÉTITIONS'), findsOneWidget);
      expect(find.byKey(const Key('competition-PD')), findsOneWidget);
      final bouton = find.byKey(const Key('suivre-ligue-La Liga'));
      expect(find.descendant(of: bouton, matching: find.byIcon(Icons.push_pin_outlined)), findsOneWidget);
      await t.tap(bouton);
      for (var i = 0; i < 3; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(find.descendant(of: bouton, matching: find.byIcon(Icons.push_pin_rounded)), findsOneWidget);
      expect(find.text('Ajoutée à tes Suivis, onglet Ligues'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 5));
    });

    testWidgets('sans compte, on est invité à se connecter', (t) async {
      await monter(t, connecte: false);
      await t.tap(find.byKey(const Key('suivre-ligue-La Liga')));
      await t.pump();
      expect(find.text('Connecte-toi pour suivre une compétition.'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 5));
    });
  });
}

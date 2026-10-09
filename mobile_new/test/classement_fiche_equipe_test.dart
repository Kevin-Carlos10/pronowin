// Dans la fiche de match, une équipe du classement — ou un adversaire de la
// forme récente — ouvre la fiche de cette équipe (demande du 9 octobre 2026).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pronowin/core/theme/app_theme.dart';
import 'package:pronowin/features/pronostics/data/models/match_model.dart';
import 'package:pronowin/features/pronostics/presentation/pages/match_detail_page.dart';
import 'package:pronowin/features/pronostics/presentation/providers/fiche_match_provider.dart';
import 'package:pronowin/features/pronostics/presentation/providers/pronostics_provider.dart';
import 'aides/banc_ecran.dart';

StandingRow _ligne(int rang, String nom, int? id) => StandingRow(
  rank: rang, teamName: nom, teamId: id, played: 5, win: 3, draw: 1, lose: 1,
  goalsDiff: 4, points: 10, isMatchTeam: nom == 'Home');

Future<void> _monter(WidgetTester t) async {
  SharedPreferences.setMockInitialValues({});
  t.view.physicalSize = const Size(780, 1800); t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  final match = MatchModel.fromJson({'id': 'm', 'league': 'Premier League', 'league_country': 'PL',
    'home_team': 'Home', 'away_team': 'Away', 'status': 'upcoming',
    'match_date': '2026-10-18T14:00:00Z', 'has_pronostic': false});
  final routeur = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, _) => const MatchDetailPage(matchId: 'm')),
    GoRoute(path: '/equipes/:id', builder: (_, s) => Scaffold(
      body: Text('fiche équipe ${s.pathParameters['id']} ${(s.extra as dynamic)?.nom}'))),
  ]);
  await t.pumpWidget(ProviderScope(overrides: [...donneesCommunes(),
    matchDetailProvider('m').overrideWith((ref) async => match),
    matchStatsProvider('m').overrideWith((ref) async => null),
    lineupsProvider('m').overrideWith((ref) async => const LineupsData(available: false)),
    injuriesProvider('m').overrideWith((ref) async => []),
    h2hProvider('m').overrideWith((ref) async => throw Exception('none')),
    playerRatingsProvider('m').overrideWith((ref) async => []),
    standingsProvider('m').overrideWith((ref) async => [
      _ligne(1, 'Leader', 50), _ligne(2, 'Home', 42), _ligne(3, 'Sans identifiant', null)]),
    cotesMarchesProvider('m').overrideWith((ref) async => const []),
    formeRecenteProvider('m').overrideWith((ref) async => FormeRecente([
      MatchRecent(adversaire: 'Brighton', adversaireLogo: 'https://media.api-sports.io/football/teams/51.png',
        domicile: false, butsPour: 0, butsContre: 3, issue: IssueMatch.defaite),
    ], const [])),
  ], child: MaterialApp.router(theme: AppTheme.light, routerConfig: routeur)));
  for (var i = 0; i < 10; i++) { await t.pump(const Duration(milliseconds: 100)); }
}

void main() {
  setUpAll(preparerBanc);

  testWidgets('classement : la ligne d\'une équipe ouvre sa fiche', (t) async {
    await _monter(t);
    await t.tap(find.text('Classements'));
    for (var i = 0; i < 10; i++) { await t.pump(const Duration(milliseconds: 100)); }
    await t.tap(find.text('Leader'));
    for (var i = 0; i < 10; i++) { await t.pump(const Duration(milliseconds: 100)); }
    expect(find.text('fiche équipe 50 Leader'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('classement : sans identifiant, la ligne ne mène nulle part', (t) async {
    await _monter(t);
    await t.tap(find.text('Classements'));
    for (var i = 0; i < 10; i++) { await t.pump(const Duration(milliseconds: 100)); }
    await t.tap(find.text('Sans identifiant'));
    for (var i = 0; i < 10; i++) { await t.pump(const Duration(milliseconds: 100)); }
    expect(find.textContaining('fiche équipe'), findsNothing);
  });

  testWidgets('forme récente : l\'adversaire ouvre sa fiche', (t) async {
    await _monter(t);
    await t.ensureVisible(find.text('Brighton'));
    await t.tap(find.text('Brighton'));
    for (var i = 0; i < 10; i++) { await t.pump(const Duration(milliseconds: 100)); }
    expect(find.text('fiche équipe 51 Brighton'), findsOneWidget);
  });
}

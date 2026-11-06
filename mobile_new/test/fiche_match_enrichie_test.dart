// Fiche de match enrichie (8 octobre 2026) : tous les marchés cotés, la forme
// récente des deux équipes, le classement à domicile, à l'extérieur et en
// forme — ce que montrent Sofascore et 1xBet.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pronowin/core/theme/app_theme.dart';
import 'package:pronowin/features/pronostics/data/models/match_model.dart';
import 'package:pronowin/features/pronostics/presentation/providers/pronostics_provider.dart';
import 'package:pronowin/features/pronostics/presentation/providers/fiche_match_provider.dart';
import 'package:pronowin/features/pronostics/presentation/pages/match_detail_page.dart';
import 'aides/banc_ecran.dart';

const _marches = [
  MarcheCote('Match Winner', [CoteMarche('Home', 1.85), CoteMarche('Draw', 3.6), CoteMarche('Away', 4.2)]),
  MarcheCote('Goals Over/Under', [CoteMarche('Over 2.5', 1.9), CoteMarche('Under 2.5', 1.95)]),
  MarcheCote('Both Teams Score', [CoteMarche('Yes', 1.7), CoteMarche('No', 2.1)]),
  MarcheCote('Corners 1x2 (1st Half)', [CoteMarche('Home', 1.6), CoteMarche('Draw', 4.5), CoteMarche('Away', 3.1)]),
  MarcheCote('Yellow Over/Under', [CoteMarche('Over 3.5', 1.75), CoteMarche('Under 3.5', 2.0)]),
  // Nom inconnu du catalogue, puis valeur inconnue : écartés en entier.
  MarcheCote('Corners Race To', [CoteMarche('Home 3', 1.5), CoteMarche('Draw 3', 9.0)]),
  MarcheCote('Total Shots', [CoteMarche('Over 25.5', 1.8), CoteMarche('Draw 3', 2.0)]),
];

MatchRecent _recent(String adv, int pour, int contre, IssueMatch issue, {bool dom = true}) => MatchRecent(
  date: DateTime(2026, 9, 20), competition: 'Premier League', adversaire: adv,
  domicile: dom, butsPour: pour, butsContre: contre, issue: issue);

final _forme = FormeRecente([
  _recent('Brighton', 0, 3, IssueMatch.defaite, dom: false),
  _recent('Sunderland', 2, 0, IssueMatch.victoire),
  _recent('Chelsea', 1, 1, IssueMatch.nul),
], [
  _recent('Coventry', 3, 0, IssueMatch.victoire),
]);

StandingRow _ligne(int rang, String nom, int pts, Bilan dom, Bilan ext, String form) => StandingRow(
  rank: rang, teamName: nom, played: dom.played + ext.played, win: dom.win + ext.win,
  draw: dom.draw + ext.draw, lose: dom.lose + ext.lose, goalsDiff: 0, points: pts,
  form: form, home: dom, away: ext, zone: rang == 1 ? 'Ligue des champions' : null, zoneNature: rang == 1 ? 'c1' : null);

Bilan _b(int w, int d, int l, int gf, int ga) => Bilan(played: w + d + l, win: w, draw: d, lose: l,
  goalsFor: gf, goalsAgainst: ga, points: w * 3 + d);

final _classement = [
  _ligne(1, 'Leader', 13, _b(1, 0, 1, 3, 3), _b(3, 1, 0, 7, 2), 'WWWDL'),
  _ligne(2, 'Home', 12, _b(4, 0, 0, 9, 1), _b(0, 0, 2, 1, 4), 'LWWWW'),
  _ligne(3, 'Away', 4, _b(1, 1, 1, 4, 4), _b(0, 0, 2, 0, 3), 'DLWLL'),
];

void main() {
  setUpAll(preparerBanc);

  test('la forme du fournisseur se lit du plus récent au plus ancien', () {
    // « LWWWW » : Arsenal battu à Brighton au dernier match (relevé du 8 octobre).
    expect(formeChronologique('LWWWW'), [IssueMatch.victoire, IssueMatch.victoire,
      IssueMatch.victoire, IssueMatch.victoire, IssueMatch.defaite]);
    expect(formeChronologique(null), isEmpty);
    expect(formeChronologique('w?d'), [IssueMatch.nul, IssueMatch.victoire]);
  });

  test('classement à domicile : points, puis différence de buts, sans zone', () {
    final dom = classementSurTerrain(_classement, domicile: true)!;
    expect(dom.map((r) => r.teamName), ['Home', 'Away', 'Leader']);
    expect(dom.map((r) => r.rank), [1, 2, 3]);
    expect(dom.first.points, 12);
    expect(dom.first.goalsDiff, 8);
    expect(dom.every((r) => r.zone == null), isTrue);
    final ext = classementSurTerrain(_classement, domicile: false)!;
    expect(ext.first.teamName, 'Leader');
    // Différence de buts départage les deux à zéro point.
    expect(ext.map((r) => r.teamName).skip(1), ['Home', 'Away']);
    // Un serveur sans bilans : pas de classement inventé.
    expect(classementSurTerrain([StandingRow.fromJson({'rank': 1})], domicile: true), isNull);
  });

  test('cotes : une cote absente ou inférieure à 1 n’est pas une cote', () {
    final m = MarcheCote.fromJson({'name': 'Both Teams Score', 'values': [
      {'value': 'Yes', 'odd': 1.7}, {'value': 'No', 'odd': 0}, {'value': 'X', 'odd': 'n/a'}]});
    expect(m.cotes.map((c) => c.valeur), ['Yes']);
  });

  testWidgets('un match sans pronostic a son onglet Cotes, tous marchés traduits', (t) async {
    await _monter(t, AppTheme.light);
    await _ouvrir(t, 'Cotes');
    expect(find.text('Tous les marchés'), findsOneWidget);
    // Sans bandeau 1X2 au-dessus, le vainqueur du match ouvre la liste.
    expect(find.text('Vainqueur du match'), findsOneWidget);
    expect(find.text('Plus de 2,5'), findsOneWidget);
    expect(find.text('Home'), findsWidgets);
    // Les marchés que le catalogue ne sait pas nommer entièrement : absents.
    expect(find.textContaining('Race'), findsNothing);
    expect(find.text('Total de tirs du match'), findsNothing);
    expect(find.text('5'), findsOneWidget);

    // Filtre « Corners » : le seul marché de corners reste, replié.
    await t.tap(find.byKey(const Key('cotes-famille-corners')));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('Équipe avec le plus de corners — 1ère MT'), findsOneWidget);
    expect(find.text('Plus de 2,5'), findsNothing);
    expect(find.text('1.60'), findsNothing);
    await t.tap(find.byKey(const Key('marche-Corners 1x2 (1st Half)')));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('1.60'), findsOneWidget);

    // Les cartons ont leur famille, pas celle des buts.
    await t.tap(find.byKey(const Key('cotes-famille-cartons')));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('Plus / Moins de cartons jaunes'), findsOneWidget);
    expect(find.text('Équipe avec le plus de corners — 1ère MT'), findsNothing);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox()); await t.pump();
  });

  testWidgets('forme récente : les deux équipes sont visibles, les détails restent accessibles', (t) async {
    await _monter(t, AppTheme.dark);
    expect(find.text('Forme récente'), findsOneWidget);
    // Défaite à l'extérieur : Brighton 3-0 Home, et non Home 0-3.
    expect(find.text('3 - 0'), findsNWidgets(2));
    expect(find.byKey(const Key('forme-domicile-score-0')), findsOneWidget);
    expect(find.byKey(const Key('forme-exterieur-score-0')), findsOneWidget);
    expect(find.text('Coventry'), findsNothing);
    await t.ensureVisible(find.byKey(const Key('forme-exterieur')));
    await t.tap(find.byKey(const Key('forme-exterieur')));
    await t.pumpAndSettle();
    expect(find.text('Coventry'), findsOneWidget);
    expect(find.text('Brighton'), findsNothing);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox()); await t.pump();
  });

  for (final theme in [AppTheme.light, AppTheme.dark]) {
    testWidgets('classement : domicile, extérieur et forme, texte 180 %, ${theme.brightness}', (t) async {
      await _monter(t, theme);
      await _ouvrir(t, 'Classements');
      for (final v in ['general', 'domicile', 'exterieur', 'forme']) {
        expect(find.byKey(Key('classement-$v')), findsOneWidget);
      }
      await t.tap(find.byKey(const Key('classement-domicile')));
      await t.pump(const Duration(milliseconds: 300));
      final noms = t.widgetList<Text>(find.descendant(
        of: find.byType(SingleChildScrollView).last, matching: find.byType(Text)))
        .map((w) => w.data).where((d) => ['Leader', 'Home', 'Away'].contains(d)).toList();
      expect(noms, ['Home', 'Away', 'Leader']);
      expect(find.text('Ligue des champions'), findsNothing);

      await t.tap(find.byKey(const Key('classement-forme')));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Forme'), findsWidgets);
      expect(find.bySemanticsLabel('Victoire'), findsWidgets);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox()); await t.pump();
    });
  }
}

Future<void> _ouvrir(WidgetTester t, String onglet) async {
  await t.ensureVisible(find.text(onglet));
  await t.tap(find.text(onglet));
  for (var i = 0; i < 10; i++) { await t.pump(const Duration(milliseconds: 100)); }
}

/// Petit téléphone (320 px), texte à 180 % : là où une fiche déborde.
Future<void> _monter(WidgetTester t, ThemeData theme) async {
  SharedPreferences.setMockInitialValues({});
  t.view.physicalSize = const Size(640, 1600); t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  final match = MatchModel.fromJson({'id': 'm', 'league': 'Premier League', 'league_country': 'PL',
    'home_team': 'Home', 'away_team': 'Away', 'status': 'upcoming',
    'match_date': '2026-10-18T14:00:00Z', 'has_pronostic': false});
  await t.pumpWidget(ProviderScope(overrides: [...donneesCommunes(),
    matchDetailProvider('m').overrideWith((ref) async => match),
    matchStatsProvider('m').overrideWith((ref) async => null),
    lineupsProvider('m').overrideWith((ref) async => const LineupsData(available: false)),
    injuriesProvider('m').overrideWith((ref) async => []),
    h2hProvider('m').overrideWith((ref) async => throw Exception('none')),
    playerRatingsProvider('m').overrideWith((ref) async => []),
    standingsProvider('m').overrideWith((ref) async => _classement),
    cotesMarchesProvider('m').overrideWith((ref) async => _marches),
    formeRecenteProvider('m').overrideWith((ref) async => _forme),
  ], child: MaterialApp(theme: theme,
    builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(
      textScaler: const TextScaler.linear(1.8), disableAnimations: true), child: child!),
    home: const MatchDetailPage(matchId: 'm'))));
  for (var i = 0; i < 10; i++) { await t.pump(const Duration(milliseconds: 100)); }
}

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pronowin/core/theme/app_theme.dart';
import 'package:pronowin/features/auth/presentation/providers/auth_provider.dart';
import 'package:pronowin/features/pronostics/data/models/match_model.dart';
import 'package:pronowin/features/pronostics/presentation/pages/match_detail_page.dart';
import 'package:pronowin/features/pronostics/presentation/providers/fiche_match_provider.dart';
import 'package:pronowin/features/pronostics/presentation/providers/pronostics_provider.dart';
import 'aides/banc_ecran.dart';

/// « Qui va gagner ? » — le vote des fans avant le match (26 octobre 2026).
VotesMatch _votes({bool ouvert = true, int dom = 0, int nul = 0, int ext = 0, String? mien}) {
  final total = dom + nul + ext;
  int p(int n) => total == 0 ? 0 : (n / total * 100).round();
  return VotesMatch(ouvert: ouvert, total: total, dom: dom, nul: nul, ext: ext,
    pDom: p(dom), pNul: p(nul), pExt: p(ext), monVote: mien);
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR');
    await preparerBanc();
  });

  late List<String> votes;

  Future<void> ouvrir(WidgetTester t, {required VotesMatch? initial, String statut = 'upcoming',
      Future<VotesMatch> Function(String choix)? serveur, bool invite = false, List<int>? score}) async {
    SharedPreferences.setMockInitialValues({'astuce_suivre_match_vue': true});
    t.view.physicalSize = const Size(1170, 2532); t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    votes = [];
    final match = MatchModel.fromJson({'id': 'm', 'league': 'Premier League', 'league_country': 'GB',
      'home_team': 'Arsenal', 'away_team': 'Chelsea', 'status': statut,
      'match_date': DateTime.now().add(Duration(hours: statut == 'upcoming' ? 20 : -1)).toUtc().toIso8601String(),
      if (score != null) ...{'home_score': score[0], 'away_score': score[1]},
      'has_pronostic': true, 'prediction_type': 'HOME_WIN', 'prediction_label': 'Victoire Arsenal',
      'odds_recommended': 1.8, 'confidence_score': 4, 'is_premium': false});
    final routeur = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, _) => const MatchDetailPage(matchId: 'm')),
      GoRoute(path: '/auth/email', builder: (_, _) => const Scaffold(body: Text('INSCRIPTION'))),
    ]);
    await t.pumpWidget(ProviderScope(overrides: [...donneesCommunes(),
      if (invite) effectiveLoggedInProvider.overrideWithValue(false),
      matchDetailProvider('m').overrideWith((ref) async => match),
      matchStatsProvider('m').overrideWith((ref) async => null),
      lineupsProvider('m').overrideWith((ref) async => const LineupsData(available: false)),
      injuriesProvider('m').overrideWith((ref) async => []),
      h2hProvider('m').overrideWith((ref) async => throw Exception('none')),
      playerRatingsProvider('m').overrideWith((ref) async => []),
      articlesDuMatchProvider('m').overrideWith((ref) async => null),
      votesMatchProvider('m').overrideWith((ref) async => initial),
      voterMatchProvider.overrideWithValue((id, choix) async {
        votes.add('$id:$choix');
        return (serveur ?? (c) async => _votes(dom: 2, nul: 0, ext: 1, mien: c))(choix);
      }),
    ], child: MaterialApp.router(theme: AppTheme.dark, routerConfig: routeur)));
    for (var i = 0; i < 20; i++) { await t.pump(const Duration(milliseconds: 100)); }
  }

  Future<void> toucher(WidgetTester t, String cle) async {
    await t.ensureVisible(find.byKey(Key(cle)));
    await t.pump();
    await t.tap(find.byKey(Key(cle)));
    for (var i = 0; i < 5; i++) { await t.pump(const Duration(milliseconds: 100)); }
  }

  testWidgets('avant de voter : trois choix, sans la répartition ; voter la montre, son vote en évidence', (t) async {
    await ouvrir(t, initial: _votes(dom: 1, nul: 0, ext: 1));
    expect(find.text('Qui va gagner ?'), findsOneWidget);
    for (final c in ['1', 'N', '2']) {
      expect(find.byKey(Key('vote-$c')), findsOneWidget);
    }
    expect(find.descendant(of: find.byKey(const Key('vote-fans')), matching: find.textContaining('%')), findsNothing, reason: 'la répartition ne se voit qu\'après avoir voté');

    await toucher(t, 'vote-1');
    expect(votes, ['m:1']);
    expect(find.byKey(const Key('vote-part-1')), findsOneWidget);
    expect(find.text('67 %'), findsOneWidget);
    expect(find.text('33 %'), findsOneWidget);
    expect(find.text('3 votes'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('vote-part-1')), matching: find.byIcon(Icons.check_circle_rounded)),
      findsOneWidget);
    expect(find.text("Tu peux changer d'avis jusqu'au coup d'envoi."), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('changer d\'avis avant le coup d\'envoi', (t) async {
    await ouvrir(t, initial: _votes(dom: 2, nul: 0, ext: 1, mien: '1'));
    await toucher(t, 'vote-part-2');
    expect(votes, ['m:2']);
    expect(find.descendant(of: find.byKey(const Key('vote-part-2')), matching: find.byIcon(Icons.check_circle_rounded)),
      findsOneWidget);
  });

  testWidgets('le match a commencé : votes clos, la répartition visible, plus de vote possible', (t) async {
    await ouvrir(t, statut: 'live', initial: _votes(ouvert: false, dom: 3, nul: 1, ext: 0));
    expect(find.text('Votes clos.'), findsOneWidget);
    expect(find.text('75 %'), findsOneWidget);
    await toucher(t, 'vote-part-2');
    expect(votes, isEmpty);
  });

  testWidgets('clos sans un seul vote, ou serveur muet : pas de carte', (t) async {
    await ouvrir(t, statut: 'live', initial: _votes(ouvert: false));
    expect(find.byKey(const Key('vote-fans')), findsNothing);
    await t.pumpWidget(const SizedBox());
    await ouvrir(t, initial: null);
    expect(find.byKey(const Key('vote-fans')), findsNothing);
  });

  testWidgets('un invité est emmené s\'inscrire au moment du vote', (t) async {
    await ouvrir(t, initial: _votes(), invite: true);
    await toucher(t, 'vote-N');
    await t.pumpAndSettle();
    expect(votes, isEmpty);
    expect(find.text('INSCRIPTION'), findsOneWidget);
  });

  testWidgets('le coup d\'envoi est passé entre-temps : le message du serveur', (t) async {
    await ouvrir(t, initial: _votes(), serveur: (c) async => throw DioException(
      requestOptions: RequestOptions(path: '/pronostics/m/vote'),
      response: Response(requestOptions: RequestOptions(path: '/pronostics/m/vote'), statusCode: 409)));
    await toucher(t, 'vote-2');
    expect(find.text('Les votes sont clos : le match a commencé.'), findsOneWidget);
  });

  // « Les fans avaient-ils raison ? » (26 octobre 2026) : le match terminé, la
  // carte dit qui avait vu juste.
  testWidgets('après le match : l\'issue marquée, les fans avaient vu juste, ton vote aussi', (t) async {
    await ouvrir(t, statut: 'finished', score: [2, 0],
      initial: _votes(ouvert: false, dom: 61, nul: 18, ext: 21, mien: '1'));
    expect(find.descendant(of: find.byKey(const Key('vote-part-1')), matching: find.byKey(const Key('vote-issue'))),
      findsOneWidget);
    expect(find.byKey(const Key('vote-issue')), findsOneWidget);
    expect(find.text("61 % des fans l'avaient vu venir."), findsOneWidget);
    expect(find.text('Ton vote : bien vu !'), findsOneWidget);
    expect(find.text('Votes clos.'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('un nul que peu de fans voyaient venir ; ton vote raté', (t) async {
    await ouvrir(t, statut: 'finished', score: [1, 1],
      initial: _votes(ouvert: false, dom: 61, nul: 18, ext: 21, mien: '2'));
    expect(find.descendant(of: find.byKey(const Key('vote-part-N')), matching: find.byKey(const Key('vote-issue'))),
      findsOneWidget);
    expect(find.text("Seuls 18 % des fans l'avaient vu venir."), findsOneWidget);
    expect(find.text('Ton vote : raté.'), findsOneWidget);
  });

  testWidgets('sans vote à soi : le verdict des fans seulement ; en direct, pas encore de verdict', (t) async {
    await ouvrir(t, statut: 'finished', score: [0, 3], initial: _votes(ouvert: false, dom: 5, nul: 2, ext: 3));
    expect(find.text("Seuls 30 % des fans l'avaient vu venir."), findsOneWidget);
    expect(find.textContaining('Ton vote'), findsNothing);
    await t.pumpWidget(const SizedBox());
    await ouvrir(t, statut: 'live', score: [1, 0], initial: _votes(ouvert: false, dom: 5, nul: 2, ext: 3, mien: '1'));
    expect(find.byKey(const Key('vote-verdict')), findsNothing);
    expect(find.byKey(const Key('vote-issue')), findsNothing);
    expect(find.text('Votes clos.'), findsOneWidget);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pronowin/core/theme/app_theme.dart';
import 'package:pronowin/features/actualites/page_article.dart';
import 'package:pronowin/features/pronostics/data/models/match_model.dart';
import 'package:pronowin/features/pronostics/presentation/pages/match_detail_page.dart';
import 'package:pronowin/features/pronostics/presentation/providers/fiche_match_provider.dart';
import 'package:pronowin/features/pronostics/presentation/providers/pronostics_provider.dart';
import 'aides/banc_ecran.dart';

/// L'avant-match et le résumé dans la fiche du match (26 octobre 2026) : plus
/// de cent articles par semaine, qu'on ne trouvait que dans la page Actus.
Map<String, dynamic> _article(String genre, String titre, String texte) => {
  'id': '${genre}_a1', 'titre': titre, 'resume': texte, 'categorie': 'Premier League',
  'created_at': DateTime.now().subtract(const Duration(hours: 2)).toUtc().toIso8601String(),
  'from_rss': false, 'type': 'resume_match', 'genre': genre, 'match_id': 'm',
  'image_url': null, 'source_url': null, 'score': genre == 'resume' ? '2-0' : null,
};

final _avant = _article('avant_match', 'Avant-match : Arsenal (2e) reçoit Chelsea (5e)',
  'Premier League. Arsenal, 2e avec 17 points, reçoit Chelsea, 5e avec 14 points.\n\nArsenal : 4 victoires et 1 nul.');
final _resume = _article('resume', 'Arsenal s\'impose face à Chelsea (2-0)',
  'Score à la mi-temps : 1-0.\n\nButs — Arsenal : Saka (12\'), Havertz (70\').');

void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR');
    await initializeDateFormatting('fr');
    await preparerBanc();
  });

  Future<void> ouvrir(WidgetTester t, {required String statut, Map<String, dynamic>? articles}) async {
    // La bulle de la cloche, déjà vue : elle n'est pas le sujet.
    SharedPreferences.setMockInitialValues({'astuce_suivre_match_vue': true});
    t.view.physicalSize = const Size(1170, 2532); t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final match = MatchModel.fromJson({'id': 'm', 'league': 'Premier League', 'league_country': 'GB',
      'home_team': 'Arsenal', 'away_team': 'Chelsea', 'status': statut,
      'match_date': DateTime.now().add(Duration(hours: statut == 'upcoming' ? 20 : -3)).toUtc().toIso8601String(),
      if (statut == 'finished') ...{'home_score': 2, 'away_score': 0},
      'has_pronostic': true, 'prediction_type': 'HOME_WIN', 'prediction_label': 'Victoire Arsenal',
      'odds_recommended': 1.8, 'confidence_score': 4, 'is_premium': false});
    final routeur = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, _) => const MatchDetailPage(matchId: 'm')),
      GoRoute(path: '/actualites/article', builder: (_, s) => pageDeLArticle(s.extra, s.uri.queryParameters)),
      GoRoute(path: '/pronostics/:id', builder: (_, s) => Text('fiche ${s.pathParameters['id']}')),
    ]);
    await t.pumpWidget(ProviderScope(overrides: [...donneesCommunes(),
      matchDetailProvider('m').overrideWith((ref) async => match),
      matchStatsProvider('m').overrideWith((ref) async => null),
      lineupsProvider('m').overrideWith((ref) async => const LineupsData(available: false)),
      injuriesProvider('m').overrideWith((ref) async => []),
      h2hProvider('m').overrideWith((ref) async => throw Exception('none')),
      playerRatingsProvider('m').overrideWith((ref) async => []),
      articlesDuMatchProvider('m').overrideWith((ref) async => articles),
    ], child: MaterialApp.router(theme: AppTheme.dark, routerConfig: routeur)));
    for (var i = 0; i < 20; i++) { await t.pump(const Duration(milliseconds: 100)); }
  }

  testWidgets('avant le match : l\'avant-match, son titre sans préfixe et deux lignes', (t) async {
    await ouvrir(t, statut: 'upcoming', articles: {'avant_match': _avant, 'resume': null});
    expect(find.byKey(const Key('fiche-article-match')), findsOneWidget);
    expect(find.text('Avant-match'), findsOneWidget);
    expect(find.text('Arsenal (2e) reçoit Chelsea (5e)'), findsOneWidget);
    expect(find.textContaining('Premier League. Arsenal, 2e avec 17 points'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('après le match : le résumé l\'emporte ; il s\'ouvre, sans renvoyer à la fiche', (t) async {
    await ouvrir(t, statut: 'finished', articles: {'avant_match': _avant, 'resume': _resume});
    expect(find.text('Résumé'), findsOneWidget);
    expect(find.text('Arsenal s\'impose face à Chelsea (2-0)'), findsOneWidget);
    expect(find.text('Avant-match'), findsNothing);
    await t.tap(find.byKey(const Key('fiche-article-match')));
    await t.pumpAndSettle();
    expect(find.byType(PageArticle), findsOneWidget);
    expect(find.text('Buts — Arsenal : Saka (12\'), Havertz (70\').'), findsOneWidget);
    expect(find.byKey(const Key('actu-voir-match')), findsNothing);
  });

  testWidgets('sans article, ou serveur muet : pas de carte', (t) async {
    await ouvrir(t, statut: 'upcoming', articles: {'avant_match': null, 'resume': null});
    expect(find.byKey(const Key('fiche-article-match')), findsNothing);
    await t.pumpWidget(const SizedBox());
    await ouvrir(t, statut: 'upcoming', articles: null);
    expect(find.byKey(const Key('fiche-article-match')), findsNothing);
  });
}

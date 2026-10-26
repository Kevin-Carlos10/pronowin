import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pronowin/core/theme/app_theme.dart';
import 'package:pronowin/features/pronostics/data/models/match_model.dart';
import 'package:pronowin/features/pronostics/presentation/providers/pronostics_provider.dart';
import 'package:pronowin/features/pronostics/presentation/pages/match_detail_page.dart';
import 'package:pronowin/shared/providers/favoris_provider.dart';
import 'aides/banc_ecran.dart';

/// La bulle de la cloche « Suivre ce match » (22 octobre 2026) : les alertes
/// des matchs suivis — buts, mi-temps, cartons rouges, compositions, résumé —
/// ne touchaient que quatre personnes. La première fiche ouverte présente la
/// cloche, une seule fois.
class _Carnet extends FavorisNotifier {
  @override
  Future<EtatFavoris> build() async => const EtatFavoris();
  @override
  Future<void> basculerMatch(String matchId) async {
    final ids = {...state.value!.matchIds};
    ids.contains(matchId) ? ids.remove(matchId) : ids.add(matchId);
    state = AsyncData(EtatFavoris(matchIds: ids));
  }
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR');
    await preparerBanc();
  });

  Future<void> ouvrirLaFiche(WidgetTester t, {String statut = 'upcoming', double texte = 1}) async {
    // iPhone 12-15 : 390 × 844 points.
    t.view.physicalSize = const Size(1170, 2532); t.view.devicePixelRatio = 3;
    t.platformDispatcher.textScaleFactorTestValue = texte;
    addTearDown(t.view.reset);
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    final match = MatchModel.fromJson({'id': 'm', 'league': 'Premier League', 'league_country': 'GB',
      'home_team': 'Arsenal', 'away_team': 'Chelsea', 'status': statut,
      'match_date': DateTime.now().add(const Duration(hours: 5)).toUtc().toIso8601String(),
      'has_pronostic': true, 'prediction_type': 'HOME_WIN', 'prediction_label': 'Victoire Arsenal',
      'odds_recommended': 1.8, 'confidence_score': 4, 'is_premium': false,
      if (statut == 'finished') ...{'home_score': 2, 'away_score': 1}});
    await t.pumpWidget(ProviderScope(overrides: [...donneesCommunes(favoris: _Carnet.new),
      matchDetailProvider('m').overrideWith((ref) async => match),
      matchStatsProvider('m').overrideWith((ref) async => null),
      lineupsProvider('m').overrideWith((ref) async => const LineupsData(available: false)),
      injuriesProvider('m').overrideWith((ref) async => []),
      h2hProvider('m').overrideWith((ref) async => throw Exception('none')),
      playerRatingsProvider('m').overrideWith((ref) async => []),
    ], child: MaterialApp(theme: AppTheme.dark, home: const MatchDetailPage(matchId: 'm'))));
    for (var i = 0; i < 20; i++) { await t.pump(const Duration(milliseconds: 100)); }
  }

  Finder bulle() => find.byKey(const Key('bulle-suivi'));

  testWidgets('première fiche : la bulle sous la cloche, au-dessus des onglets — notée vue', (t) async {
    SharedPreferences.setMockInitialValues({});
    await ouvrirLaFiche(t);
    expect(bulle(), findsOneWidget);
    expect(find.text('Sois alerté des buts, de la mi-temps et du résumé.'), findsOneWidget);
    // Sous la cloche, et sans rien cacher de la barre d'onglets.
    final cloche = t.getRect(find.byKey(const Key('suivre-match')));
    final rect = t.getRect(bulle());
    expect(rect.top, greaterThanOrEqualTo(cloche.bottom - 8));
    expect(rect.left, lessThan(cloche.center.dx));
    expect(rect.right, greaterThan(cloche.center.dx));
    expect(rect.bottom, lessThanOrEqualTo(t.getRect(find.byType(TabBar)).top));
    expect((await SharedPreferences.getInstance()).getBool('astuce_suivre_match_vue'), isTrue);
    expect(t.takeException(), isNull);
  });

  testWidgets('texte agrandi (200 %) : la bulle tient toujours au-dessus des onglets', (t) async {
    SharedPreferences.setMockInitialValues({});
    await ouvrirLaFiche(t, texte: 2);
    expect(t.getRect(bulle()).bottom, lessThanOrEqualTo(t.getRect(find.byType(TabBar)).top));
    expect(t.takeException(), isNull);
  });

  testWidgets('le premier toucher ailleurs la ferme ; les fiches suivantes ne la montrent plus', (t) async {
    SharedPreferences.setMockInitialValues({});
    await ouvrirLaFiche(t);
    await t.tapAt(const Offset(60, 500));
    await t.pump();
    expect(bulle(), findsNothing);
    // Une autre fiche, plus tard : déjà vue.
    await t.pumpWidget(const SizedBox());
    await ouvrirLaFiche(t);
    expect(bulle(), findsNothing);
  });

  testWidgets('« Suivre » suit le match et ferme la bulle', (t) async {
    SharedPreferences.setMockInitialValues({});
    await ouvrirLaFiche(t);
    await t.tap(find.byKey(const Key('bulle-suivi-suivre')));
    for (var i = 0; i < 5; i++) { await t.pump(const Duration(milliseconds: 100)); }
    expect(bulle(), findsNothing);
    final conteneur = ProviderScope.containerOf(t.element(find.byType(MatchDetailPage)));
    expect(conteneur.read(favorisProvider).value!.matchIds, contains('m'));
  });

  testWidgets('match terminé : pas de bulle, et rien de noté', (t) async {
    SharedPreferences.setMockInitialValues({});
    await ouvrirLaFiche(t, statut: 'finished');
    expect(bulle(), findsNothing);
    expect((await SharedPreferences.getInstance()).getBool('astuce_suivre_match_vue'), isNull);
  });
}

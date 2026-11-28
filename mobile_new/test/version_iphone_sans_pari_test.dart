// Version iPhone sans pari (12 octobre 2026).
//
// Apple a refusé la 1.0.16 : un compte individuel ne peut plus distribuer
// d'application de jeu d'argent, même simulé. Sur iPhone, PronoWin n'affiche
// donc ni bankroll, ni bouton de sélection, ni cote, ni tutoriel de stratégie
// de pari. Ces bancs forcent l'interrupteur pour vérifier, sur Windows, ce que
// verra un iPhone — et vérifient qu'Android, lui, ne change pas.
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show SemanticsFlag;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pronowin/core/config/sans_pari.dart';
import 'package:pronowin/core/network/dio_client.dart';
import 'package:pronowin/core/theme/app_theme.dart';
import 'package:pronowin/features/pronostics/data/models/match_model.dart';
import 'package:pronowin/features/pronostics/domain/entities/avis_compares.dart';
import 'package:pronowin/features/pronostics/presentation/pages/match_detail_page.dart';
import 'package:pronowin/features/pronostics/presentation/providers/fiche_match_provider.dart';
import 'package:pronowin/features/pronostics/presentation/providers/pronostics_provider.dart';
import 'package:pronowin/features/pronostics/presentation/widgets/match_card_widget.dart';
import 'package:pronowin/features/tutoriels/presentation/providers/tutoriels_provider.dart';
import 'package:pronowin/shared/widgets/main_scaffold.dart';
import 'aides/banc_ecran.dart';

final _match = MatchModel.fromJson({
  'id': 'm', 'league': 'Bundesliga', 'league_country': 'DE',
  'home_team': 'Borussia Dortmund', 'away_team': 'Werder Bremen', 'status': 'upcoming',
  'match_date': DateTime.now().add(const Duration(days: 2)).toIso8601String(),
  'has_pronostic': true, 'prediction_type': 'win1', 'prediction_label': 'Borussia Dortmund gagne',
  'odds_recommended': 1.41, 'odds_home': 1.41, 'odds_draw': 5.7, 'odds_away': 7.7,
  'confidence_score': 4, 'confidence_pct': 79, 'is_premium': false,
});

Widget _app(Widget enfant, {required bool iphone, List<Override> surcharges = const []}) => ProviderScope(
  overrides: [...donneesCommunes(), sansPariProvider.overrideWithValue(iphone), ...surcharges],
  child: MaterialApp(theme: AppTheme.light, home: enfant),
);

Future<void> _attendre(WidgetTester t) async {
  for (var i = 0; i < 10; i++) { await t.pump(const Duration(milliseconds: 100)); }
}

/// Le serveur des tutoriels : un de chaque catégorie.
class _ServeurTutoriels implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? a) async =>
      ResponseBody.fromString(jsonEncode([
        for (final c in ['valuebet', 'bankroll', 'martingale', 'trading', 'statistics', 'analyse'])
          {'id': c, 'title': 'Tuto $c', 'description': '', 'category': c, 'level': 'beginner'},
      ]), 200, headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
  @override
  void close({bool force = false}) {}
}

/// Le serveur de l'analyse : note les requêtes reçues.
class _ServeurAnalyse implements HttpClientAdapter {
  _ServeurAnalyse(this.requetes);
  final List<RequestOptions> requetes;
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? a) async {
    requetes.add(o);
    return ResponseBody.fromString(jsonEncode({'probability': 71, 'explanation': 'Texte.'}), 200,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
  }
  @override
  void close({bool force = false}) {}
}

void main() {
  setUpAll(preparerBanc);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('barre : pas d\'onglet Bankroll sur iPhone, et un lien Bankroll ouvre l\'accueil', (t) async {
    t.view.physicalSize = const Size(780, 1600); t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    final semantique = t.ensureSemantics();
    await t.pumpWidget(ProviderScope(
      overrides: [...donneesCommunes(), sansPariProvider.overrideWithValue(true)],
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: GoRouter(routes: [
        GoRoute(path: '/', builder: (_, _) => const MainScaffold(initialIndex: 2)),
      ])),
    ));
    await _attendre(t);
    expect(find.bySemanticsLabel('Bankroll'), findsNothing);
    for (final onglet in ['Accueil', 'Pronos', 'Tutoriels', 'Compte']) {
      expect(find.bySemanticsLabel(onglet), findsOneWidget, reason: onglet);
    }
    // Ouvert sur l'onglet 2 (Bankroll) : c'est l'accueil qui s'affiche,
    // sélectionné dans la barre.
    final accueil = t.getSemantics(find.bySemanticsLabel('Accueil'));
    expect(accueil.hasFlag(SemanticsFlag.isSelected), isTrue);
    semantique.dispose();
    await t.pumpWidget(const SizedBox()); await t.pump(const Duration(minutes: 1));
  });

  for (final iphone in [true, false]) {
    final nom = iphone ? 'iPhone' : 'Android';
    testWidgets('fiche de match ($nom) : onglet Cotes, bouton de sélection, cote du pronostic', (t) async {
      t.view.physicalSize = const Size(780, 1800); t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      await t.pumpWidget(_app(const MatchDetailPage(matchId: 'm'), iphone: iphone, surcharges: [
        matchDetailProvider('m').overrideWith((ref) async => _match),
        matchStatsProvider('m').overrideWith((ref) async => null),
        lineupsProvider('m').overrideWith((ref) async => const LineupsData(available: false)),
        injuriesProvider('m').overrideWith((ref) async => []),
        h2hProvider('m').overrideWith((ref) async => throw Exception('none')),
        playerRatingsProvider('m').overrideWith((ref) async => []),
        standingsProvider('m').overrideWith((ref) async => []),
        cotesMarchesProvider('m').overrideWith((ref) async => const []),
        formeRecenteProvider('m').overrideWith((ref) async => null),
      ]));
      await _attendre(t);
      expect(find.text('Cotes'), iphone ? findsNothing : findsOneWidget);
      expect(find.text('Valider ma sélection'), iphone ? findsNothing : findsOneWidget);
      expect(find.text('1.41'), iphone ? findsNothing : findsWidgets);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox()); await t.pump(const Duration(minutes: 1));
    });

    testWidgets('carte de match ($nom) : ni cote ni 1/N/2 sur iPhone', (t) async {
      await t.pumpWidget(_app(Scaffold(body: SingleChildScrollView(
        child: MatchCardWidget(match: _match, isPremiumUser: true))), iphone: iphone));
      await _attendre(t);
      expect(find.text('1.41'), iphone ? findsNothing : findsWidgets);
      expect(find.text('7.70'), iphone ? findsNothing : findsWidgets);
      expect(t.takeException(), isNull);
    });

    test('tutoriels ($nom) : la stratégie de pari est écartée sur iPhone', () async {
      final c = ProviderContainer(overrides: [
        sansPariProvider.overrideWithValue(iphone),
        dioProvider.overrideWithValue(Dio()..httpClientAdapter = _ServeurTutoriels()),
      ]);
      addTearDown(c.dispose);
      final abonnement = c.listen(tutorielsProvider, (_, _) {});
      addTearDown(abonnement.close);
      final categories = (await c.read(tutorielsProvider.future)).map((t) => t.category).toSet();
      expect(categories, iphone
          ? {'statistics', 'analyse'}
          : {'valuebet', 'bankroll', 'martingale', 'trading', 'statistics', 'analyse'});
    });
  }

  // Captures de la 1.0.23 (13 octobre 2026) : l'analyse statistique disait
  // encore « fondé sur les cotes » et « La cote de 1.34… (marge du bookmaker
  // incluse) » sur iPhone.
  test('analyse statistique : la phrase de comparaison ne nomme pas les cotes sur iPhone', () {
    for (final (calcul, analyste) in [(71, 95), (95, 60), (70, 72)]) {
      final ios = AvisCompares(calcul: calcul, analyste: analyste, sansCotes: true).phrase;
      expect(ios.toLowerCase().contains('cote'), isFalse, reason: ios);
    }
    expect(const AvisCompares(calcul: 71, analyste: 95).phrase.contains('cotes'), isTrue,
        reason: 'Android garde sa phrase');
  });

  for (final iphone in [true, false]) {
    test('analyse statistique (${iphone ? 'iPhone' : 'Android'}) : explication sans cotes demandée au serveur', () async {
      final requetes = <RequestOptions>[];
      final c = ProviderContainer(overrides: [
        sansPariProvider.overrideWithValue(iphone),
        dioProvider.overrideWithValue(Dio()..httpClientAdapter = _ServeurAnalyse(requetes)),
      ]);
      addTearDown(c.dispose);
      final abonnement = c.listen(aiAnalysisProvider('p1'), (_, _) {});
      addTearDown(abonnement.close);
      await c.read(aiAnalysisProvider('p1').future);
      expect(requetes.single.queryParameters['sans_cotes'], iphone ? '1' : isNull);
    });
  }

  test('une rencontre sans cotes garde tout le reste', () {
    final s = _match.sansCotes();
    expect([s.oddsRecommended, s.oddsHome, s.oddsDraw, s.oddsAway], [0, 0, 0, 0]);
    expect(s.homeTeam, _match.homeTeam);
    expect(s.displayPredictionLabel, _match.displayPredictionLabel);
    expect(s.pourcentageConfiance, _match.pourcentageConfiance);
    expect(s.hasPronostic, isTrue);
  });
}

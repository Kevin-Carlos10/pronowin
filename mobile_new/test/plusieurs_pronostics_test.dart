import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronowin/core/config/sans_pari.dart';
import 'package:pronowin/core/theme/app_theme.dart';
import 'package:pronowin/features/auth/domain/entities/user_entity.dart';
import 'package:pronowin/features/pronostics/data/models/match_model.dart';
import 'package:pronowin/features/pronostics/domain/entities/match_entity.dart';
import 'package:pronowin/features/pronostics/presentation/pages/match_detail_page.dart';
import 'package:pronowin/features/pronostics/presentation/providers/fiche_match_provider.dart';
import 'package:pronowin/features/pronostics/presentation/providers/pronostics_provider.dart';
import 'package:pronowin/features/pronostics/presentation/widgets/match_card_widget.dart';

import 'aides/banc_ecran.dart';

/// Plusieurs pronostics par match (23 novembre 2026) : la carte de la liste
/// montre le principal et annonce « +N prono » ; la fiche du match montre les
/// autres sous le principal, chacun avec son propre verrou VIP.
Map<String, dynamic> _fiche({bool vipOuvert = false, Object? autres}) => {
  'id': 'm', 'league': 'Premier League', 'league_country': 'GB',
  'home_team': 'Arsenal', 'away_team': 'Chelsea', 'status': 'upcoming',
  'match_date': DateTime.now().add(const Duration(hours: 20)).toUtc().toIso8601String(),
  'has_pronostic': true, 'prediction_type': 'win1', 'prediction_label': 'Victoire Arsenal',
  'odds_recommended': 1.8, 'confidence_score': 4, 'is_premium': false,
  'autres_pronostics': autres ?? [
    {'id': 'p2', 'is_premium': false, 'locked': false,
     'prediction_label': 'Total buts : Plus de 2.5', 'odds_recommended': 1.95,
     'confidence_score': 4, 'confidence_pct': 62, 'analyst_note': 'Deux attaques en forme.', 'result': null},
    vipOuvert
        ? {'id': 'p3', 'is_premium': true, 'locked': false,
           'prediction_label': 'Corners : Plus de 9.5', 'odds_recommended': 1.7,
           'confidence_score': 4, 'confidence_pct': 70, 'analyst_note': null, 'result': null}
        : {'id': 'p3', 'is_premium': true, 'locked': true, 'prediction_label': null,
           'odds_recommended': null, 'confidence_score': null, 'confidence_pct': null,
           'analyst_note': null, 'result': null},
  ],
};

final _abonne = UserEntity(
  id: 'u1', pseudo: 'Kevin', firstName: 'Kevin', lastName: 'Zongo',
  birthDate: DateTime(2000, 1, 11), phoneNumber: '+22670000000', countryCode: 'BF',
  subscriptionPlan: SubscriptionPlan.premium, referralCode: '1A639B', referralEarnings: 0,
  createdAt: DateTime(2026, 8, 16),
);

void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR');
    await initializeDateFormatting('fr');
    await preparerBanc();
  });

  group('la réponse du serveur', () {
    test('la liste envoie un nombre ; la fiche, les pronostics eux-mêmes', () {
      final liste = MatchModel.fromJson(_fiche(autres: 2));
      expect(liste.nbAutresPronostics, 2);
      expect(liste.autresPronostics, isEmpty);

      final fiche = MatchModel.fromJson(_fiche());
      expect(fiche.nbAutresPronostics, 2);
      expect(fiche.autresPronostics.map((a) => a.id), ['p2', 'p3']);
      expect(fiche.autresPronostics[0].oddsRecommended, 1.95);
      expect(fiche.autresPronostics[0].pourcentageConfiance, 62);
      expect(fiche.autresPronostics[1].isLocked, isTrue);
      expect(fiche.autresPronostics[1].predictionLabel, isEmpty);
    });

    test('un serveur d\'avant (sans le champ) : aucun autre pronostic', () {
      final ancien = MatchModel.fromJson(_fiche()..remove('autres_pronostics'));
      expect(ancien.nbAutresPronostics, 0);
      expect(ancien.autresPronostics, isEmpty);
    });

    test('le cache relit ce qu\'il a écrit', () {
      final relu = MatchModel.fromJson(MatchModel.fromJson(_fiche()).toJson());
      expect(relu.autresPronostics.map((a) => a.id), ['p2', 'p3']);
      expect(relu.autresPronostics[0].analystNote, 'Deux attaques en forme.');
      expect(MatchModel.fromJson(MatchModel.fromJson(_fiche(autres: 3)).toJson()).nbAutresPronostics, 3);
    });

    test('sur iPhone, les autres pronostics perdent aussi leur cote', () {
      final sans = MatchModel.fromJson(_fiche(vipOuvert: true)).sansCotes();
      expect(sans.autresPronostics.every((a) => a.oddsRecommended == 0), isTrue);
      expect(sans.autresPronostics[0].pourcentageConfiance, 62);
    });
  });

  group('la fiche du match', () {
    Future<void> ouvrir(WidgetTester t, Map<String, dynamic> json,
        {UserEntity? utilisateur, bool iphone = false}) async {
      SharedPreferences.setMockInitialValues({'astuce_suivre_match_vue': true});
      t.view.physicalSize = const Size(1170, 2532); t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      final routeur = GoRouter(routes: [
        GoRoute(path: '/', builder: (_, _) => const MatchDetailPage(matchId: 'm')),
        GoRoute(path: '/compte/activer-premium', builder: (_, _) => const Scaffold(body: Text('OFFRE PREMIUM'))),
      ]);
      await t.pumpWidget(ProviderScope(overrides: [...donneesCommunes(utilisateur: utilisateur),
        sansPariProvider.overrideWithValue(iphone),
        matchDetailProvider('m').overrideWith((ref) async => MatchModel.fromJson(json)),
        matchStatsProvider('m').overrideWith((ref) async => null),
        lineupsProvider('m').overrideWith((ref) async => const LineupsData(available: false)),
        injuriesProvider('m').overrideWith((ref) async => []),
        h2hProvider('m').overrideWith((ref) async => throw Exception('none')),
        playerRatingsProvider('m').overrideWith((ref) async => []),
        articlesDuMatchProvider('m').overrideWith((ref) async => null),
      ], child: MaterialApp.router(theme: AppTheme.dark, routerConfig: routeur)));
      for (var i = 0; i < 20; i++) { await t.pump(const Duration(milliseconds: 100)); }
    }

    Finder dansLaSection(Finder f) =>
        find.descendant(of: find.byKey(const Key('autres-pronostics')), matching: f);

    testWidgets('compte gratuit : le gratuit en entier, le VIP verrouillé mène à l\'offre', (t) async {
      await ouvrir(t, _fiche());
      expect(find.byKey(const Key('autres-pronostics')), findsOneWidget);
      expect(dansLaSection(find.text('AUTRES PRONOSTICS')), findsOneWidget);
      expect(dansLaSection(find.text('TOTAL BUTS')), findsOneWidget);
      expect(dansLaSection(find.textContaining('2.5')), findsOneWidget);
      expect(dansLaSection(find.text('1.95')), findsOneWidget);
      expect(dansLaSection(find.text('Confiance 62 %')), findsOneWidget);
      expect(dansLaSection(find.text('Deux attaques en forme.')), findsOneWidget);
      // Le VIP : ni choix, ni cote.
      expect(dansLaSection(find.text('Pronostic VIP')), findsOneWidget);
      expect(dansLaSection(find.textContaining('Corners')), findsNothing);
      expect(t.takeException(), isNull);

      final verrou = find.byKey(const Key('autre-prono-verrouille-p3'));
      await t.ensureVisible(verrou);
      await t.tap(verrou);
      await t.pumpAndSettle();
      expect(find.text('OFFRE PREMIUM'), findsOneWidget);
    });

    testWidgets('abonné : le VIP en clair, avec sa pastille', (t) async {
      await ouvrir(t, _fiche(vipOuvert: true), utilisateur: _abonne);
      expect(dansLaSection(find.text('Pronostic VIP')), findsNothing);
      expect(dansLaSection(find.text('CORNERS')), findsOneWidget);
      expect(dansLaSection(find.text('1.70')), findsOneWidget);
      expect(dansLaSection(find.text('VIP')), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('un VIP que le serveur dit ouvert reste fermé à un compte gratuit', (t) async {
      // Réponse en cache d'avant l'échéance : l'état local tranche.
      await ouvrir(t, _fiche(vipOuvert: true));
      expect(dansLaSection(find.text('Pronostic VIP')), findsOneWidget);
      expect(dansLaSection(find.text('CORNERS')), findsNothing);
    });

    testWidgets('iPhone : aucune cote', (t) async {
      await ouvrir(t, _fiche(vipOuvert: true), utilisateur: _abonne, iphone: true);
      expect(dansLaSection(find.text('COTE')), findsNothing);
      expect(dansLaSection(find.text('1.95')), findsNothing);
      expect(dansLaSection(find.text('Confiance 62 %')), findsOneWidget);
    });

    testWidgets('un seul pronostic : pas de section', (t) async {
      await ouvrir(t, _fiche(autres: const []));
      expect(find.byKey(const Key('autres-pronostics')), findsNothing);
      expect(find.text('AUTRES PRONOSTICS'), findsNothing);
    });
  });

  group('la carte de la liste', () {
    MatchEntity carte({int autres = 0, bool vip = false}) => MatchModel.fromJson({
      ..._fiche(autres: autres), 'is_premium': vip, 'locked': vip,
      if (vip) ...{'prediction_label': null, 'odds_recommended': null},
    });

    Future<void> monter(WidgetTester t, MatchEntity m) async {
      await t.pumpWidget(ProviderScope(
        overrides: donneesCommunes(),
        child: MaterialApp.router(
          theme: AppTheme.dark,
          routerConfig: GoRouter(routes: [
            GoRoute(path: '/', builder: (_, _) => Scaffold(body: SingleChildScrollView(
              child: MatchCardWidget(match: m)))),
            GoRoute(path: '/pronostics/:id', builder: (_, etat) =>
              Scaffold(body: Text('FICHE ${etat.pathParameters['id']}'))),
          ]),
        ),
      ));
      await t.pump();
    }

    testWidgets('« +2 pronos », et rien sans autre pronostic', (t) async {
      await monter(t, carte(autres: 2));
      expect(find.text('+2 pronos'), findsOneWidget);
      await monter(t, carte());
      expect(find.byKey(const Key('carte-autres-pronostics')), findsNothing);
      // L'animation de la jauge de confiance.
      await t.pumpAndSettle();
    });

    testWidgets('principal VIP verrouillé mais d\'autres pronostics : la carte ouvre la fiche', (t) async {
      await monter(t, carte(autres: 1, vip: true));
      expect(find.text('+1 prono'), findsOneWidget);
      await t.tap(find.byType(MatchCardWidget));
      await t.pumpAndSettle();
      expect(find.text('FICHE m'), findsOneWidget);
    });
  });
}

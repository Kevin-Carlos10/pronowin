import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronowin/core/config/distribution_channel.dart';
import 'package:pronowin/core/services/reglages_systeme.dart';
import 'package:pronowin/core/theme/app_theme.dart';
import 'package:pronowin/features/abonnement/presentation/pages/activer_premium_page.dart';
import 'package:pronowin/features/abonnement/presentation/providers/subscription_provider.dart';
import 'package:pronowin/features/auth/domain/entities/user_entity.dart';
import 'package:pronowin/features/parametres/presentation/providers/settings_provider.dart';
import 'package:pronowin/features/parametres/presentation/widgets/notifications_telephone.dart';
import 'package:pronowin/features/pronostics/data/models/match_model.dart';
import 'package:pronowin/features/pronostics/domain/entities/match_entity.dart';
import 'package:pronowin/features/pronostics/presentation/providers/pronostics_provider.dart' show MatchEvent;
import 'package:pronowin/features/pronostics/presentation/widgets/fil_evenements.dart';
import 'package:pronowin/features/pronostics/presentation/widgets/fond_equipes.dart';
import 'package:pronowin/features/pronostics/presentation/widgets/ligne_match_compacte.dart';
import 'package:pronowin/features/pronostics/presentation/widgets/match_card_widget.dart';
import 'package:pronowin/shared/providers/favoris_provider.dart';
import 'package:pronowin/shared/widgets/suivre_match.dart';

import 'aides/banc_ecran.dart';

/// Corrections tirées des vidéos du 8 novembre 2026 (PronoWin à côté de
/// Sofascore et de 1xBet).
void main() {
  setUpAll(() async => preparerBanc());

  MatchEntity match({MatchStatus status = MatchStatus.live, int? minute, bool cotes = true}) => MatchEntity(
        id: 'm1', league: 'La Liga', leagueCountry: 'ES',
        homeTeam: 'Real Sociedad', awayTeam: 'Rayo Vallecano',
        matchDate: DateTime(2026, 11, 8, 15, 15), status: status,
        homeScore: 0, awayScore: 0, elapsed: minute,
        predictionType: PredictionType.btts, predictionLabel: 'Les deux équipes marquent',
        oddsRecommended: 0, oddsHome: cotes ? 1.5 : 0, oddsDraw: cotes ? 4 : 0, oddsAway: cotes ? 7.5 : 0,
        confidenceScore: 4, confidencePct: 71, isPremium: false,
        homeFormPoints: 7, awayFormPoints: 5,
      );

  Future<void> monter(WidgetTester t, Widget enfant) async {
    t.view.physicalSize = const Size(800, 1600);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(
      child: MaterialApp(theme: AppTheme.dark,
        home: Scaffold(body: ListView(padding: const EdgeInsets.all(12), children: [enfant]))),
    ));
    await t.pump();
    // Les animations des cartes (pulsation LIVE, jauge) ont des minuteurs :
    // on démonte avant la fin du test.
    addTearDown(() async {
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(seconds: 2));
    });
  }

  group('la minute du direct', () {
    test('le serveur l\'envoie, le modèle la lit', () {
      final m = MatchModel.fromJson({
        'id': 'm1', 'league': 'La Liga', 'home_team': 'A', 'away_team': 'B',
        'match_date': '2026-11-08T15:15:00.000Z', 'status': 'live',
        'home_score': 1, 'away_score': 0, 'elapsed': 67,
      });
      expect(m.elapsed, 67);
      expect(m.toJson()['elapsed'], 67);
      expect(m.sansCotes().elapsed, 67);
    });

    testWidgets("la carte dit « 67' » plutôt que « En direct »", (t) async {
      await monter(t, MatchCardWidget(match: match(minute: 67)));
      expect(find.text("67'"), findsOneWidget);
      expect(find.text('En direct'), findsNothing);
    });

    testWidgets('sans minute publiée : « En direct »', (t) async {
      await monter(t, MatchCardWidget(match: match()));
      expect(find.text('En direct'), findsOneWidget);
    });

    testWidgets('la ligne compacte aussi', (t) async {
      await monter(t, LigneMatchCompacte(match: match(minute: 23)));
      expect(find.text("23'"), findsOneWidget);
    });
  });

  group('« VAINQUEUR DU MATCH »', () {
    testWidgets('avec des cotes : le titre et la rangée', (t) async {
      await monter(t, MatchCardWidget(match: match(status: MatchStatus.upcoming)));
      expect(find.text('VAINQUEUR DU MATCH'), findsOneWidget);
    });

    testWidgets('sans cote : pas de titre au-dessus de rien', (t) async {
      await monter(t, MatchCardWidget(match: match(status: MatchStatus.upcoming, cotes: false)));
      expect(find.text('VAINQUEUR DU MATCH'), findsNothing);
    });
  });

  group('les buteurs de l\'en-tête', () {
    test('le prénom devient une initiale, les particules restent', () {
      expect(abregerJoueur('Nicolas Jackson'), 'N. Jackson');
      expect(abregerJoueur('Kevin De Bruyne'), 'K. De Bruyne');
      expect(abregerJoueur('Alysson Edward Fraga Dos Santos'), 'A. Dos Santos');
      expect(abregerJoueur('N. Jackson'), 'N. Jackson');
      expect(abregerJoueur('Rodri'), 'Rodri');
    });

    test('le nom et les minutes séparés, regroupés par joueur', () {
      MatchEvent but(String joueur, int minute, String equipe, {String detail = 'Normal Goal'}) =>
          MatchEvent(minute: minute, type: 'Goal', detail: detail, team: equipe, player: joueur);
      final d = buteursDetailles([
        but('Alysson Edward', 1, 'Aston Villa'),
        but('Nicolas Jackson', 4, 'Aston Villa'),
        but('Nicolas Jackson', 70, 'Aston Villa', detail: 'Penalty'),
      ], domicile: 'Manchester United', scoreFinal: (dom: 0, ext: 3));
      expect(d.dom, isEmpty);
      expect(d.ext, [(joueur: 'Alysson Edward', minutes: "1'"), (joueur: 'Nicolas Jackson', minutes: "4', 70' (pen.)")]);
      // Le texte d'avant, pour les lecteurs d'écran, ne change pas.
      expect(buteursDuMatch([but('Nicolas Jackson', 4, 'Aston Villa')], domicile: 'Manchester United').ext,
          ["Nicolas Jackson 4'"]);
    });
  });

  group('notifications coupées sur le téléphone', () {
    late bool ouvert;
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      ouvert = false;
      ReglagesSysteme.ouvrirNotifications = () async => ouvert = true;
    });
    late int demandes;
    setUp(() {
      demandes = 0;
      ReglagesSysteme.demander = () async { demandes++; return true; };
    });
    tearDown(() {
      ReglagesSysteme.lireEtat = () async => EtatNotifications.inconnu;
    });

    Future<void> monterCloche(WidgetTester t) async {
      await t.pumpWidget(ProviderScope(
        overrides: [favorisProvider.overrideWith(_FavorisFaux.new)],
        child: MaterialApp.router(routerConfig: GoRouter(routes: [
          GoRoute(path: '/', builder: (_, _) => Scaffold(body: Consumer(builder: (context, ref, _) {
            // Chargés au démarrage de l'application, bien avant le geste.
            ref.watch(settingsProvider);
            ref.watch(favorisProvider);
            return IconButton(
              key: const Key('cloche'), icon: const Icon(Icons.notifications),
              onPressed: () => basculerSuivi(context, 'm1'));
          }))),
        ])),
      ));
      await t.pump();
    }

    testWidgets('suivre un match le dit, et « Réglages » les ouvre', (t) async {
      ReglagesSysteme.lireEtat = () async => EtatNotifications.refusees;
      await monterCloche(t);
      await t.tap(find.byKey(const Key('cloche')));
      await t.pump();
      await t.pump();
      expect(find.textContaining('notifications sont coupées sur ce téléphone'), findsOneWidget);
      // Le message finit d'entrer avant qu'on touche son bouton.
      await t.pump(const Duration(milliseconds: 500));
      await t.tap(find.text('Réglages'));
      await t.pump();
      expect(ouvert, isTrue);
    });

    testWidgets('autorisées : la promesse habituelle', (t) async {
      ReglagesSysteme.lireEtat = () async => EtatNotifications.autorisees;
      await monterCloche(t);
      await t.tap(find.byKey(const Key('cloche')));
      await t.pump();
      await t.pump();
      expect(find.text("Match suivi : tu recevras le coup d'envoi, les buts et le résultat."), findsOneWidget);
    });

    testWidgets('jamais demandé : « Être notifié » d\'abord, puis la question du téléphone', (t) async {
      ReglagesSysteme.lireEtat = () async => EtatNotifications.aDemander;
      await monterCloche(t);
      await t.tap(find.byKey(const Key('cloche')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('etre-notifie')), findsOneWidget);
      expect(find.textContaining('chaque but et le résultat de ce match'), findsOneWidget);
      expect(demandes, 0, reason: 'la question du téléphone attend la réponse à l\'explication');
      await t.tap(find.byKey(const Key('etre-notifie-autoriser')));
      await t.pumpAndSettle();
      expect(demandes, 1);
      expect(find.text("Match suivi : tu recevras le coup d'envoi, les buts et le résultat."), findsOneWidget);
    });

    testWidgets('« Plus tard » : pas de question du téléphone, et on le dit', (t) async {
      ReglagesSysteme.lireEtat = () async => EtatNotifications.aDemander;
      await monterCloche(t);
      await t.tap(find.byKey(const Key('cloche')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('etre-notifie-plus-tard')));
      await t.pumpAndSettle();
      expect(demandes, 0);
      expect(find.text('Match suivi. Les alertes arriveront dès que tu autoriseras les notifications.'), findsOneWidget);
    });

    testWidgets('Paramètres, jamais demandé : « Activer les notifications »', (t) async {
      ReglagesSysteme.lireEtat = () async => EtatNotifications.aDemander;
      await monter(t, const AlerteNotificationsTelephone());
      await t.pump();
      expect(find.byKey(const Key('notifications-a-activer')), findsOneWidget);
      await t.tap(find.text('Activer les notifications'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('etre-notifie-autoriser')));
      await t.pumpAndSettle();
      expect(demandes, 1);
    });

    testWidgets('Paramètres : l\'encart, puis son bouton', (t) async {
      ReglagesSysteme.lireEtat = () async => EtatNotifications.refusees;
      await monter(t, const AlerteNotificationsTelephone());
      await t.pump();
      expect(find.byKey(const Key('notifications-telephone-coupees')), findsOneWidget);
      await t.tap(find.text('Ouvrir les réglages'));
      expect(ouvert, isTrue);
    });

    testWidgets('Paramètres, autorisées : rien', (t) async {
      ReglagesSysteme.lireEtat = () async => EtatNotifications.autorisees;
      await monter(t, const AlerteNotificationsTelephone());
      await t.pump();
      expect(find.byKey(const Key('notifications-telephone-coupees')), findsNothing);
    });
  });

  group('fond de l\'en-tête teinté par les équipes (Sofascore)', () {
    Widget fond({bool contraste = false}) => MediaQuery(
      data: MediaQueryData(size: const Size(393, 260), highContrast: contraste),
      child: const Directionality(textDirection: TextDirection.ltr, child: SizedBox(width: 393, height: 260,
        child: FondEquipes(fond: Color(0xFF0D1220),
          domicile: ColoredBox(color: Color(0xFFDA291C)), exterieur: ColoredBox(color: Color(0xFF670E36))))));

    testWidgets('les deux logos, floutés et en transparence, sous un voile', (t) async {
      await t.pumpWidget(fond());
      expect(find.byKey(const Key('halo-domicile')), findsOneWidget);
      expect(find.byKey(const Key('halo-exterieur')), findsOneWidget);
      expect(find.byType(ImageFiltered), findsNWidgets(2));
      expect(t.widget<Opacity>(find.descendant(of: find.byKey(const Key('halo-domicile')), matching: find.byType(Opacity))).opacity,
          FondEquipes.opacite);
    });

    testWidgets('contraste élevé : un aplat, rien derrière le texte', (t) async {
      await t.pumpWidget(fond(contraste: true));
      expect(find.byType(ImageFiltered), findsNothing);
    });
  });

  testWidgets('page d\'abonnement : un abonné voit qu\'il l\'est déjà', (t) async {
    t.view.physicalSize = const Size(900, 2400);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    final abonne = UserEntity(
      id: 'u1', pseudo: 'Kevin', firstName: 'Kevin', lastName: 'Zongo',
      birthDate: DateTime(2000, 1, 11), phoneNumber: '+22670000000', countryCode: 'BF',
      subscriptionPlan: SubscriptionPlan.premium,
      subscriptionExpiresAt: DateTime.now().add(const Duration(days: 20)),
      referralCode: '1A639B', referralEarnings: 0, createdAt: DateTime(2026, 8, 16),
    );
    await t.pumpWidget(ProviderScope(
      overrides: [
        ...donneesCommunes(utilisateur: abonne),
        currentSubscriptionProvider.overrideWith((ref) async => {
          'plan': 'premium', 'days_left': 20,
          'expires_at': DateTime.now().add(const Duration(days: 20)).toUtc().toIso8601String(),
          'premium_price_monthly_usd': 10, 'premium_price_annual_usd': 90,
          'payment_methods': [{'key': 'orange_money', 'label': 'Orange Money', 'phone': '22645568158'}],
        }),
        isStoreBuildProvider.overrideWithValue(false),
      ],
      child: const MaterialApp(home: ActiverPremiumPage()),
    ));
    await t.pump();
    t.takeException();
    await t.pump(const Duration(milliseconds: 600));
    t.takeException();
    expect(find.byKey(const Key('deja-premium')), findsOneWidget);
    expect(find.textContaining('Ton Premium est actif jusqu'), findsOneWidget);
    addTearDown(() async {
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(seconds: 2));
    });
  });
}

class _FavorisFaux extends FavorisNotifier {
  @override
  Future<EtatFavoris> build() async => const EtatFavoris();
  @override
  Future<void> basculerMatch(String matchId) async {
    final ids = {...state.value!.matchIds};
    ids.contains(matchId) ? ids.remove(matchId) : ids.add(matchId);
    state = AsyncData(EtatFavoris(matchIds: ids));
  }
}

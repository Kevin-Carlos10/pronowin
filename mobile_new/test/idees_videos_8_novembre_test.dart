import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pronowin/core/network/dio_client.dart';
import 'package:pronowin/core/router/onglet_demarrage.dart';
import 'package:pronowin/shared/providers/favoris_provider.dart';
import 'package:pronowin/shared/widgets/alertes_match.dart';
import 'package:pronowin/features/pronostics/presentation/widgets/equipes_suivies.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pronowin/core/theme/app_theme.dart';
import 'package:pronowin/features/abonnement/domain/essai_gratuit.dart';
import 'package:pronowin/features/abonnement/presentation/pages/activer_premium_page.dart' show libelleEssai;
import 'package:pronowin/features/competitions/competitions.dart';
import 'package:pronowin/features/pronostics/domain/entities/match_entity.dart';
import 'package:pronowin/features/pronostics/domain/matchs_recommandes.dart';
import 'package:pronowin/features/pronostics/presentation/providers/fiche_match_provider.dart';
import 'package:pronowin/features/pronostics/presentation/widgets/carte_match_partage.dart';
import 'package:pronowin/features/pronostics/presentation/widgets/decompte_coup_envoi.dart';

import 'aides/banc_ecran.dart';

/// Les idées reprises des vidéos du 8 novembre 2026 (Sofascore, 1xBet).
void main() {
  setUpAll(() async => preparerBanc());

  MatchEntity m(String id, MatchStatus status, {bool prono = false, int heures = 0, String league = 'Premier League'}) => MatchEntity(
        id: id, league: league, leagueCountry: 'PL',
        homeTeam: 'Manchester United', awayTeam: 'Aston Villa',
        matchDate: DateTime(2026, 11, 8, 16, 30).add(Duration(hours: heures)), status: status,
        homeScore: status == MatchStatus.upcoming ? null : 0, awayScore: status == MatchStatus.upcoming ? null : 2,
        predictionType: PredictionType.btts, predictionLabel: 'Les deux équipes marquent', hasPronostic: prono,
        oddsRecommended: 0, oddsHome: 0, oddsDraw: 0, oddsAway: 0, confidenceScore: 4, isPremium: false,
        homeFormPoints: 7, awayFormPoints: 5,
      );

  group('compte à rebours avant le coup d\'envoi (1xBet)', () {
    tearDown(() => DecompteCoupEnvoi.horloge = DateTime.now);

    test('heures, minutes, secondes', () {
      expect(texteDecompte(const Duration(hours: 3, minutes: 19, seconds: 13)), '03:19:13');
      expect(texteDecompte(const Duration(seconds: -5)), '00:00:00');
    });

    testWidgets('à moins de 24 h il décompte, au-delà il se tait', (t) async {
      var maintenant = DateTime(2026, 11, 8, 16, 0, 0);
      DecompteCoupEnvoi.horloge = () => maintenant;
      Widget decompte(DateTime coup) => Directionality(textDirection: TextDirection.ltr,
        child: DecompteCoupEnvoi(coupEnvoi: coup,
          builder: (_, reste) => Text(reste == null ? 'date' : texteDecompte(reste))));
      await t.pumpWidget(decompte(DateTime(2026, 11, 8, 19, 19, 13)));
      expect(find.text('03:19:13'), findsOneWidget);
      maintenant = maintenant.add(const Duration(seconds: 1));
      await t.pump(const Duration(seconds: 1));
      expect(find.text('03:19:12'), findsOneWidget);
      await t.pumpWidget(decompte(DateTime(2026, 11, 10, 20)));
      expect(find.text('date'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });
  });

  group('recommandés quand on ne suit rien (1xBet)', () {
    test('le direct pronostiqué d\'abord, jamais un match terminé', () {
      final r = matchsRecommandes([
        m('fini', MatchStatus.finished, prono: true),
        m('avenir', MatchStatus.upcoming, heures: 3),
        m('avenir-prono', MatchStatus.upcoming, prono: true, heures: 4),
        m('direct', MatchStatus.live),
        m('direct-prono', MatchStatus.live, prono: true),
      ]);
      expect(r.map((e) => e.id), ['direct-prono', 'direct', 'avenir-prono', 'avenir']);
      expect(matchsRecommandes(List.generate(9, (i) => m('$i', MatchStatus.upcoming, heures: i))), hasLength(5));
    });
  });

  group('grandes compétitions (1xBet, Sofascore)', () {
    testWidgets('la rangée de l\'accueil : les sept compétitions', (t) async {
      await t.pumpWidget(ProviderScope(child: MaterialApp(theme: AppTheme.dark,
        home: const Scaffold(body: SingleChildScrollView(child: GrandesCompetitions())))));
      expect(find.text('Grandes compétitions'), findsOneWidget);
      expect(find.text('Ligue des champions'), findsOneWidget);
      expect(competitionDe('AF_3')?.logo, 'https://media.api-sports.io/football/leagues/3.png');
    });

    testWidgets('la page : les matchs de la semaine, jour par jour', (t) async {
      final serveur = _Serveur();
      final maintenant = DateTime.now();
      serveur.reponse = {
        'data': [
          for (final (i, j) in [0, 0, 1].indexed)
            {'id': 'm$i', 'league': 'Premier League', 'league_country': 'PL', 'home_team': 'Arsenal $i', 'away_team': 'Chelsea $i',
             'match_date': DateTime(maintenant.year, maintenant.month, maintenant.day, 23, 0).add(Duration(days: j)).toUtc().toIso8601String(),
             'status': 'upcoming', 'has_pronostic': false},
        ],
        'nextCursor': null, 'hasMore': false,
      };
      await t.pumpWidget(ProviderScope(
        overrides: [...donneesCommunes(), dioProvider.overrideWithValue(Dio()..httpClientAdapter = serveur)],
        child: MaterialApp(theme: AppTheme.dark, home: const CompetitionPage(code: 'PL'))));
      for (var i = 0; i < 5; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      expect(serveur.parametres['league_code'], 'PL');
      expect(serveur.parametres['date_filter'], 'week');
      expect(find.text("Aujourd'hui"), findsOneWidget);
      expect(find.text('Demain'), findsOneWidget);
      expect(find.text('Arsenal 2'), findsOneWidget);
    });
  });

  group('partager l\'image d\'un match (Sofascore)', () {
    testWidgets('score, état, buteurs, domaine — sans débordement', (t) async {
      t.view.physicalSize = const Size(800, 1400);
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(theme: AppTheme.dark, home: Scaffold(body: Center(child: CarteMatchPartage(
        match: m('x', MatchStatus.live), dom: 0, ext: 2, minute: 67,
        buteurs: (dom: const [], ext: [(joueur: 'Nicolas Jackson', minutes: "4'"), (joueur: 'Alysson Edward', minutes: "1'")]),
      )))));
      await t.pump();
      expect(find.text('0 - 2'), findsOneWidget);
      expect(find.text("67'"), findsOneWidget);
      expect(find.text("N. Jackson 4'"), findsOneWidget);
      expect(find.text('pronowin.space'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });

  group('joueur du match (Sofascore)', () {
    test('le résumé du serveur se lit', () {
      final v = VotesJoueurDuMatch.fromJson({
        'etat': 'ouvert', 'minute_ouverture': 80, 'total': 3, 'mon_vote': 10,
        'classement': [{'joueur_id': 10, 'nom': 'Nicolas Jackson', 'equipe': 'away', 'votes': 2, 'pourcentage': 67}],
      });
      expect(v.ouvert, isTrue);
      expect(v.classement.single.nom, 'Nicolas Jackson');
      expect(v.monVote, 10);
    });
  });

  group('essai gratuit (Sofascore)', () {
    test('la période Google Play', () {
      expect(essaiDepuisPeriodeIso('P3D'), (nombre: 3, unite: UniteEssai.jour));
      expect(essaiDepuisPeriodeIso('P1W', cycles: 2), (nombre: 2, unite: UniteEssai.semaine));
      expect(essaiDepuisPeriodeIso('n importe quoi'), isNull);
    });

    testWidgets('le libellé', (t) async {
      late String trois, un;
      await t.pumpWidget(MaterialApp(home: Builder(builder: (context) {
        trois = libelleEssai(context, (nombre: 3, unite: UniteEssai.jour));
        un = libelleEssai(context, (nombre: 1, unite: UniteEssai.mois));
        return const SizedBox();
      })));
      expect(trois, "3 jours d'essai gratuit");
      expect(un, "1 mois d'essai gratuit");
    });
  });

  group('deuxième lot du 8 novembre', () {
    testWidgets('l\'étoile de l\'en-tête suit l\'équipe (Sofascore)', (t) async {
      SharedPreferences.setMockInitialValues({});
      late ProviderContainer c;
      await t.pumpWidget(ProviderScope(
        overrides: donneesCommunes(),
        child: MaterialApp(theme: AppTheme.dark, home: Scaffold(body: Consumer(builder: (context, ref, _) {
          c = ProviderScope.containerOf(context);
          ref.watch(favorisProvider);
          return const Center(child: EtoileSuivreEquipe(nom: 'Aston Villa',
            logo: 'https://media.api-sports.io/football/teams/66.png', competition: 'Premier League'));
        }))),
      ));
      await t.pump();
      await t.tap(find.byKey(const Key('etoile-equipe-66')));
      await t.pump();
      await t.pump();
      expect(c.read(favorisProvider).value!.suitEquipe(66), isTrue);
      expect(find.textContaining('Aston Villa est suivie'), findsOneWidget);
    });

    testWidgets('pas d\'identifiant d\'équipe : pas d\'étoile', (t) async {
      await t.pumpWidget(ProviderScope(overrides: donneesCommunes(),
        child: const MaterialApp(home: EtoileSuivreEquipe(nom: 'Inconnue', logo: null))));
      expect(find.byType(IconButton), findsNothing);
    });

    test('onglet d\'ouverture (Sofascore)', () {
      expect(ongletDepuisPreference(null), OngletDemarrage.accueil);
      expect(ongletDepuisPreference('suivis'), OngletDemarrage.suivis);
      expect(ongletDepuisPreference('autre chose'), OngletDemarrage.accueil);
      expect(cheminDemarrage(OngletDemarrage.accueil), '/home');
      expect(cheminDemarrage(OngletDemarrage.suivis), '/pronostics');
    });

    testWidgets('en direct dans les grandes compétitions, pas les autres (1xBet)', (t) async {
      final serveur = _Serveur();
      Map<String, dynamic> direct(String id, String code) => {
        'id': id, 'league': code, 'league_country': code, 'home_team': 'Dom $id', 'away_team': 'Ext $id',
        'match_date': DateTime.now().subtract(const Duration(minutes: 40)).toUtc().toIso8601String(),
        'status': 'live', 'elapsed': 40, 'has_pronostic': false,
      };
      serveur.reponse = {'data': [direct('a', 'PL'), direct('b', 'AF_525'), direct('c', 'CL')], 'nextCursor': null, 'hasMore': false};
      await t.pumpWidget(ProviderScope(
        overrides: [dioProvider.overrideWithValue(Dio()..httpClientAdapter = serveur)],
        child: MaterialApp(theme: AppTheme.dark, home: const Scaffold(body: SingleChildScrollView(child: DirectGrandesCompetitions())))));
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      expect(serveur.parametres['status'], 'live');
      expect(find.text('En direct dans les grandes compétitions'), findsOneWidget);
      expect(find.text('Dom a'), findsOneWidget);
      expect(find.text('Dom c'), findsOneWidget);
      expect(find.text('Dom b'), findsNothing);
      // La Ligue des champions avant la Premier League, dans l'ordre de la rangée.
      expect(t.getTopLeft(find.text('Dom c')).dy, lessThan(t.getTopLeft(find.text('Dom a')).dy));
    });

    testWidgets('les alertes de but disent penalties et VAR', (t) async {
      late String libelle;
      await t.pumpWidget(MaterialApp(home: Builder(builder: (context) {
        libelle = libelleAlerte(context, 'buts');
        return const SizedBox();
      })));
      expect(libelle, 'Buts, penalties et VAR');
    });
  });
}

class _Serveur implements HttpClientAdapter {
  Map<String, dynamic> reponse = {};
  Map<String, dynamic> parametres = {};
  final chemins = <String>[];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? a) async {
    chemins.add(o.path);
    if (o.path.startsWith('/pronostics')) parametres = o.queryParameters;
    return ResponseBody.fromString(jsonEncode(reponse), 200,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
  }

  @override
  void close({bool force = false}) {}
}

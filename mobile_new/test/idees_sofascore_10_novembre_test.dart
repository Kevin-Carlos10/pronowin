import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronowin/core/network/dio_client.dart';
import 'package:pronowin/core/theme/app_theme.dart';
import 'package:pronowin/core/utils/noms_courts.dart';
import 'package:pronowin/core/widgets/nom_equipe_adapte.dart';
import 'package:pronowin/features/competitions/competitions.dart';
import 'package:pronowin/features/pronostics/presentation/pages/pronostics_page.dart';
import 'package:pronowin/features/pronostics/presentation/pages/search_page.dart';
import 'package:pronowin/features/pronostics/presentation/providers/pronostics_provider.dart';
import 'package:pronowin/features/pronostics/presentation/widgets/fil_evenements.dart';
import 'package:pronowin/l10n/app_strings.dart';
import 'package:pronowin/shared/providers/favoris_provider.dart';

import 'aides/banc_ecran.dart';

/// Les idées reprises de Sofascore le 10 novembre 2026 : noms courts, filtres
/// du fil, recherches récentes, « Suivis » en trois rangements, page de
/// compétition en onglets, calendrier.
void main() {
  setUpAll(() async => preparerBanc());

  group('noms d\'équipe courts', () {
    test('les noms longs connus', () {
      expect(nomCourt('Manchester United'), 'Man Utd');
      expect(nomCourt('Paris Saint Germain'), 'PSG');
      expect(nomCourt('Paris Saint-Germain'), 'PSG');
      expect(nomCourt('Borussia Mönchengladbach'), "M'gladbach");
      expect(nomCourt('Bosnie-Herzégovine'), 'Bosnie');
      expect(nomCourt('Émirats arabes unis'), 'EAU');
    });

    test('les sigles de forme juridique tombent, la catégorie reste', () {
      expect(nomCourt('AS Roma'), 'Roma');
      expect(nomCourt('VfB Stuttgart'), 'Stuttgart');
      expect(nomCourt('1. FC Köln'), 'Köln');
      expect(nomCourt('Valencia CF'), 'Valencia');
      expect(nomCourt('Leeds United'), 'Leeds Utd');
      expect(nomCourt('Bosnie-Herzégovine U21'), 'Bosnie U21');
      expect(nomCourt('AS Douanes'), 'Douanes');
    });

    test('rien à raccourcir : le nom reste', () {
      expect(nomCourt('Arsenal'), 'Arsenal');
      expect(nomCourt('Real Madrid'), 'Real Madrid');
      expect(nomCourt('FC Ba'), 'FC Ba', reason: 'un sigle ne part pas s\'il ne reste presque rien');
      expect(nomCourt(''), '');
    });

    testWidgets('le nom court ne sert que si le complet ne tient pas', (t) async {
      Widget dans(double largeur) => MaterialApp(home: Scaffold(body: Center(child: SizedBox(
        width: largeur, child: const NomEquipeAdapte('Manchester United', style: TextStyle(fontSize: 14))))));
      await t.pumpWidget(dans(400));
      expect(find.text('Manchester United'), findsOneWidget);
      await t.pumpWidget(dans(80));
      expect(find.text('Man Utd'), findsOneWidget);
      // Les lecteurs d'écran gardent le nom complet.
      expect(find.bySemanticsLabel('Manchester United'), findsOneWidget);
    });
  });

  group('filtres du fil des événements', () {
    MatchEvent e(String type, int minute) =>
        MatchEvent(minute: minute, team: 'A', player: 'X', type: type, detail: 'd');

    test('« Tout » puis chaque catégorie présente ; une seule catégorie : aucun filtre', () {
      expect(filtresDisponibles([e('Goal', 10), e('Card', 20), e('subst', 60)]),
          [FiltreFil.tout, FiltreFil.buts, FiltreFil.cartons, FiltreFil.remplacements]);
      expect(filtresDisponibles([e('Goal', 10), e('Var', 12)]), isEmpty);
      expect(filtresDisponibles(const []), isEmpty);
    });

    test('le filtre garde les séparateurs de période', () {
      final fil = construireFil([e('Goal', 10), e('Card', 20), e('subst', 60)],
          domicile: 'A', termine: true, periodeAtteinte: 2, scoreFinal: (dom: 1, ext: 0));
      final cartons = filtrerFil(fil, FiltreFil.cartons);
      expect(cartons.where((l) => l.evenement != null).map((l) => l.evenement!.type), ['Card']);
      expect(cartons.where((l) => l.separateur != null), isNotEmpty);
      expect(filtrerFil(fil, FiltreFil.tout), fil);
    });
  });

  group('recherches récentes', () {
    test('la plus récente d\'abord, sans doublon, huit au plus', () async {
      SharedPreferences.setMockInitialValues({});
      for (final t in ['Arsenal', 'x', 'Chelsea', 'arsenal']) {
        await RecherchesRecentes.ajouter(t);
      }
      expect(await RecherchesRecentes.lire(), ['arsenal', 'Chelsea']);
      for (var i = 0; i < 10; i++) {
        await RecherchesRecentes.ajouter('Équipe $i');
      }
      expect(await RecherchesRecentes.lire(), hasLength(RecherchesRecentes.max));
      await RecherchesRecentes.effacer();
      expect(await RecherchesRecentes.lire(), isEmpty);
    });

    testWidgets('le champ vide propose les récentes et les grandes compétitions', (t) async {
      SharedPreferences.setMockInitialValues({RecherchesRecentes.cle: ['Arsenal']});
      await t.pumpWidget(ProviderScope(
        overrides: donneesCommunes(),
        child: MaterialApp(theme: AppTheme.dark, home: const SearchPage())));
      for (var i = 0; i < 5; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      expect(find.text('RECHERCHES RÉCENTES'), findsOneWidget);
      expect(find.byKey(const Key('recente-Arsenal')), findsOneWidget);
      expect(find.text('Premier League'), findsOneWidget);
      await t.tap(find.byKey(const Key('effacer-recherches')));
      await t.pump();
      await t.pump();
      expect(find.byKey(const Key('recente-Arsenal')), findsNothing);
      await t.pumpWidget(const SizedBox());
    });
  });

  group('page de compétition en onglets', () {
    Future<_Serveur> monter(WidgetTester t, String code) async {
      final serveur = _Serveur({
        '/pronostics/classement-ligue': [
          {'rank': 1, 'teamName': 'Arsenal', 'played': 11, 'goalsDiff': 15, 'points': 26, 'zone': 'Ligue des champions', 'zoneNature': 'c1'},
          {'rank': 2, 'teamName': 'Manchester City', 'played': 11, 'goalsDiff': 12, 'points': 22},
        ],
        '/pronostics/top-scorers': [
          {'rank': 1, 'name': 'E. Haaland', 'team': 'Manchester City', 'goals': 13, 'appearances': 11},
        ],
        '/pronostics': {'data': [], 'nextCursor': null, 'hasMore': false},
      });
      await t.pumpWidget(ProviderScope(
        overrides: [...donneesCommunes(), dioProvider.overrideWithValue(Dio()..httpClientAdapter = serveur)],
        child: MaterialApp(theme: AppTheme.dark, home: CompetitionPage(code: code))));
      for (var i = 0; i < 5; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      return serveur;
    }

    testWidgets('Matchs, Classement, Buteurs', (t) async {
      final serveur = await monter(t, 'PL');
      expect(find.byKey(const Key('onglets-competition')), findsOneWidget);
      expect(find.text('Buteurs'), findsOneWidget);
      await t.tap(find.text('Classement'));
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      expect(serveur.parametres['/pronostics/classement-ligue']?['league'], 'PL');
      expect(find.text('Arsenal'), findsOneWidget);
      expect(find.text('26'), findsOneWidget);
      // Hors d'un match : pas de « les équipes de ce match n'y figurent pas ».
      expect(find.textContaining('les équipes de ce match'), findsNothing);
      await t.tap(find.text('Buteurs'));
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      expect(find.text('E. Haaland'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('sans palmarès publié (codes AF_) : deux onglets', (t) async {
      await monter(t, 'AF_3');
      expect(find.text('Classement'), findsOneWidget);
      expect(find.text('Buteurs'), findsNothing);
      await t.pumpWidget(const SizedBox());
    });
  });

  group('Pronos : calendrier et retour à aujourd\'hui', () {
    Future<void> monter(WidgetTester t, {List<Override> plus = const []}) async {
      SharedPreferences.setMockInitialValues({'pseudo_nudge_dismissed': true});
      t.view.physicalSize = const Size(390 * 2, 844 * 2);
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      await t.pumpWidget(ProviderScope(
        overrides: [...donneesCommunes(), ...plus],
        child: MaterialApp.router(
          routerConfig: GoRouter(routes: [GoRoute(path: '/', builder: (_, _) => const PronosticsPage())]),
          theme: AppTheme.light,
          locale: const Locale('fr'),
          supportedLocales: AppStrings.supportedLocales,
          localizationsDelegates: const [
            AppStrings.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
        ),
      ));
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> demonter(WidgetTester t) async {
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(minutes: 1));
    }

    testWidgets('« Aujourd\'hui » n\'apparaît qu\'une fois parti d\'aujourd\'hui', (t) async {
      await monter(t);
      expect(find.byKey(const Key('calendrier-pronos')), findsOneWidget);
      expect(find.byKey(const Key('retour-aujourdhui')), findsNothing);
      final hier = DateTime.now().subtract(const Duration(days: 1));
      await t.tap(find.text('${hier.day}').first);
      for (var i = 0; i < 5; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(find.byKey(const Key('retour-aujourdhui')), findsOneWidget);
      await t.tap(find.byKey(const Key('retour-aujourdhui')));
      for (var i = 0; i < 5; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(find.byKey(const Key('retour-aujourdhui')), findsNothing);
      await demonter(t);
    });

    testWidgets('le calendrier s\'ouvre sur le jour choisi', (t) async {
      await monter(t);
      await t.tap(find.byKey(const Key('calendrier-pronos')));
      for (var i = 0; i < 5; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Aller au jour'), findsOneWidget);
      await t.tap(find.text('Annuler'));
      for (var i = 0; i < 5; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Aller au jour'), findsNothing);
      await demonter(t);
    });

    testWidgets('« Suivis » en trois rangements : matchs, équipes, ligues', (t) async {
      await monter(t, plus: [favorisMatchsProvider.overrideWith((ref) async => const [])]);
      await t.tap(find.text('Suivis').first);
      for (var i = 0; i < 5; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(find.byKey(const Key('vues-suivis')), findsOneWidget);
      await t.tap(find.byKey(const Key('vue-suivis-ligues')));
      for (var i = 0; i < 3; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(find.byKey(const Key('aucune-ligue-suivie')), findsOneWidget);
      expect(t.takeException(), isNull);
      await demonter(t);
    });
  });
}

/// Répond selon le chemin ; garde les paramètres de chaque chemin.
class _Serveur implements HttpClientAdapter {
  final Map<String, Object> reponses;
  final parametres = <String, Map<String, dynamic>>{};
  _Serveur(this.reponses);

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? a) async {
    parametres[o.path] = o.queryParameters;
    final r = reponses[o.path];
    return ResponseBody.fromString(jsonEncode(r ?? {}), r == null ? 404 : 200,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
  }

  @override
  void close({bool force = false}) {}
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:pronowin/core/theme/app_theme.dart';
import 'package:pronowin/features/joueurs/presentation/pages/fiche_joueur_page.dart';
import 'package:pronowin/features/joueurs/presentation/providers/fiche_joueur_provider.dart';
import 'package:pronowin/features/pronostics/presentation/pages/match_detail_page.dart';
import 'package:pronowin/features/pronostics/presentation/providers/pronostics_provider.dart';
import 'package:pronowin/l10n/catalog_en.dart';

import 'aides/banc_ecran.dart';

/// La fiche d'un joueur : un nom affiché dans les compositions, les notes, les
/// absences ou les palmarès s'ouvre désormais sur quelque chose.
void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR');
    await preparerBanc();
  });

  final attaquant = FicheJoueur(
    id: 1100, name: 'Erling Haaland', season: 2026, age: 26, nationality: 'Norway',
    height: '195 cm', weight: '88 kg', birthPlace: 'Leeds, England', birthDate: DateTime(2000, 7, 21),
    stats: const [
      StatsCompetition(team: 'Manchester City', league: 'Premier League', position: 'Attacker',
          appearances: 8, lineups: 8, minutes: 690, goals: 9, assists: 2, rating: 7.43,
          passAccuracy: 71, shots: 30, shotsOn: 18, yellowCards: 1),
      StatsCompetition(team: 'Manchester City', league: 'UEFA Champions League', position: 'Attacker',
          appearances: 3, minutes: 250, goals: 4),
    ],
    absences: [AbsenceJoueur(motif: 'Blessure aux ischio-jambiers', debut: DateTime(2025, 2, 1), fin: DateTime(2025, 2, 20))],
    transferts: [TransfertJoueur(date: DateTime(2022, 7, 1), type: '€ 60M', depuis: 'Dortmund', vers: 'Manchester City')],
  );

  const gardien = FicheJoueur(
    id: 2200, name: 'Ederson', season: 2026,
    stats: [StatsCompetition(team: 'Manchester City', league: 'Premier League', position: 'Goalkeeper',
        appearances: 8, minutes: 720, conceded: 6, saves: 21)],
  );

  Future<void> monter(WidgetTester t, Widget page,
      {double echelle = 1, double largeur = 390, List<Override> overrides = const []}) async {
    t.view.physicalSize = Size(largeur * 2, 1800 * 2);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.dark,
        home: MediaQuery(
          data: MediaQueryData(size: Size(largeur, 1800), textScaler: TextScaler.linear(echelle)),
          child: page),
      ),
    ));
    await t.pump();
    await t.pump();
  }

  Override fiche(FicheJoueur f) => ficheJoueurProvider.overrideWith((ref, id) async => f);

  testWidgets('qui il est, sa saison, ses absences et ses transferts', (t) async {
    await monter(t, const FicheJoueurPage(id: 1100), overrides: [fiche(attaquant)]);
    expect(find.text('Erling Haaland'), findsOneWidget);
    expect(find.text('Manchester City · Attaquant'), findsOneWidget);
    expect(find.text('26 ans'), findsOneWidget);
    expect(find.text('Saison 2026-27'), findsOneWidget);
    expect(find.text('7.43'), findsOneWidget);
    expect(find.text('30 (18)'), findsOneWidget);
    expect(find.text('Blessure aux ischio-jambiers'), findsOneWidget);
    expect(find.text('Dortmund'), findsOneWidget);

    // Une autre compétition, au toucher.
    await t.tap(find.byKey(const Key('competition-1')));
    await t.pump();
    expect(find.text('4'), findsWidgets);
    expect(find.text('7.43'), findsNothing);
  });

  testWidgets('un gardien : encaissés et arrêts, pas de tirs', (t) async {
    await monter(t, const FicheJoueurPage(id: 2200), overrides: [fiche(gardien)]);
    expect(find.text('Buts encaissés'), findsOneWidget);
    expect(find.text('Arrêts'), findsOneWidget);
    expect(find.text('Tirs (cadrés)'), findsNothing);
    expect(find.text('Absences récentes'), findsNothing);
  });

  testWidgets('un joueur inconnu du fournisseur le dit', (t) async {
    await monter(t, const FicheJoueurPage(id: 9),
        overrides: [ficheJoueurProvider.overrideWith((ref, id) async => throw const JoueurIntrouvable())]);
    expect(find.text("Ce joueur n'a pas de fiche disponible."), findsOneWidget);
  });

  for (final largeur in [320.0, 390.0]) {
    testWidgets('texte à 180 % · ${largeur.toInt()} px : rien ne déborde', (t) async {
      await monter(t, const FicheJoueurPage(id: 1100), echelle: 1.8, largeur: largeur, overrides: [fiche(attaquant)]);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('toucher un joueur du palmarès ouvre sa fiche', (t) async {
    t.view.physicalSize = const Size(390 * 2, 1400);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    final routeur = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, _) => Scaffold(body: SingleChildScrollView(child: palmaresCompetitionSeul('FL1')))),
      GoRoute(path: '/joueurs/:id', builder: (_, s) => Scaffold(body: Text('fiche ${s.pathParameters['id']}'))),
    ]);
    await t.pumpWidget(ProviderScope(
      overrides: [topScorersProvider.overrideWith((ref, p) async => const [
        TopScorer(id: 1100, rank: 1, name: 'Erling Haaland', team: 'Manchester City',
            goals: 9, assists: 2, penalties: 0, appearances: 8),
        TopScorer(rank: 2, name: 'Sans identifiant', team: 'X', goals: 5, assists: 0, penalties: 0, appearances: 8),
      ])],
      child: MaterialApp.router(theme: AppTheme.dark, routerConfig: routeur),
    ));
    await t.pump(); await t.pump();

    // Sans identifiant, la ligne reste inerte.
    await t.tap(find.text('Sans identifiant'));
    await t.pumpAndSettle();
    expect(find.textContaining('fiche '), findsNothing);

    await t.tap(find.text('Erling Haaland'));
    await t.pumpAndSettle();
    expect(find.text('fiche 1100'), findsOneWidget);
  });

  test('les textes de la fiche sont traduits', () {
    for (final cle in ['Fiche joueur', 'Saison {arg0}-{arg1}', 'Note moyenne', 'Buts encaissés',
        'Absences récentes', 'Transferts', "Ce joueur n'a pas de fiche disponible.", 'ouvrir la fiche du joueur']) {
      expect(englishMessages, contains(cle), reason: cle);
    }
  });
}

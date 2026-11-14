import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:pronowin/core/theme/app_theme.dart';
import 'package:pronowin/features/pronostics/domain/entities/match_entity.dart';
import 'package:pronowin/features/pronostics/presentation/widgets/ligne_match_compacte.dart';

import 'aides/banc_ecran.dart';

/// La liste du jour : une ligne par match sans pronostic (7 novembre 2026).
/// Chaque grande carte faisait ~170 points ; la ligne doit tenir sous 70, ne
/// rien répéter (« Aucune analyse publiée », la ligue) et ouvrir la fiche.
void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR');
    await preparerBanc();
  });

  MatchEntity match(String id, MatchStatus statut, {int? dom, int? ext}) => MatchEntity(
        id: id, league: 'Bundesliga', leagueCountry: 'DE',
        homeTeam: 'Borussia Mönchengladbach', awayTeam: 'Bayern München',
        matchDate: DateTime(2026, 11, 8, 15, 30),
        status: statut, homeScore: dom, awayScore: ext,
        predictionType: PredictionType.win1, predictionLabel: '',
        oddsRecommended: 0, oddsHome: 0, oddsDraw: 0, oddsAway: 0,
        confidenceScore: 0, isPremium: false, homeFormPoints: 0, awayFormPoints: 0,
        hasPronostic: false,
      );

  Future<void> monter(WidgetTester t, List<MatchEntity> matchs, {double largeur = 360, double echelle = 1}) async {
    t.view.physicalSize = Size(largeur * 2, 1600);
    t.view.devicePixelRatio = 2;
    t.platformDispatcher.textScaleFactorTestValue = echelle;
    addTearDown(t.view.reset);
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    await t.pumpWidget(ProviderScope(
      overrides: donneesCommunes(),
      child: MaterialApp.router(
        theme: AppTheme.dark,
        routerConfig: GoRouter(routes: [
          GoRoute(path: '/', builder: (_, _) => Scaffold(body: SingleChildScrollView(
            padding: const EdgeInsets.all(14), child: BlocLignesMatch(matchs: matchs)))),
          GoRoute(path: '/pronostics/:id', builder: (_, etat) =>
            Scaffold(body: Text('FICHE ${etat.pathParameters['id']}'))),
        ]),
      ),
    ));
    await t.pump();
  }

  testWidgets('à venir, en direct, terminé : l\'heure ou l\'état, le score, rien de répété', (t) async {
    await monter(t, [
      match('a', MatchStatus.upcoming),
      match('b', MatchStatus.live, dom: 1, ext: 2),
      match('c', MatchStatus.finished, dom: 3, ext: 0),
    ]);
    expect(find.text('15:30'), findsOneWidget);
    expect(find.text('En direct'), findsOneWidget);
    expect(find.text('Terminé'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('Aucune analyse publiée'), findsNothing);
    expect(find.text('Bundesliga'), findsNothing, reason: 'la ligue est dans l\'en-tête au-dessus');
    for (final ligne in t.widgetList(find.byType(LigneMatchCompacte))) {
      expect(t.getSize(find.byWidget(ligne)).height, lessThan(70));
    }
    expect(t.takeException(), isNull);
  });

  testWidgets('une ligne ouvre la fiche du match', (t) async {
    await monter(t, [match('m42', MatchStatus.upcoming)]);
    await t.tap(find.text('Borussia Mönchengladbach'));
    await t.pumpAndSettle();
    expect(find.text('FICHE m42'), findsOneWidget);
  });

  testWidgets('lecteur d\'écran : une phrase par match', (t) async {
    final poignee = t.ensureSemantics();
    await monter(t, [match('b', MatchStatus.live, dom: 1, ext: 2)]);
    expect(find.bySemanticsLabel(RegExp(r'Borussia Mönchengladbach 1, Bayern München 2\. En direct\.')), findsOneWidget);
    poignee.dispose();
  });

  for (final (largeur, echelle) in [(320.0, 1.0), (320.0, 1.6), (411.0, 2.0)]) {
    testWidgets('$largeur px, texte ×$echelle : rien ne déborde', (t) async {
      await monter(t, [
        match('a', MatchStatus.upcoming),
        match('b', MatchStatus.live, dom: 10, ext: 12),
        match('c', MatchStatus.finished, dom: 3, ext: 0),
      ], largeur: largeur, echelle: echelle);
      expect(t.takeException(), isNull);
    });
  }
}

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pronowin/core/theme/app_theme.dart';
import 'package:pronowin/features/pronostics/domain/entities/match_entity.dart';
import 'package:pronowin/features/pronostics/presentation/pages/match_detail_page.dart';
import 'package:pronowin/features/pronostics/presentation/providers/fiche_match_provider.dart';

import 'aides/banc_ecran.dart';

/// L'évolution au classement, journée par journée (7 novembre 2026).
void main() {
  setUpAll(() async => preparerBanc());

  final match = MatchEntity(
    id: 'm', league: 'Bundesliga', leagueCountry: 'BL1',
    homeTeam: 'Mainz 05', awayTeam: 'Bayern München',
    matchDate: DateTime(2026, 11, 7, 14, 30), status: MatchStatus.upcoming,
    predictionType: PredictionType.win2, predictionLabel: '',
    oddsRecommended: 0, oddsHome: 0, oddsDraw: 0, oddsAway: 0,
    confidenceScore: 0, isPremium: false, homeFormPoints: 0, awayFormPoints: 0,
    hasPronostic: false,
  );

  Future<void> monter(WidgetTester t, EvolutionClassement? e, {double echelle = 1}) async {
    t.view.physicalSize = const Size(640, 1600);
    t.view.devicePixelRatio = 2;
    t.platformDispatcher.textScaleFactorTestValue = echelle;
    addTearDown(t.view.reset);
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    await t.pumpWidget(ProviderScope(
      overrides: [...donneesCommunes(), evolutionClassementProvider('m').overrideWith((ref) async => e)],
      child: MaterialApp(theme: AppTheme.dark,
        home: Scaffold(body: SingleChildScrollView(child: evolutionClassementSeule(match)))),
    ));
    await t.pump();
    await t.pump();
  }

  const huit = EvolutionClassement(saison: 2026, equipes: 18, journees: [
    (journee: 1, domicile: 12, exterieur: 1), (journee: 2, domicile: 9, exterieur: 2),
    (journee: 3, domicile: 11, exterieur: 1), (journee: 8, domicile: 10, exterieur: 1),
  ]);

  testWidgets('deux courbes, la position actuelle de chaque équipe', (t) async {
    await monter(t, huit);
    expect(find.text('Évolution au classement'), findsOneWidget);
    expect(find.text('10e'), findsOneWidget);
    expect(find.text('1er'), findsOneWidget);
    final data = t.widget<LineChart>(find.byType(LineChart)).data;
    expect(data.lineBarsData, hasLength(2));
    expect(data.lineBarsData.last.spots.last, const FlSpot(8, -10), reason: 'la 1re place en haut : y = −position');
    expect(t.takeException(), isNull);
  });

  testWidgets('une seule journée, une coupe ou pas de réponse : rien', (t) async {
    await monter(t, const EvolutionClassement(saison: 2026, equipes: 18,
      journees: [(journee: 1, domicile: 3, exterieur: 4)]));
    expect(find.byType(LineChart), findsNothing);
    await monter(t, null);
    expect(find.text('Évolution au classement'), findsNothing);
  });

  testWidgets('texte agrandi ×1,8 : rien ne déborde', (t) async {
    await monter(t, huit, echelle: 1.8);
    expect(t.takeException(), isNull);
  });
}

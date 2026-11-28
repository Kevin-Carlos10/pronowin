import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pronowin/core/theme/app_theme.dart';
import 'package:pronowin/features/pronostics/domain/entities/match_entity.dart';
import 'package:pronowin/features/pronostics/domain/series_match.dart';
import 'package:pronowin/features/pronostics/presentation/pages/match_detail_page.dart';
import 'package:pronowin/features/pronostics/presentation/providers/fiche_match_provider.dart';
import 'package:pronowin/features/pronostics/presentation/providers/pronostics_provider.dart';

import 'aides/banc_ecran.dart';

/// « Séries » sur la fiche du match (7 novembre 2026), comme Sofascore.
void main() {
  setUpAll(() async => preparerBanc());

  group('ce qui mérite d\'être lu', () {
    test('une série de victoires prime sur « sans défaite » ; les comptes en k/N', () {
      final f = faitsNotables(const SeriesEquipe(sur: 10, victoires: 3, sansDefaite: 6,
          plusDe25Buts: 7, lesDeuxMarquent: 6, cleanSheets: 2, nAPasMarque: 1, marque: 8));
      expect(f, const [
        FaitSerie('Victoires de suite', '3'),
        FaitSerie('A marqué à chaque match', '8'),
        FaitSerie('Plus de 2,5 buts', '7/10'),
        FaitSerie('Les deux équipes marquent', '6/10'),
      ]);
    });

    test('une équipe en difficulté : sans victoire, sans marquer, peu de buts', () {
      final f = faitsNotables(const SeriesEquipe(sur: 10, sansVictoire: 5, defaites: 1,
          plusDe25Buts: 2, nAPasMarque: 5, sansDefaite: 0));
      expect(f, containsAll(const [
        FaitSerie('Sans victoire', '5'),
        FaitSerie('Moins de 2,5 buts', '8/10'),
        FaitSerie('Matchs sans marquer', '5/10'),
      ]));
    });

    test('rien d\'ordinaire n\'est affiché ; moins de cinq matchs : pas de compte', () {
      expect(faitsNotables(const SeriesEquipe(sur: 10, victoires: 1, sansDefaite: 1, plusDe25Buts: 5, lesDeuxMarquent: 5)), isEmpty);
      expect(faitsNotables(const SeriesEquipe(sur: 4, plusDe25Buts: 4, lesDeuxMarquent: 4)), isEmpty);
      expect(faitsNotables(const SeriesEquipe(sur: 0)), isEmpty);
    });

    test('face-à-face : buts, les deux marquent, invaincu face à l\'autre', () {
      const c = [
        (domicile: 'Mainz', exterieur: 'Bayern', butsDom: 3, butsExt: 4),
        (domicile: 'Bayern', exterieur: 'Mainz', butsDom: 2, butsExt: 2),
        (domicile: 'Bayern', exterieur: 'Mainz', butsDom: 3, butsExt: 0),
        (domicile: 'Mainz', exterieur: 'Bayern', butsDom: 2, butsExt: 1),
      ];
      expect(faitsFaceAFace(c, equipeA: 'Mainz', equipeB: 'Bayern'), const [
        FaitSerie('Plus de 2,5 buts', '4/4'),
        FaitSerie('Les deux équipes marquent', '3/4'),
      ]);
      expect(sansDefaiteFaceA(c, 'Bayern'), 3);
      expect(sansDefaiteFaceA(c, 'Mainz'), 0);
      expect(faitsFaceAFace(c.take(2).toList(), equipeA: 'Mainz', equipeB: 'Bayern'), isEmpty,
          reason: 'deux confrontations ne font pas une série');
    });
  });

  MatchEntity match(MatchStatus statut) => MatchEntity(
        id: 'm', league: 'Bundesliga', leagueCountry: 'DE',
        homeTeam: 'Mainz', awayTeam: 'Bayern', homeTeamLogo: '', awayTeamLogo: '',
        matchDate: DateTime(2026, 11, 7, 14, 30), status: statut,
        predictionType: PredictionType.win2, predictionLabel: '',
        oddsRecommended: 0, oddsHome: 0, oddsDraw: 0, oddsAway: 0,
        confidenceScore: 0, isPremium: false, homeFormPoints: 0, awayFormPoints: 0,
        hasPronostic: false,
      );

  Future<void> monter(WidgetTester t, MatchEntity m, {double echelle = 1}) async {
    t.view.physicalSize = const Size(640, 2400);
    t.view.devicePixelRatio = 2;
    t.platformDispatcher.textScaleFactorTestValue = echelle;
    addTearDown(t.view.reset);
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    await t.pumpWidget(ProviderScope(
      overrides: [
        ...donneesCommunes(),
        formeRecenteProvider('m').overrideWith((ref) async => const FormeRecente([], [],
          seriesDomicile: SeriesEquipe(sur: 10, sansVictoire: 4, nAPasMarque: 5),
          seriesExterieur: SeriesEquipe(sur: 10, victoires: 6, sansDefaite: 9, plusDe25Buts: 9))),
        h2hProvider('m').overrideWith((ref) async => H2HData(
          homeTeam: 'Mainz', awayTeam: 'Bayern', homeWins: 1, awayWins: 2, draws: 1, totalMatches: 4,
          matches: [
            for (final (d, e, a, b) in const [('Mainz', 'Bayern', 3, 4), ('Bayern', 'Mainz', 2, 2),
                ('Bayern', 'Mainz', 3, 0), ('Mainz', 'Bayern', 2, 1)])
              H2HMatchResult(date: DateTime(2025), homeTeam: d, awayTeam: e,
                homeScore: a, awayScore: b, winner: '', league: 'Bundesliga'),
          ])),
      ],
      child: MaterialApp(theme: AppTheme.dark,
        home: Scaffold(body: SingleChildScrollView(child: seriesSeules(m)))),
    ));
    await t.pump();
    await t.pump();
  }

  testWidgets('avant le match : les séries des deux équipes et des face-à-face', (t) async {
    await monter(t, match(MatchStatus.upcoming));
    expect(find.text('Séries'), findsOneWidget);
    expect(find.text('Sans victoire'), findsOneWidget);
    expect(find.text('Victoires de suite'), findsOneWidget);
    expect(find.text('6'), findsOneWidget);
    expect(find.text('Plus de 2,5 buts'), findsNWidgets(2), reason: 'Bayern 9/10, face-à-face 4/4');
    expect(find.text('Face-à-face'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('après le match : plus de séries', (t) async {
    await monter(t, match(MatchStatus.finished));
    expect(find.text('Séries'), findsNothing);
  });

  testWidgets('texte agrandi ×2 : rien ne déborde', (t) async {
    await monter(t, match(MatchStatus.live), echelle: 2);
    expect(t.takeException(), isNull);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pronowin/core/theme/app_theme.dart';
import 'package:pronowin/features/pronostics/domain/classement_direct.dart';
import 'package:pronowin/features/pronostics/domain/entities/match_entity.dart';
import 'package:pronowin/features/pronostics/presentation/pages/match_detail_page.dart';
import 'package:pronowin/features/pronostics/presentation/providers/pronostics_provider.dart';

/// Le classement en direct (15 novembre 2026) : les matchs en cours comptés au
/// score du moment, calculé sur le téléphone — aucun appel de plus au
/// fournisseur.
void main() {
  String logo(int id) => 'https://media.api-sports.io/football/teams/$id.png';

  StandingRow ligne(int rang, String nom, int id, int pts, int diff, {String? zone, String? nature}) => StandingRow(
    rank: rang, teamName: nom, teamId: id, teamLogo: logo(id),
    played: 10, win: pts ~/ 3, draw: pts % 3, lose: 10 - pts ~/ 3 - pts % 3,
    goalsDiff: diff, points: pts, zone: zone, zoneNature: nature);

  // Arsenal 1er (25), Chelsea 2e (23), Liverpool 3e (22), Everton 4e (10).
  final classement = [
    ligne(1, 'Arsenal', 42, 25, 12, zone: 'Champions League', nature: 'c1'),
    ligne(2, 'Chelsea', 49, 23, 8, zone: 'Champions League', nature: 'c1'),
    ligne(3, 'Liverpool', 40, 22, 9),
    ligne(4, 'Everton', 45, 10, -6, zone: 'Relegation', nature: 'relegation'),
  ];

  MatchEntity match(String dom, int idDom, String ext, int idExt, int bDom, int bExt,
      {MatchStatus statut = MatchStatus.live, bool avecLogo = true}) => MatchEntity(
    id: '$idDom-$idExt', league: 'Premier League', leagueCountry: 'PL',
    homeTeam: dom, awayTeam: ext,
    homeTeamLogo: avecLogo ? logo(idDom) : null, awayTeamLogo: avecLogo ? logo(idExt) : null,
    matchDate: DateTime.now(), status: statut, homeScore: bDom, awayScore: bExt, elapsed: 60,
    predictionType: PredictionType.win1, predictionLabel: '',
    oddsRecommended: 0, oddsHome: 0, oddsDraw: 0, oddsAway: 0,
    confidenceScore: 0, isPremium: false, homeFormPoints: 0, awayFormPoints: 0);

  test('sans match en cours entre deux équipes du groupe : le classement officiel suffit', () {
    expect(classementEnDirect(classement, const []), isNull);
    expect(classementEnDirect(classement, [match('Arsenal', 42, 'Chelsea', 49, 1, 0, statut: MatchStatus.finished)]), isNull);
    // Une équipe hors du groupe (coupe, autre poule) : rien ne bouge.
    expect(classementEnDirect(classement, [match('Arsenal', 42, 'Real Madrid', 541, 2, 0)]), isNull);
  });

  test('chacun au score du moment : points, matchs joués, différence de buts, et le rang qui suit', () {
    // Liverpool mène Chelsea 2-1 ; Everton et Arsenal font nul.
    final direct = classementEnDirect(classement, [
      match('Liverpool', 40, 'Chelsea', 49, 2, 1),
      match('Everton', 45, 'Arsenal', 42, 0, 0),
    ])!;
    expect([for (final l in direct) l.row.teamName], ['Arsenal', 'Liverpool', 'Chelsea', 'Everton']);
    expect([for (final l in direct) l.row.rank], [1, 2, 3, 4]);
    final liverpool = direct[1];
    expect(liverpool.row.points, 25);
    expect(liverpool.row.played, 11);
    expect(liverpool.row.goalsDiff, 10);
    expect(liverpool.row.win, classement[2].win + 1);
    expect(liverpool.mouvement, 1);
    expect(liverpool.enJeu, (pour: 2, contre: 1));
    expect(direct[2].mouvement, -1);
    expect(direct[2].enJeu, (pour: 1, contre: 2));
    expect(direct[0].row.points, 26);
    expect(direct[0].row.draw, classement[0].draw + 1);
    // La zone reste attachée à la place : la 2ᵉ qualifie, quelle que soit
    // l'équipe qui l'occupe.
    expect(direct[1].row.zoneNature, 'c1');
    expect(direct[2].row.zoneNature, isNull);
    expect(direct[3].row.zoneNature, 'relegation');
  });

  test('égalité de points : la différence de buts, puis l\'ordre officiel', () {
    // Chelsea (23, +8) bat Everton 1-0 → 26, +9 ; Arsenal perd → 25.
    final direct = classementEnDirect(classement, [match('Chelsea', 49, 'Everton', 45, 1, 0)])!;
    expect(direct.first.row.teamName, 'Chelsea');
    // Sans logo, l'équipe se reconnaît à son nom.
    final parNom = classementEnDirect(classement, [match('Chelsea', 1, 'Everton', 2, 1, 0, avecLogo: false)])!;
    expect(parNom.first.row.teamName, 'Chelsea');
  });

  testWidgets('pendant les matchs, le classement s\'ouvre en direct ; le général reste à un geste', (t) async {
    await t.pumpWidget(MaterialApp(theme: AppTheme.dark, home: Scaffold(body: SingleChildScrollView(
      child: classementDeCompetition(classement, direct: [match('Liverpool', 40, 'Chelsea', 49, 2, 1)])))));
    await t.pump();
    final chip = t.widget<ChoiceChip>(find.byKey(const Key('classement-direct')));
    expect(chip.selected, isTrue);
    expect(find.byKey(const Key('classement-direct-note')), findsOneWidget);
    expect(find.text('2-1'), findsOneWidget);
    expect(find.text('1-2'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_drop_up_rounded), findsOneWidget);
    expect(find.byIcon(Icons.arrow_drop_down_rounded), findsOneWidget);

    await t.tap(find.byKey(const Key('classement-general')));
    await t.pump();
    expect(find.byKey(const Key('classement-direct-note')), findsNothing);
    expect(find.text('2-1'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('sans match en cours, rien ne change', (t) async {
    await t.pumpWidget(MaterialApp(theme: AppTheme.dark, home: Scaffold(body: SingleChildScrollView(
      child: classementDeCompetition(classement)))));
    await t.pump();
    expect(find.byKey(const Key('classement-direct')), findsNothing);
    expect(find.byKey(const Key('classement-direct-note')), findsNothing);
    expect(find.byIcon(Icons.arrow_drop_up_rounded), findsNothing);
    expect(find.text('Chelsea'), findsOneWidget);
  });
}

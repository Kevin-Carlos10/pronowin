import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:pronowin/core/theme/app_theme.dart';
import 'package:pronowin/features/pronostics/domain/entities/match_entity.dart';
import 'package:pronowin/features/pronostics/presentation/widgets/match_card_widget.dart';

import 'aides/banc_ecran.dart';

/// Toute fiche de match est consultable, pronostic ou non (demande de
/// l'utilisateur du 18 octobre 2026) : seuls les matchs terminés sans
/// pronostic s'ouvraient, un match à venir ou en direct restait muet.
void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR');
    await preparerBanc();
  });

  MatchEntity sansProno(MatchStatus statut) => MatchEntity(
        id: 'm-$statut', league: 'Premier League', leagueCountry: 'GB',
        homeTeam: 'Brentford', awayTeam: 'Liverpool',
        matchDate: DateTime.now().add(const Duration(hours: 3)),
        status: statut,
        predictionType: PredictionType.win1,
        predictionLabel: '',
        oddsRecommended: 0, oddsHome: 0, oddsDraw: 0, oddsAway: 0,
        confidenceScore: 0,
        isPremium: false, homeFormPoints: 0, awayFormPoints: 0,
        hasPronostic: false,
      );

  for (final statut in [MatchStatus.upcoming, MatchStatus.live, MatchStatus.finished]) {
    testWidgets('match ${statut.name} sans pronostic : la carte ouvre sa fiche', (t) async {
      final match = sansProno(statut);
      await t.pumpWidget(ProviderScope(
        overrides: donneesCommunes(),
        child: MaterialApp.router(
          theme: AppTheme.dark,
          routerConfig: GoRouter(routes: [
            GoRoute(path: '/', builder: (_, _) => Scaffold(body: SingleChildScrollView(
              child: MatchCardWidget(match: match)))),
            GoRoute(path: '/pronostics/:id', builder: (_, etat) =>
              Scaffold(body: Text('FICHE ${etat.pathParameters['id']}'))),
          ]),
        ),
      ));
      await t.pump();
      await t.tap(find.byType(MatchCardWidget));
      await t.pumpAndSettle();
      expect(find.text('FICHE m-$statut'), findsOneWidget);
    });
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:pronowin/core/theme/app_theme.dart';
import 'package:pronowin/features/pronostics/domain/entities/match_entity.dart';
import 'package:pronowin/features/pronostics/presentation/widgets/match_card_widget.dart';

import 'aides/banc_ecran.dart';

/// Sur la page Pronos, le pronostic se lit en entier.
///
/// Signalé le 2 octobre 2026 : « Total buts do… », « Double chan… ». Le
/// libellé n'avait qu'une ligne, et la rangée le partageait à parts égales
/// avec l'indice de confiance, qui n'occupait qu'une partie de sa moitié.
void main() {
  // La vraie police : celle du banc de test dessine chaque lettre en carré,
  // bien plus large que Roboto — une troncature mesurée avec elle ne vaut rien.
  setUpAll(() async {
    await initializeDateFormatting('fr_FR');
    await preparerBanc();
  });

  MatchEntity match(String libelle) => MatchEntity(
        id: 'm1', league: 'UEFA Nations League', leagueCountry: 'EU',
        homeTeam: 'Faroe Islands', awayTeam: 'Slovakia',
        matchDate: DateTime(2026, 10, 2, 18, 45),
        status: MatchStatus.upcoming,
        predictionType: PredictionType.win1,
        predictionLabel: libelle,
        oddsRecommended: 1.81, oddsHome: 6.68, oddsDraw: 4.10, oddsAway: 1.57,
        confidenceScore: 5, confidencePct: 83,
        isPremium: false, homeFormPoints: 5, awayFormPoints: 9,
        hasPronostic: true,
      );

  // Des libellés publiés, tels que le panneau les compose.
  const libelles = [
    'Total buts domicile : Plus de 0.5',
    'Double chance : Domicile ou Nul',
    'Au moins une équipe marquer : 1,5',
    'Les deux équipes marquent : Oui',
  ];

  for (final largeur in [360.0, 390.0, 411.0]) {
    for (final libelle in libelles) {
      testWidgets('« $libelle » en entier à ${largeur.toInt()} px', (tester) async {
        tester.view.physicalSize = Size(largeur, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(ProviderScope(
          child: MaterialApp(
            theme: AppTheme.dark,
            home: Scaffold(body: SingleChildScrollView(
              child: MatchCardWidget(match: match(libelle)))),
          ),
        ));
        await tester.pump();

        expect(tester.takeException(), isNull);
        // « Domicile » devient le nom de l'équipe : on cherche ce qui s'affiche.
        final affiche = match(libelle).displayPredictionLabel;
        final paragraphe = tester.renderObject<RenderParagraph>(find.text(affiche));
        expect(paragraphe.didExceedMaxLines, isFalse,
            reason: 'le libellé est coupé par « … »');
      });
    }
  }
}

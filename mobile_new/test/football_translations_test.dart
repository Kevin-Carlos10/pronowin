import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/l10n/football_labels.dart';
import 'package:pronowin/l10n/app_strings.dart';
import 'package:pronowin/features/pronostics/data/models/match_model.dart';
import 'package:pronowin/features/pronostics/presentation/providers/pronostics_provider.dart';

void main() {
  final cases =
      jsonDecode(
            File(
              '../backend/src/__tests__/fixtures/football-translations.json',
            ).readAsStringSync(),
          )
          as List;
  tearDown(() => AppStrings.setCurrentLanguage('fr'));
  for (final c in cases) {
    for (final language in ['fr', 'en']) {
      test('${c['method']}: ${c['input']} → $language', () {
        final String input = c['input'];
        final Object result = switch (c['method']) {
          'market' => FootballLabels.market(input, language: language),
          'selection' => FootballLabels.selection(input, language: language),
          'prediction' => FootballLabels.prediction(input, language: language),
          'round' => FootballLabels.round(input, language: language),
          'absence' => FootballLabels.absence(input, language: language),
          'transfer' => FootballLabels.transfer(input, language: language),
          _ => FootballLabels.country(input, language: language),
        };
        expect(result is FootballLabel ? result.text : result, c[language]);
        if (result is FootballLabel) expect(result.known, c['known']);
      });
    }
  }
  test(
    'a cached match and live odds follow a language switch without refetching',
    () {
      final match = MatchModel.fromJson({
        'id': '1',
        'league': 'League',
        'home_team': 'Netherlands',
        'away_team': 'Belgium',
        'match_date': '2026-10-06T12:00:00Z',
        'prediction_label': 'Double Chance : Home or Draw',
        'prediction_type': 'other',
        'odds_recommended': 1.8,
      });
      const live = LiveOddValue(value: 'Over', odd: 1.9, ligne: '2.5');
      AppStrings.setCurrentLanguage('fr');
      expect(match.homeTeam, 'Pays-Bas');
      expect(match.toJson()['home_team'], 'Netherlands');
      expect(match.displayPredictionLabel, 'Double chance : Pays-Bas ou Nul');
      expect(live.libelle, 'Plus de 2,5');
      AppStrings.setCurrentLanguage('en');
      expect(match.homeTeam, 'Netherlands');
      expect(
        match.displayPredictionLabel,
        'Double Chance : Netherlands or Draw',
      );
      expect(live.libelle, 'Over 2.5');
      expect(live.odd, 1.9);
      expect(live.ligne, '2.5');
      expect(match.oddsRecommended, 1.8);
      expect(match.predictionLabel, 'Double Chance : Home or Draw');
    },
  );
  test(
    'player names stay intact, actual team names follow the selected language',
    () {
      expect(
        FootballLabels.selection(
          'Jordan Henderson',
          home: 'Jordan',
          away: 'Belgium',
        ).text,
        'Jordan Henderson',
      );
      expect(
        FootballLabels.selection(
          'Home -0.5',
          home: 'Netherlands',
          away: 'Belgium',
        ).text,
        'Pays-Bas -0,5',
      );
    },
  );
}

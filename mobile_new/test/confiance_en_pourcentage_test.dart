import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/features/pronostics/data/models/match_model.dart';
import 'package:pronowin/features/pronostics/domain/entities/match_entity.dart';
import 'package:pronowin/shared/widgets/confidence_indicator.dart';

import 'aides/code_seul.dart';

/// L'indice de confiance s'affiche en pourcentage — celui que l'analyste
/// saisit (décision du 1er octobre 2026).
///
/// ── L'historique, pour ne pas le refaire ─────────────────────────────────
///
/// En août, l'application convertissait la note 1–5 par une table fixe
/// (60, 70, 80, 90, 95 %) : une note « très faible » s'affichait 60 %, et
/// 95 % se lisait comme une victoire presque certaine. Le 22 septembre, la
/// confiance est redevenue une note sur cinq. Aujourd'hui, le pourcentage
/// revient, mais **saisi par l'analyste**, borné à 1–99 par le serveur, et
/// présenté comme son appréciation, pas comme une probabilité de gain.
void main() {
  group('l\'indice saisi s\'affiche tel quel', () {
    testWidgets('73 % — et son niveau en toutes lettres', (t) async {
      await t.pumpWidget(const MaterialApp(home: Scaffold(body: ConfidenceIndicator(pourcentage: 73))));
      expect(find.text('73 %'), findsOneWidget);
      expect(find.text(MatchEntity.labelForConfidence(4)), findsOneWidget);
      expect(find.textContaining('/5'), findsNothing);
    });

    testWidgets('un indice absent ne devient pas une confiance inventée', (t) async {
      await t.pumpWidget(const MaterialApp(home: Scaffold(body: ConfidenceIndicator(pourcentage: 0, showLabel: false))));
      expect(find.text('Non évaluée'), findsOneWidget);
    });

    testWidgets('le libellé peut être masqué, pas l\'indice', (t) async {
      await t.pumpWidget(const MaterialApp(home: Scaffold(body: ConfidenceIndicator(pourcentage: 73, showLabel: false))));
      expect(find.text('73 %'), findsOneWidget);
      expect(find.text(MatchEntity.labelForConfidence(4)), findsNothing);
    });

    testWidgets('l\'infobulle dit ce que ce n\'est pas', (t) async {
      await t.pumpWidget(const MaterialApp(home: Scaffold(body: ConfidenceIndicator(pourcentage: 73))));
      final bulle = t.widget<Tooltip>(find.byType(Tooltip));
      expect(bulle.message, contains('pas une probabilité de gain'));
    });
  });

  group('le serveur envoie le pourcentage', () {
    Map<String, dynamic> api({int? pct, int score = 4}) => {
          'id': 'm1', 'league': 'Ligue 1', 'league_country': 'France',
          'home_team': 'Lyon', 'away_team': 'Lens',
          'match_date': '2026-10-04T19:00:00Z', 'status': 'upcoming',
          'prediction_type': 'win1', 'prediction_label': 'Domicile',
          'odds_recommended': 1.8, 'odds_home': 1.8, 'odds_draw': 3.4, 'odds_away': 4.2,
          'confidence_score': score, 'confidence_pct': ?pct,
          'is_premium': false, 'home_form_points': 9, 'away_form_points': 7,
        };

    test('c\'est lui qu\'on affiche', () {
      expect(MatchModel.fromJson(api(pct: 73)).pourcentageConfiance, 73);
      expect(MatchEntity.pourcentageDepuisApi(api(pct: 73)), 73);
    });

    test('un serveur ancien n\'envoie que le niveau : le milieu de son palier', () {
      // Le même repli que le serveur pour les pronostics antérieurs à la
      // saisie : 1 → 10 … 5 → 90. Jamais la table flatteuse d'août.
      expect([1, 2, 3, 4, 5].map((n) => MatchModel.fromJson(api(score: n)).pourcentageConfiance),
          [10, 30, 50, 70, 90]);
    });

    test('les paliers du niveau sont ceux du serveur', () {
      expect([1, 19, 20, 39, 40, 59, 60, 79, 80, 99].map(MatchEntity.niveauDepuisPourcentage),
          [1, 1, 2, 2, 3, 3, 4, 4, 5, 5]);
    });
  });

  test('plus aucun écran n\'écrit « n/5 »', () {
    final fautes = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final code = f.readAsStringSync().pipeCodeSeul();
      if (RegExp(r'''/5['"]''').hasMatch(code) || code.contains('sur 5')) fautes.add(f.path);
    }
    expect(fautes, isEmpty);
  });
}

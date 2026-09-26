import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/shared/widgets/confidence_indicator.dart';
import 'package:pronowin/features/pronostics/domain/entities/match_entity.dart';

void main() {
  for(final score in [1,2,3,4,5]) {
    testWidgets('la confiance reste une note $score/5', (tester) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: ConfidenceIndicator(score: score))));
      expect(find.text('$score/5'), findsOneWidget);
      expect(find.text(MatchEntity.labelForConfidence(score)), findsOneWidget);
      expect(find.textContaining('%'), findsNothing);
    });
  }
  testWidgets('un score absent ne devient pas une confiance inventée', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: ConfidenceIndicator(score: 0,showLabel:false))));
    expect(find.text('Non évaluée'), findsOneWidget);
  });
  testWidgets('le libellé peut être masqué, pas la note', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: ConfidenceIndicator(score: 4,showLabel:false))));
    expect(find.text('4/5'), findsOneWidget);
    expect(find.text(MatchEntity.labelForConfidence(4)), findsNothing);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/core/theme/app_theme.dart';
import 'package:pronowin/features/bankroll/presentation/providers/bankroll_provider.dart';
import 'package:pronowin/features/bankroll/presentation/widgets/miser_dialog.dart';

void main() {
  for (final stake in [300.0, 0.0]) {
    testWidgets('barème obligatoire, montant $stake, écran étroit', (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(ProviderScope(overrides: [
        suggestedStakeProvider('p1').overrideWith((ref) async => {
          'suggested_amount': stake, 'current_balance': stake == 0 ? 20 : 10000,
          'currency': 'XOF', 'confidence_score': 3, 'stake_percent': 3.0,
        }),
      ], child: MaterialApp(theme: AppTheme.dark, home: Consumer(builder: (context, ref, _) => Scaffold(
        body: TextButton(onPressed: () => showMiserDialog(context, ref: ref, pronosticId: 'p1',
          homeTeam: 'Paris', awayTeam: 'Marseille', predictionLabel: 'Paris gagne',
          confidenceScore: 5, oddsRecommended: 1.8), child: const Text('Ouvrir')),
      )))));
      await tester.tap(find.text('Ouvrir'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('3/5'), findsOneWidget); // la note actualisée du serveur
      expect(find.text('3 % du solde'), findsOneWidget);
      expect(find.byType(TextField), findsNothing); // aucun pourcentage personnel
      final button = tester.widget<GestureDetector>(find.ancestor(
        of: find.text('Confirmer la mise'), matching: find.byType(GestureDetector)).first);
      expect(button.onTap == null, stake == 0);
    });
  }
}

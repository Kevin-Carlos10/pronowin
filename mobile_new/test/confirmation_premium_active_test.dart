import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pronowin/features/abonnement/presentation/widgets/confirmation_premium_active.dart';
import 'package:pronowin/l10n/catalog_en.dart';

/// Après un achat sur l'App Store, le Premium est actif : l'écran le dit.
///
/// L'achat intégré réutilisait la confirmation du Mobile Money — « Preuve
/// soumise ! », « Activation sous immédiate », « Compris, j'attends la
/// validation » — constaté sur iPhone le 1er octobre 2026, alors que le
/// serveur venait d'activer le Premium.
void main() {
  testWidgets('la confirmation annonce un Premium actif, et jusqu\'à quand', (tester) async {
    var continue_ = false;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ConfirmationPremiumActive(
      expireLe: DateTime(2026, 11, 1, 9, 30),
      onContinuer: () => continue_ = true,
    ))));

    expect(find.text('Premium activé !'), findsOneWidget);
    expect(find.textContaining('renouvelé automatiquement'), findsOneWidget);
    expect(find.textContaining('Preuve soumise'), findsNothing);
    expect(find.textContaining('attends'), findsNothing);

    await tester.tap(find.text('Découvrir le Premium'));
    expect(continue_, isTrue);
  });

  test('l\'achat intégré n\'ouvre plus la confirmation du Mobile Money', () {
    final source = File('lib/features/abonnement/presentation/pages/activer_premium_page.dart')
        .readAsStringSync();
    final branche = RegExp(r'case IapSuccess\(.*?case IapCancelled', dotAll: true)
        .firstMatch(source)!.group(0)!;
    expect(branche, contains('ConfirmationPremiumActive('));
    expect(branche, isNot(contains('_showSuccessDialog(')));
  });

  test('la confirmation est traduite', () {
    for (final cle in [
      'Premium activé !',
      'Découvrir le Premium',
      "Actif jusqu'au {arg0}, renouvelé automatiquement. Résiliable à tout moment depuis les réglages de ton compte store.",
    ]) {
      expect(englishMessages, contains(cle), reason: cle);
    }
  });
}

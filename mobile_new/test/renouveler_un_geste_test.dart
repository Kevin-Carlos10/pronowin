import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/core/config/distribution_channel.dart';
import 'package:pronowin/features/abonnement/data/iap_service.dart';
import 'package:pronowin/features/abonnement/presentation/pages/activer_premium_page.dart';
import 'package:pronowin/features/abonnement/presentation/providers/iap_provider.dart';
import 'package:pronowin/features/abonnement/presentation/providers/subscription_provider.dart';

/// Renouveler en un geste (23 novembre 2026) : le rappel d'échéance porte la
/// formule de l'abonné, et l'écran s'ouvre sur son paiement — plus sur
/// l'offre, où il fallait tout rechoisir.
void main() {
  Future<void> monter(WidgetTester t, {required TargetPlatform plateforme, required bool store,
      String? renouveler}) async {
    debugDefaultTargetPlatformOverride = plateforme;
    t.view.physicalSize = const Size(390 * 2, 2400 * 2);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(
      overrides: [
        currentSubscriptionProvider.overrideWith((ref) async => <String, dynamic>{
          'plan': 'premium', 'paiement_geniuspay': true,
          'premium_price_monthly_fcfa': 6000, 'premium_price_annual_fcfa': 54000,
        }),
        isStoreBuildProvider.overrideWithValue(store),
        iapReadyProvider.overrideWith((ref) async => true),
        iapProductsProvider.overrideWithValue(const []),
        iapServiceProvider.overrideWithValue(IapService(Dio())),
        submitProofProvider.overrideWith((ref) => SubmitProofNotifier(Dio())),
      ],
      child: MaterialApp(home: ActiverPremiumPage(renouveler: renouveler)),
    ));
    await t.pump();
    t.takeException(); // filet « profil incomplet » : dépendances Firebase absentes
    await t.pump(const Duration(milliseconds: 600));
  }

  tearDown(() => debugDefaultTargetPlatformOverride = null);

  for (final (nom, store) in [('APK', false), ('Google Play', true)]) {
    testWidgets('$nom : le rappel de l\'annuel ouvre son paiement, d\'un geste', (t) async {
      await monter(t, plateforme: TargetPlatform.android, store: store, renouveler: 'premium_annual');
      expect(find.text('Paiement Mobile'), findsOneWidget);
      expect(find.textContaining(RegExp(r'Payer 54\D?000 FCFA')), findsOneWidget);
      // L'offre n'est pas repassée.
      expect(find.text("Passer à l'annuel"), findsNothing);
      debugDefaultTargetPlatformOverride = null;
    });
  }

  testWidgets('sans formule, l\'offre comme avant', (t) async {
    await monter(t, plateforme: TargetPlatform.android, store: false);
    expect(find.text('Paiement Mobile'), findsNothing);
    expect(find.text('Passer au mensuel'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('iPhone : l\'offre, jamais de paiement hors App Store', (t) async {
    await monter(t, plateforme: TargetPlatform.iOS, store: true, renouveler: 'premium_annual');
    expect(find.text('Paiement Mobile'), findsNothing);
    expect(find.textContaining('FCFA'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });
}

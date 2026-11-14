import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pronowin/core/config/distribution_channel.dart';
import 'package:pronowin/features/auth/domain/entities/user_entity.dart';
import 'package:pronowin/shared/utils/premium_nav.dart';
import 'aides/banc_ecran.dart';

/// Refus Apple du 2 novembre 2026 : le relecteur, venu tester l'abonnement,
/// est tombé sur « Compléter le profil ». Sur l'App Store et Google Play, le
/// paywall s'ouvre directement ; l'APK direct (Mobile Money) garde l'étape.
void main() {
  setUpAll(() async => preparerBanc());

  // Inscrit par e-mail : ni nom, ni date de naissance, ni téléphone.
  final incomplet = UserEntity(
    id: 'u2',
    pseudo: 'Parieur_A1B2C',
    countryCode: 'BF',
    subscriptionPlan: SubscriptionPlan.free,
    referralCode: 'A1B2C3',
    referralEarnings: 0,
    createdAt: DateTime(2026, 11, 2),
  );

  Future<void> ouvrir(WidgetTester t, {required bool store}) async {
    SharedPreferences.setMockInitialValues({});
    final routeur = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, _) => Consumer(builder: (context, ref, _) => Scaffold(
        body: TextButton(onPressed: () => goToPremium(context, ref), child: const Text('Get Premium'))))),
      GoRoute(path: '/compte/activer-premium', builder: (_, _) => const Text('paywall')),
      GoRoute(path: '/compte/completer-profil', builder: (_, _) => const Text('profil')),
    ]);
    await t.pumpWidget(ProviderScope(
      overrides: [...donneesCommunes(utilisateur: incomplet), isStoreBuildProvider.overrideWithValue(store)],
      child: MaterialApp.router(routerConfig: routeur),
    ));
    await t.tap(find.text('Get Premium'));
    await t.pumpAndSettle();
  }

  testWidgets('App Store et Google Play : le paywall, sans « Compléter le profil »', (t) async {
    await ouvrir(t, store: true);
    expect(find.text('paywall'), findsOneWidget);
    expect(find.text('profil'), findsNothing);
  });

  testWidgets('APK direct (Mobile Money) : le profil d\'abord, comme avant', (t) async {
    await ouvrir(t, store: false);
    expect(find.text('profil'), findsOneWidget);
  });
}

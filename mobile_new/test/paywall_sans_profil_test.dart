import 'package:flutter/foundation.dart';
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
/// est tombé sur « Compléter le profil ». Sur l'App Store, le paywall s'ouvre
/// directement. Le paiement Mobile Money, lui, demande nom et téléphone (le
/// serveur l'exige) : l'APK direct et, depuis le 23 novembre 2026, Google
/// Play gardent l'étape.
void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

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

  testWidgets('App Store : le paywall, sans « Compléter le profil »', (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await ouvrir(t, store: true);
    expect(find.text('paywall'), findsOneWidget);
    expect(find.text('profil'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Google Play (Mobile Money) : le profil d\'abord, comme l\'APK', (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await ouvrir(t, store: true);
    expect(find.text('profil'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('APK direct (Mobile Money) : le profil d\'abord, comme avant', (t) async {
    await ouvrir(t, store: false);
    expect(find.text('profil'), findsOneWidget);
  });
}

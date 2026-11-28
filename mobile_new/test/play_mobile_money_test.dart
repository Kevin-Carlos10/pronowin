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

/// Google Play paie par Mobile Money (23 novembre 2026), comme l'APK direct.
///
/// Aucun compte marchand Google n'est possible depuis le Burkina Faso : la
/// Play Console n'a rien à vendre. Depuis le 26 octobre, la version Play
/// renvoyait vers le paiement du site ; sur décision expresse de
/// l'utilisateur, risque accepté (Google exige sa facturation pour un
/// abonnement), le paiement Mobile Money est désormais dans l'application.
/// Sans le parcours « code promo » 1xBet, réservé à l'APK. Jamais sur iPhone.
void main() {
  Future<void> monter(WidgetTester t, {required TargetPlatform plateforme, bool store = true}) async {
    debugDefaultTargetPlatformOverride = plateforme;
    // Écran haut : la page est une liste, construite au fil du défilement.
    t.view.physicalSize = const Size(390 * 2, 2400 * 2);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(
      overrides: [
        currentSubscriptionProvider.overrideWith((ref) async => <String, dynamic>{'plan': 'free'}),
        isStoreBuildProvider.overrideWithValue(store),
        // Catalogue du store lu, mais vide.
        iapReadyProvider.overrideWith((ref) async => true),
        iapProductsProvider.overrideWithValue(const []),
        // Le vrai passe par le client HTTP de l'app, donc par Firebase.
        iapServiceProvider.overrideWithValue(IapService(Dio())),
        submitProofProvider.overrideWith((ref) => SubmitProofNotifier(Dio())),
      ],
      child: const MaterialApp(home: ActiverPremiumPage()),
    ));
    await t.pump();
    t.takeException(); // filet « profil incomplet » : dépendances Firebase absentes
    await t.pump(const Duration(milliseconds: 600));
  }

  tearDown(() => debugDefaultTargetPlatformOverride = null);

  testWidgets('Google Play : le paiement Mobile Money dans l\'app, sans code promo ni achat intégré', (t) async {
    await monter(t, plateforme: TargetPlatform.android);
    expect(find.text('Paiement Direct'), findsOneWidget);
    expect(find.text('Avec Code Promo'), findsNothing);
    // Ni l'ancien renvoi vers le site, ni la section d'achat intégré.
    expect(find.byKey(const Key('iap-indisponible-play')), findsNothing);
    expect(find.byKey(const Key('play-payer-site')), findsNothing);
    expect(find.byKey(const Key('iap-reessayer')), findsNothing);
    // La FAQ du paiement direct, sans ses questions sur le code promo.
    expect(find.text('Comment se passe le paiement ?'), findsOneWidget);
    expect(find.textContaining('Code Promo'), findsNothing);
    // Le formulaire : un seul onglet, sans « Code Promo ».
    await t.tap(find.text('Passer au mensuel'));
    await t.pump(const Duration(milliseconds: 600));
    expect(find.byType(TabBar), findsNothing);
    expect(find.text('Paiement Mobile'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('APK direct : le paiement direct et le code promo, comme avant', (t) async {
    await monter(t, plateforme: TargetPlatform.android, store: false);
    expect(find.text('Paiement Direct'), findsOneWidget);
    expect(find.text('Avec Code Promo'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('iPhone : l\'achat intégré seul — jamais de paiement hors App Store', (t) async {
    await monter(t, plateforme: TargetPlatform.iOS);
    expect(find.byKey(const Key('iap-reessayer')), findsOneWidget);
    // Règle 3.1.1 d'Apple : aucun autre moyen de paiement, aucun renvoi au site.
    expect(find.text('Paiement Direct'), findsNothing);
    expect(find.textContaining('Mobile Money'), findsNothing);
    expect(find.textContaining('GeniusPay'), findsNothing);
    expect(find.textContaining('Google Play'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });
}

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

/// Version Google Play sans abonnement en vente (18 octobre 2026) : aucun
/// compte marchand Google n'est possible depuis le Burkina Faso, le catalogue
/// est vide. L'écran disait « vérifie ta connexion, puis réessaie » — ce qui
/// ne changeait rien — et les accroches annonçaient un prix.
///
/// Depuis le 26 octobre 2026, sur décision expresse de l'utilisateur (risque
/// accepté : Google interdit d'indiquer un autre moyen de paiement), l'app
/// Google Play propose le paiement Mobile Money sur le site. Jamais l'iPhone.
void main() {
  Future<void> monter(WidgetTester t, {required TargetPlatform plateforme}) async {
    debugDefaultTargetPlatformOverride = plateforme;
    // Écran haut : la page est une liste, construite au fil du défilement.
    t.view.physicalSize = const Size(390 * 2, 2400 * 2);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(
      overrides: [
        currentSubscriptionProvider.overrideWith((ref) async => <String, dynamic>{'plan': 'free'}),
        isStoreBuildProvider.overrideWithValue(true),
        // Catalogue du store lu, mais vide : aucun abonnement en vente.
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

  testWidgets('Android (Google Play) : le message, et le paiement Mobile Money sur le site ; ni « réessayer », ni FAQ', (t) async {
    await monter(t, plateforme: TargetPlatform.android);
    expect(find.byKey(const Key('iap-indisponible-play')), findsOneWidget);
    expect(find.text("L'abonnement Premium n'est pas encore proposé dans la version Google Play."), findsOneWidget);
    expect(find.byKey(const Key('play-payer-site')), findsOneWidget);
    expect(find.text('Payer par Mobile Money sur le site'), findsOneWidget);
    expect(find.byKey(const Key('iap-reessayer')), findsNothing);
    expect(find.textContaining('Vérifie ta connexion'), findsNothing);
    expect(find.text('Comment se passe le paiement ?'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('iPhone : le message d\'origine, avec « réessayer » — jamais de paiement hors App Store', (t) async {
    await monter(t, plateforme: TargetPlatform.iOS);
    expect(find.byKey(const Key('iap-indisponible-play')), findsNothing);
    expect(find.byKey(const Key('iap-reessayer')), findsOneWidget);
    // Règle 3.1.1 d'Apple : aucun autre moyen de paiement, aucun renvoi au site.
    expect(find.byKey(const Key('play-payer-site')), findsNothing);
    expect(find.textContaining('Mobile Money'), findsNothing);
    expect(find.textContaining('GeniusPay'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });
}

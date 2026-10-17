import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pronowin/core/theme/app_theme.dart';
import 'package:pronowin/features/abonnement/data/iap_service.dart';
import 'package:pronowin/features/abonnement/presentation/providers/subscription_provider.dart';
import 'package:pronowin/features/bankroll/presentation/providers/bankroll_provider.dart';
import 'package:pronowin/features/compte/presentation/pages/compte_page.dart';
import 'package:pronowin/features/compte/presentation/providers/compte_provider.dart';
import 'package:pronowin/features/parrainage/presentation/providers/referral_provider.dart';
import 'package:pronowin/l10n/catalog_en.dart';

/// Un abonné des stores trouve dans l'app où gérer son abonnement.
///
/// La page de gestion existait dans le code, mais aucun bouton n'y menait :
/// pour résilier ou changer de formule, il fallait trouver seul le chemin dans
/// les réglages du téléphone (2 octobre 2026). Et le bandeau « Renouveler »
/// envoyait un abonné Apple vers l'écran d'achat, où Apple répond « Vous êtes
/// déjà abonné ».
void main() {
  group('la page de gestion suit le store de l\'abonnement', () {
    test('Apple', () {
      expect(pageGestionAbonnement('apple').toString(),
          'https://apps.apple.com/account/subscriptions');
    });

    test('Google, avec le produit et le paquet', () {
      final u = pageGestionAbonnement('google', produit: 'com.pronowin.premium.annual')!;
      expect(u.host, 'play.google.com');
      expect(u.path, '/store/account/subscriptions');
      expect(u.queryParameters, {'sku': 'com.pronowin.premium.annual', 'package': 'com.pronowin.app'});
    });

    test('hors des stores, rien à gérer chez eux', () {
      // Un Premium payé par Mobile Money ne se résilie ni chez Apple ni chez
      // Google.
      expect(pageGestionAbonnement(null), isNull);
      expect(pageGestionAbonnement('manual_mobcash'), isNull);
    });
  });

  Widget compte(Map<String, dynamic> abonnement) => ProviderScope(
        overrides: [
          profileProvider.overrideWith((ref) async => {
                'pseudo': 'Parieur_G6OEQ', 'phone_number': '+22660012181',
                'email': 'a@b.co', 'country_code': 'BF',
                'first_name': 'Kevin', 'last_name': 'Carlos',
                'birth_date': '1999-01-22T00:00:00.000Z',
                'subscription_plan': 'premium',
                'created_at': '2026-10-02T00:00:00.000Z',
                'referral_code': 'ABC123', 'referral_earnings': 0,
              }),
          userStatsProvider.overrideWith((ref) async => <String, dynamic>{}),
          bankrollProvider.overrideWith((ref) async => null),
          currentSubscriptionProvider.overrideWith((ref) async => abonnement),
          referralStatsProvider.overrideWith((ref) async => <String, dynamic>{}),
        ],
        child: MaterialApp(theme: AppTheme.dark, home: const ComptePage()),
      );

  Future<void> ongletAbonnement(WidgetTester t, Map<String, dynamic> abonnement) async {
    t.view.physicalSize = const Size(390 * 3, 2400 * 3);
    t.view.devicePixelRatio = 3.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(compte(abonnement));
    // Pas de `pumpAndSettle` : la pastille Premium anime en boucle.
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 120));
    }
    await t.tap(find.text('Abonnement').first);
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 120));
    }
  }

  testWidgets('abonné Apple : « Gérer mon abonnement », pas « Renouveler »', (t) async {
    await ongletAbonnement(t, {
      'plan': 'premium', 'days_left': 12, 'expires_at': '2026-10-15T00:00:00.000Z',
      'store': 'apple', 'product_id': 'com.pronowin.premium.monthly',
    });
    expect(t.takeException(), isNull);
    expect(find.byKey(const Key('gerer-abonnement')), findsOneWidget);
    expect(find.textContaining("Renouvelé automatiquement par l'App Store"), findsOneWidget);
    expect(find.text('Renouveler'), findsNothing,
        reason: "l'écran d'achat répondrait « Vous êtes déjà abonné »");
    expect(find.textContaining('Échéance dans 12 jours'), findsOneWidget);
  });

  testWidgets('Premium payé par Mobile Money : le bandeau « Renouveler » reste', (t) async {
    await ongletAbonnement(t, {
      'plan': 'premium', 'days_left': 12, 'expires_at': '2026-10-15T00:00:00.000Z',
      'store': null, 'product_id': null,
    });
    expect(t.takeException(), isNull);
    expect(find.byKey(const Key('gerer-abonnement')), findsNothing);
    expect(find.text('Renouveler'), findsOneWidget);
    expect(find.textContaining('Expire dans 12 jours'), findsOneWidget);
  });

  testWidgets("au défilement, l'en-tête ne recouvre pas les onglets", (t) async {
    // Vidéo du 3 octobre 2026 : les pastilles « PREMIUM » et « 1 j restants »
    // passaient à travers la barre d'onglets, transparente, et masquaient
    // « Abonnement ».
    await ongletAbonnement(t, {
      'plan': 'premium', 'days_left': 1, 'store': 'apple', 'product_id': 'com.pronowin.premium.monthly',
    });
    final fond = t.widget<ColoredBox>(find.byKey(const Key('onglets-compte')));
    expect(fond.color.a, 1.0, reason: "la barre d'onglets doit être opaque");
    expect(find.descendant(of: find.byKey(const Key('onglets-compte')), matching: find.byType(TabBar)),
        findsOneWidget);
  });

  test("la suppression du compte nomme la boutique du téléphone", () {
    // L'iPhone affichait « fais-le depuis le Play Store ».
    final source = File('lib/features/parametres/presentation/pages/parametres_page.dart').readAsStringSync();
    final avertissement = RegExp(r'_DeleteWarning\(!widget\.ref.*?\)\),', dotAll: true).firstMatch(source)!.group(0)!;
    expect(avertissement, contains('Platform.isIOS'));
    expect(avertissement, contains("depuis l'App Store"));
    expect(englishMessages, contains(
        "Ton abonnement n'est pas résilié : fais-le depuis l'App Store (Réglages, puis ton nom, puis Abonnements)"));
  });

  test('les nouveaux textes sont traduits', () {
    for (final cle in [
      'Gérer mon abonnement',
      'Échéance dans {arg0} jour',
      'Échéance dans {arg0} jours',
      "Renouvelé automatiquement par l'App Store. Résiliable à tout moment, au moins 24 h avant l'échéance.",
      'Renouvelé automatiquement par Google Play. Résiliable à tout moment, au moins 24 h avant l\'échéance.',
      'Ouvre Réglages, puis ton nom, puis Abonnements.',
      'Ouvre Google Play, puis Paiements et abonnements, puis Abonnements.',
    ]) {
      expect(englishMessages, contains(cle), reason: cle);
    }
  });
}

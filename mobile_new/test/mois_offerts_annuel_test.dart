import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/core/config/distribution_channel.dart';
import 'package:pronowin/features/abonnement/presentation/pages/activer_premium_page.dart';
import 'package:pronowin/features/abonnement/presentation/providers/subscription_provider.dart';

/// Les mois offerts par l'annuel se calculent sur les prix proposés.
///
/// « Annuel · 2 mois offerts » était écrit en dur, alors que chaque grille
/// publiée — 10 $ et 90 $, 6 000 et 54 000 FCFA, 14,99 $ et 134,99 $ au store —
/// fait payer l'année neuf mois : trois offerts. Une promesse de prix fausse
/// sur l'écran d'achat est un motif de refus à l'examen d'Apple.
void main() {
  group('le calcul', () {
    test('chaque grille publiée offre trois mois', () {
      expect(moisOffertsAnnuel(10, 90), 3);
      expect(moisOffertsAnnuel(6000, 54000), 3);
      expect(moisOffertsAnnuel(15, 135), 3);
      // Les paliers du store : 12 × 14,99 $ − 134,99 $ = 2,99 mois.
      expect(moisOffertsAnnuel(14.99, 134.99), 3);
    });

    test('suit le prix quand il change', () {
      expect(moisOffertsAnnuel(10, 100), 2);
      expect(moisOffertsAnnuel(10, 110), 1);
    });

    test('un annuel qui n\'économise rien n\'annonce rien', () {
      expect(moisOffertsAnnuel(10, 120), 0);
      expect(moisOffertsAnnuel(10, 130), 0);
      expect(moisOffertsAnnuel(0, 90), 0, reason: 'tarif manquant : pas de promesse');
      expect(libelleMoisOfferts(0), isNull);
    });

    test('le libellé s\'accorde', () {
      expect(libelleMoisOfferts(1), '1 mois offert');
      expect(libelleMoisOfferts(3), '3 mois offerts');
    });
  });

  Future<void> monter(WidgetTester tester, {required num mensuel, required num annuel}) async {
    final publie = <String, dynamic>{
      'plan': 'free', 'days_left': 0,
      'promo_code': 'CODE77',
      'premium_price_monthly_usd': mensuel,
      'premium_price_annual_usd': annuel,
      'betting_platforms': ['1xbet'],
      'code_offer_days': 30,
      'payment_methods': <Map<String, dynamic>>[],
    };
    await tester.pumpWidget(ProviderScope(
      overrides: [
        currentSubscriptionProvider.overrideWith((ref) async => publie),
        isStoreBuildProvider.overrideWithValue(false),
        submitProofProvider.overrideWith((ref) => SubmitProofNotifier(Dio())),
      ],
      child: const MaterialApp(home: ActiverPremiumPage()),
    ));
    await tester.pump();
    // `initState` lit `authProvider`, qui construit des dépendances Firebase
    // absentes hors application (voir paywall_offre_mensuelle_test.dart).
    tester.takeException();
    await tester.pump(const Duration(milliseconds: 600));
    tester.takeException();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 2));
    });
  }

  testWidgets('l\'écran annonce trois mois, pas deux', (tester) async {
    await monter(tester, mensuel: 10, annuel: 90);
    expect(find.text('Annuel · 3 mois offerts'), findsOneWidget);

    await tester.tap(find.textContaining('Annuel'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('3 MOIS OFFERTS'), findsOneWidget);
    expect(find.textContaining('2 mois offerts'), findsNothing);
    expect(find.textContaining('2 MOIS OFFERTS'), findsNothing);
  });

  testWidgets('un autre tarif, une autre promesse', (tester) async {
    await monter(tester, mensuel: 10, annuel: 100);
    expect(find.text('Annuel · 2 mois offerts'), findsOneWidget);
  });
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/core/config/distribution_channel.dart';
import 'package:pronowin/core/network/dio_client.dart';
import 'package:pronowin/features/abonnement/domain/tarifs_premium.dart';
import 'package:pronowin/features/abonnement/presentation/pages/activer_premium_page.dart';
import 'package:pronowin/features/abonnement/presentation/providers/subscription_provider.dart';

/// Paiement Mobile Money automatique (GeniusPay, 13 octobre 2026).
///
/// Quand le serveur le propose à ce compte, le canal direct offre de payer
/// sur la page GeniusPay ; l'écran suit ensuite le paiement et confirme le
/// Premium sans preuve à envoyer. Sinon, rien ne change : la preuve Orange
/// Money reste le seul parcours.

/// Ce que répond le serveur PronoWin : l'ouverture du paiement, puis son état.
class _Serveur implements HttpClientAdapter {
  final requetes = <String>[];
  bool paye = false;

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? a) async {
    requetes.add('${o.method} ${o.path}');
    final corps = switch ((o.method, o.path)) {
      ('POST', '/subscriptions/geniuspay') => {
        'id': 'p1', 'reference': 'MTX-1', 'montant': 6000, 'plan': 'premium_monthly',
        'checkout_url': 'https://pay.genius.ci/checkout/MTX-1'},
      ('GET', '/subscriptions/geniuspay/p1') => {
        'id': 'p1', 'statut': paye ? 'completed' : 'pending', 'premium_active': paye,
        'expire_le': paye ? '2026-11-12T10:00:00.000Z' : null},
      // Le reste (profil relu après le paiement…) n'est pas le sujet.
      _ => null,
    };
    return ResponseBody.fromString(jsonEncode(corps ?? {'message': 'hors sujet'}), corps == null ? 404 : 200,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  Map<String, dynamic> publie({required bool auto}) => {
    'plan': 'free', 'days_left': 0,
    'promo_code': 'CODE77',
    'premium_price_monthly_usd': 10, 'premium_price_annual_usd': 90,
    'premium_price_monthly_fcfa': 6000, 'premium_price_annual_fcfa': 54000,
    'betting_platforms': ['1xbet'], 'code_offer_days': 30,
    'payment_methods': [
      {'key': 'orange_money', 'label': 'Orange Money', 'phone': '22645568158'},
    ],
    'paiement_geniuspay': auto,
  };

  late List<MethodCall> lancements;
  setUp(() {
    lancements = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/url_launcher'), (appel) async {
        if (appel.method == 'launch') lancements.add(appel);
        return true;
      });
  });

  Future<_Serveur> monter(WidgetTester tester, {required bool auto}) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final serveur = _Serveur();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        currentSubscriptionProvider.overrideWith((ref) async => publie(auto: auto)),
        isStoreBuildProvider.overrideWithValue(false),
        submitProofProvider.overrideWith((ref) => SubmitProofNotifier(Dio())),
        dioProvider.overrideWithValue(Dio()..httpClientAdapter = serveur),
      ],
      child: const MaterialApp(home: ActiverPremiumPage()),
    ));
    await tester.pump();
    // `initState` lit `authProvider`, qui construit des dépendances Firebase
    // absentes hors application.
    tester.takeException();
    await tester.pump(const Duration(milliseconds: 600));
    tester.takeException();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 2));
    });
    return serveur;
  }

  Future<void> versLeFormulaire(WidgetTester tester) async {
    await tester.tap(find.text('Passer au mensuel'));
    await tester.pump(const Duration(milliseconds: 600));
    tester.takeException();
  }

  test('le drapeau du serveur arrive jusqu\'aux tarifs', () {
    expect(TarifsPremium.depuis({'paiement_geniuspay': true}).paiementAutomatique, isTrue);
    expect(TarifsPremium.depuis({}).paiementAutomatique, isFalse);
  });

  testWidgets('sans le paiement automatique, seul le parcours par preuve est proposé', (tester) async {
    await monter(tester, auto: false);
    expect(find.text('Mobile Money · activation immédiate'), findsNothing);
    await versLeFormulaire(tester);
    expect(find.text('Paiement Mobile Money, activation immédiate'), findsNothing);
    expect(find.textContaining('Envoyer la preuve'), findsOneWidget);
  });

  testWidgets('payer ouvre la page GeniusPay, puis confirme le Premium sans preuve', (tester) async {
    final serveur = await monter(tester, auto: true);
    expect(find.text('Mobile Money · activation immédiate'), findsOneWidget);
    expect(find.text('Accès Premium activé immédiatement après le paiement.'), findsOneWidget);

    await versLeFormulaire(tester);
    expect(find.text('Paiement Mobile Money, activation immédiate'), findsOneWidget);
    // Plus de preuve à envoyer ni de vérification manuelle : un recours au
    // support à la place.
    expect(find.textContaining('Envoyer la preuve'), findsNothing);
    expect(find.textContaining('capture'), findsNothing);
    expect(find.text('Un souci avec ton paiement ? Écris-nous'), findsOneWidget);

    await tester.tap(find.textContaining('Payer 6'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(serveur.requetes, contains('POST /subscriptions/geniuspay'));
    expect(lancements, hasLength(1));
    expect(lancements.single.arguments['url'], 'https://pay.genius.ci/checkout/MTX-1');
    expect(find.text('En attente de la confirmation du paiement…'), findsOneWidget);

    // Pas encore payé : l'écran attend.
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('Premium activé !'), findsNothing);

    // Payé : la confirmation s'affiche, sans parler de store.
    serveur.paye = true;
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 600));
    tester.takeException();
    expect(find.text('Premium activé !'), findsOneWidget);
    expect(find.textContaining('Pas de renouvellement automatique'), findsOneWidget);
    expect(find.textContaining('compte store'), findsNothing);
  });
}

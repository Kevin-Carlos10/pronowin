import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pronowin/core/constants/app_constants.dart';
import 'package:pronowin/core/network/dio_client.dart';
import 'package:pronowin/core/storage/secure_storage.dart';
import 'package:pronowin/features/auth/data/datasources/apple_auth_service.dart';
import 'package:pronowin/features/auth/data/datasources/auth_remote_datasource.dart';
import 'package:pronowin/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:pronowin/features/auth/presentation/pages/email_auth_page.dart';

/// « Se connecter avec Apple » (règle 4.8 de l'App Store).
class _StockageMemoire extends SecureStorageService {
  final Map<String, String> valeurs = {};
  @override
  Future<String?> read(String key) async => valeurs[key];
  @override
  Future<void> write(String key, String value) async => valeurs[key] = value;
  @override
  Future<void> deleteAll() async => valeurs.clear();
}

class _Serveur implements HttpClientAdapter {
  final List<({String chemin, Map<String, dynamic> corps})> requetes = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? corps, Future<void>? annulation) async {
    final brut = corps == null ? '' : utf8.decode(await corps.expand((o) => o).toList());
    requetes.add((chemin: options.path, corps: jsonDecode(brut) as Map<String, dynamic>));
    return ResponseBody.fromString(jsonEncode({
      'access_token': 'acces', 'refresh_token': 'rafraichissement',
      'user': {
        'id': 'u1', 'pseudo': 'Parieur_APPLE', 'email': 'x@privaterelay.appleid.com',
        'country_code': 'CI', 'subscription_plan': 'free', 'referral_code': 'ABC',
        'referral_earnings': 0, 'created_at': '2026-09-29T10:00:00Z',
        'phone_verified': false, 'email_verified': true,
      },
    }), 200, headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  group('le nonce', () {
    test('neuf à chaque tentative, de 32 caractères sûrs', () {
      final a = AppleAuthService.nonceBrut();
      final b = AppleAuthService.nonceBrut();
      expect(a, hasLength(32));
      expect(a, isNot(b));
      expect(a, matches(RegExp(r'^[0-9A-Za-z\-._]{32}$')));
      expect(AppleAuthService.nonceBrut(Random(1)), AppleAuthService.nonceBrut(Random(1)));
    });

    test('Apple reçoit son empreinte SHA-256 en hexadécimal, comme le serveur la calcule', () {
      expect(AppleAuthService.empreinte('abc'),
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
    });
  });

  test('la session s\'ouvre sur ce que le serveur a vérifié ; les champs absents ne partent pas', () async {
    final serveur = _Serveur();
    final stockage = _StockageMemoire();
    final dio = Dio(BaseOptions(baseUrl: 'https://api.banc.invalid'))..httpClientAdapter = serveur;
    final depot = AuthRepositoryImpl(AuthRemoteDataSourceImpl(dio), stockage);

    const ids = IdentifiantsApple(identityToken: 'jeton', nonce: 'nonce-brut', authorizationCode: 'code');
    final user = await depot.appleLogin(ids.versApi());

    expect(serveur.requetes.single.chemin, ApiEndpoints.appleLogin);
    expect(serveur.requetes.single.corps,
        {'identity_token': 'jeton', 'nonce': 'nonce-brut', 'authorization_code': 'code'});
    expect(user.pseudo, 'Parieur_APPLE');
    expect(stockage.valeurs[AppConstants.refreshTokenKey], 'rafraichissement');
  });

  group('le bouton', () {
    Future<void> monter(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      // Un client réseau sans la télémétrie Firebase, absente des bancs.
      await tester.pumpWidget(ProviderScope(
        overrides: [dioProvider.overrideWithValue(Dio()), secureStorageProvider.overrideWithValue(_StockageMemoire())],
        child: const MaterialApp(home: EmailAuthPage())));
      await tester.pumpAndSettle();
    }

    testWidgets('sur iPhone, « Continuer avec Apple » est proposé, entre Google et l\'e-mail', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await monter(tester);
      final apple = tester.getTopLeft(find.text('Continuer avec Apple')).dy;
      expect(tester.getTopLeft(find.text('Continuer avec Google')).dy, lessThan(apple));
      expect(tester.getTopLeft(find.text('Continuer avec un e-mail')).dy, greaterThan(apple));
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('sur Android, il n\'apparaît pas', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await monter(tester);
      expect(find.text('Continuer avec Apple'), findsNothing);
      expect(find.text('Continuer avec Google'), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });
  });
}

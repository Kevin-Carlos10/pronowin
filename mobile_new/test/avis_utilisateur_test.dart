import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import 'package:pronowin/core/network/dio_client.dart';
import 'package:pronowin/core/theme/app_theme.dart';
import 'package:pronowin/features/parametres/presentation/pages/avis_page.dart';

import 'aides/banc_ecran.dart';

/// « Donne-nous ton avis » (8 novembre 2026), comme Sofascore.
class _Serveur implements HttpClientAdapter {
  final recus = <Map<String, dynamic>>[];
  int statut = 201;

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? a) async {
    if (o.path == '/support/avis') recus.add(Map<String, dynamic>.from(o.data as Map));
    final corps = statut == 201 ? {'id': 'a1'} : {'message': 'Merci, nous avons bien reçu tes messages. Réessaie dans une heure.'};
    return ResponseBody.fromString(jsonEncode(corps), statut,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  setUpAll(() async => preparerBanc());

  setUp(() {
    AvisPage.lireVersion = () async => '1.0.35 (51)';
    // Une vraie image (PNG 1×1) : l'aperçu la décode.
    AvisPage.choisirCapture = () async => XFile.fromData(base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='),
        name: 'capture.png', mimeType: 'image/png');
  });

  Future<_Serveur> monter(WidgetTester t) async {
    t.view.physicalSize = const Size(800, 1700);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    final serveur = _Serveur();
    await t.pumpWidget(ProviderScope(
      overrides: [...donneesCommunes(), dioProvider.overrideWithValue(Dio()..httpClientAdapter = serveur)],
      child: MaterialApp.router(theme: AppTheme.dark, routerConfig: GoRouter(initialLocation: '/parametres/avis', routes: [
        GoRoute(path: '/parametres', builder: (_, _) => const Scaffold(body: Text('PARAMÈTRES'))),
        GoRoute(path: '/parametres/avis', builder: (_, _) => const AvisPage()),
      ])),
    ));
    await t.pump();
    return serveur;
  }

  bool actif(WidgetTester t) =>
      t.widget<ElevatedButton>(find.byKey(const Key('avis-envoyer'))).onPressed != null;

  testWidgets('dix caractères au moins avant de pouvoir envoyer', (t) async {
    await monter(t);
    expect(actif(t), isFalse);
    await t.enterText(find.byKey(const Key('avis-message')), 'Bug');
    await t.pump();
    expect(find.text('Encore 7 caractères au moins.'), findsOneWidget);
    expect(actif(t), isFalse);
    await t.enterText(find.byKey(const Key('avis-message')), 'Le score reste figé en direct.');
    await t.pump();
    expect(actif(t), isTrue);
  });

  testWidgets('connecté : e-mail facultatif ; message, capture, version et système partent', (t) async {
    final serveur = await monter(t);
    expect(find.text('Ton e-mail (facultatif)'), findsOneWidget);
    await t.enterText(find.byKey(const Key('avis-message')), 'Le score reste figé en direct.');
    await t.tap(find.byKey(const Key('avis-capture')));
    await t.pump();
    await t.pump();
    expect(find.text('Capture jointe'), findsOneWidget);
    await t.tap(find.byKey(const Key('avis-envoyer')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(serveur.recus, hasLength(1));
    final r = serveur.recus.single;
    expect(r['message'], 'Le score reste figé en direct.');
    expect(r['version_app'], '1.0.35 (51)');
    expect(r['plateforme'], isNotNull);
    expect(r['image_base64'] as String, startsWith('data:image/jpeg;base64,'));
    expect(r.containsKey('email'), isFalse);
    await t.pumpAndSettle();
    expect(find.text('PARAMÈTRES'), findsOneWidget);
  });

  testWidgets('la capture se retire', (t) async {
    final serveur = await monter(t);
    await t.enterText(find.byKey(const Key('avis-message')), 'Ajoutez la Ligue 1 burkinabè.');
    await t.tap(find.byKey(const Key('avis-capture')));
    await t.pump();
    await t.pump();
    await t.tap(find.byKey(const Key('avis-retirer-capture')));
    await t.pump();
    expect(find.byKey(const Key('avis-capture')), findsOneWidget);
    await t.tap(find.byKey(const Key('avis-envoyer')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(serveur.recus.single.containsKey('image_base64'), isFalse);
    await t.pumpAndSettle();
  });

  testWidgets('refus du serveur : son message, et on reste sur la page', (t) async {
    final serveur = await monter(t);
    serveur.statut = 429;
    await t.enterText(find.byKey(const Key('avis-message')), 'Encore un message de plus.');
    await t.pump();
    await t.tap(find.byKey(const Key('avis-envoyer')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('Merci, nous avons bien reçu tes messages. Réessaie dans une heure.'), findsOneWidget);
    expect(find.byKey(const Key('avis-message')), findsOneWidget);
    await t.pumpAndSettle(const Duration(seconds: 1));
  });

  testWidgets('texte agrandi : la page tient', (t) async {
    t.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    await monter(t);
    await t.tap(find.byKey(const Key('avis-capture')));
    await t.pump();
    await t.pump();
    expect(t.takeException(), isNull);
  });
}

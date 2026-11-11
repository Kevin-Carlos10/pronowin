import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronowin/core/config/distribution_channel.dart';
import 'package:pronowin/core/network/dio_client.dart';
import 'package:pronowin/core/theme/app_theme.dart';
import 'package:pronowin/features/parametres/presentation/pages/parametres_page.dart';
import 'package:pronowin/features/parametres/presentation/providers/security_provider.dart';
import 'package:pronowin/features/parametres/presentation/providers/settings_provider.dart';
import 'package:pronowin/l10n/app_strings.dart';

import 'aides/banc_ecran.dart';

/// Les Paramètres au dessin de 1xPartners (11 novembre 2026) : la sécurité
/// d'abord, des statuts « Activé / Pas activé », des sous-pages pour les
/// notifications et les choix, la version installée en bas.
void main() {
  setUpAll(() async => preparerBanc());

  Future<ProviderContainer> monter(WidgetTester t, {Map<String, dynamic>? config,
      double largeur = 390, double echelle = 1}) async {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(appName: 'PronoWin', packageName: 'com.pronowin.app',
        version: '1.0.35', buildNumber: '63', buildSignature: '');
    t.view.physicalSize = Size(largeur, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final conteneur = ProviderContainer(overrides: [
      bioAvailableProvider.overrideWith((ref) async => true),
      appVersionProvider.overrideWith((ref) async => 'v1.0.35'),
      isStoreBuildProvider.overrideWithValue(false),
      dioProvider.overrideWithValue(Dio()..httpClientAdapter = _Config(config)),
    ]);
    addTearDown(conteneur.dispose);
    await t.pumpWidget(UncontrolledProviderScope(
      container: conteneur,
      child: MaterialApp(
        theme: AppTheme.dark,
        locale: const Locale('fr'),
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: const [
          AppStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(echelle)),
          child: child!),
        home: const ParametresPage(),
      ),
    ));
    await t.pumpAndSettle();
    return conteneur;
  }

  testWidgets('la sécurité d\'abord, avec ses statuts', (t) async {
    await monter(t);
    final securite = t.getTopLeft(find.text('Sécurité')).dy;
    final application = t.getTopLeft(find.text("Paramètres de l'application")).dy;
    expect(securite, lessThan(application));
    expect(find.text('Code PIN'), findsOneWidget);
    expect(find.text('Déverrouillage biométrique'), findsOneWidget);
    // PIN et biométrie éteints : « Pas activé ».
    expect(find.descendant(of: find.byKey(const Key('reglage-pin')), matching: find.text('Pas activé')), findsOneWidget);
    expect(find.byIcon(Icons.cancel_rounded), findsWidgets);
    expect(t.takeException(), isNull);
  });

  testWidgets('« Notifications push » : une sous-page, et le statut suit', (t) async {
    final c = await monter(t);
    final notifs = find.byKey(const Key('reglage-notifications'));
    // Les promotions sont à activer soi-même : trois sur quatre au départ.
    expect(find.descendant(of: notifs, matching: find.text('3 sur 4 activées')), findsOneWidget);
    // Plus d'interrupteurs d'alerte sur la page principale.
    expect(find.text('Alertes matchs'), findsNothing);

    await t.tap(notifs);
    await t.pumpAndSettle();
    expect(find.text('Alertes matchs'), findsOneWidget);
    expect(find.text('Réglages du téléphone'), findsOneWidget);
    await t.tap(find.byKey(const Key('notif-promo')));
    await t.pumpAndSettle();
    expect(c.read(settingsProvider).notifPromo, isTrue);

    await t.tap(find.byIcon(Icons.arrow_back_ios_new_rounded).last);
    await t.pumpAndSettle();
    expect(find.descendant(of: find.byKey(const Key('reglage-notifications')), matching: find.text('Activé')),
        findsOneWidget);
  });

  testWidgets('le thème se choisit sur sa page, coché, et ramène aux Paramètres', (t) async {
    final c = await monter(t);
    await t.tap(find.byKey(const Key('reglage-theme')));
    await t.pumpAndSettle();
    expect(find.text("Thème de l'application"), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('theme-sombre')), matching: find.byIcon(Icons.check_rounded)),
        findsOneWidget);
    await t.tap(find.byKey(const Key('theme-clair')));
    await t.pumpAndSettle();
    expect(c.read(settingsProvider).themeMode, ThemeMode.light);
    expect(find.text("Thème de l'application"), findsNothing);
    expect(find.text('Paramètres'), findsOneWidget);
  });

  testWidgets('l\'onglet d\'ouverture se choisit sur sa page', (t) async {
    await monter(t);
    await t.tap(find.byKey(const Key('reglage-onglet')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('onglet-suivis')));
    await t.pumpAndSettle();
    expect(find.descendant(of: find.byKey(const Key('reglage-onglet')), matching: find.text('Suivis')), findsOneWidget);
  });

  testWidgets('la carte de version : à jour', (t) async {
    await monter(t, config: {'apkLatestVersion': '1.0.35', 'apkMinVersion': '1.0.28',
        'apkUrl': 'https://pronowin.space/downloads/pronowin.apk'});
    await t.scrollUntilVisible(find.byKey(const Key('carte-version')), 200, scrollable: find.byType(Scrollable).first);
    await t.pumpAndSettle();
    expect(find.text("Vous utilisez la dernière version de l'appli"), findsOneWidget);
    expect(find.text('1.0.35'), findsOneWidget);
  });

  testWidgets('la carte de version : une mise à jour à installer', (t) async {
    await monter(t, config: {'apkLatestVersion': '1.0.36', 'apkMinVersion': '1.0.28',
        'apkUrl': 'https://pronowin.space/downloads/pronowin.apk'});
    await t.scrollUntilVisible(find.byKey(const Key('carte-version')), 200, scrollable: find.byType(Scrollable).first);
    await t.pumpAndSettle();
    expect(find.text('Une nouvelle version est disponible'), findsOneWidget);
    expect(find.text('1.0.35 → 1.0.36 · Touche pour mettre à jour'), findsOneWidget);
  });

  testWidgets('serveur muet : la version seule, sans rien affirmer', (t) async {
    await monter(t);
    await t.scrollUntilVisible(find.byKey(const Key('carte-version')), 200, scrollable: find.byType(Scrollable).first);
    await t.pumpAndSettle();
    expect(find.text("Version de l'application"), findsOneWidget);
    expect(find.text("Vous utilisez la dernière version de l'appli"), findsNothing);
  });

  testWidgets('petit écran, texte agrandi : rien ne déborde', (t) async {
    await monter(t, largeur: 320, echelle: 1.8);
    for (var i = 0; i < 12; i++) {
      await t.drag(find.byType(ListView).first, const Offset(0, -400));
      await t.pump();
    }
    expect(t.takeException(), isNull);
    await t.tap(find.byKey(const Key('reglage-supprimer-compte')));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });
}

/// `GET /config` : la configuration donnée, ou une panne.
class _Config implements HttpClientAdapter {
  final Map<String, dynamic>? config;
  _Config(this.config);

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? a) async {
    final ok = config != null && o.path == '/config';
    return ResponseBody.fromString(jsonEncode(ok ? config : {}), ok ? 200 : 503,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
  }

  @override
  void close({bool force = false}) {}
}

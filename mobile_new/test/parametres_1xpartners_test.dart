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

  /// Un test de la page, démontée à la fin : Riverpod libère ses
  /// fournisseurs éphémères au démontage, sur un minuteur à vider.
  void testParametres(String nom, Future<void> Function(WidgetTester t) corps) =>
      testWidgets(nom, (t) async {
        await corps(t);
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(seconds: 1));
      });

  Future<ProviderContainer> monter(WidgetTester t, {Map<String, dynamic>? config,
      double largeur = 390, double echelle = 1, bool store = false, bool connecte = false}) async {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(appName: 'PronoWin', packageName: 'com.pronowin.app',
        version: '1.0.35', buildNumber: '63', buildSignature: '');
    t.view.physicalSize = Size(largeur, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final conteneur = ProviderContainer(overrides: [
      // Connecté : le compte du banc (et son serveur, muet sur /config).
      if (connecte) ...donneesCommunes()
      else dioProvider.overrideWithValue(Dio()..httpClientAdapter = _Config(config)),
      bioAvailableProvider.overrideWith((ref) async => true),
      appVersionProvider.overrideWith((ref) async => 'v1.0.35'),
      isStoreBuildProvider.overrideWithValue(store),
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
    // Les sections entrent en décalé à la première visite (motion.dart) :
    // laisser finir leurs délais, qui ne sont pas des images.
    await t.pump(const Duration(seconds: 1));
    await t.pumpAndSettle();
    return conteneur;
  }

  testParametres('la sécurité d\'abord, avec ses statuts', (t) async {
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

  testParametres('« Notifications push » : une sous-page, et le statut suit', (t) async {
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

  testParametres('le thème : quatre aperçus, appliqué sans quitter la page', (t) async {
    final c = await monter(t);
    await t.tap(find.byKey(const Key('reglage-theme')));
    await t.pumpAndSettle();
    expect(find.text("Thème de l'application"), findsOneWidget);
    for (final n in ['clair', 'sombre', 'nocturne', 'systeme']) {
      expect(find.byKey(Key('theme-$n')), findsOneWidget);
    }
    expect(find.descendant(of: find.byKey(const Key('theme-sombre')),
        matching: find.byIcon(Icons.check_circle_rounded)), findsOneWidget);

    await t.tap(find.byKey(const Key('theme-nocturne')));
    await t.pumpAndSettle();
    expect(c.read(settingsProvider).themeMode, ThemeMode.dark);
    expect(c.read(settingsProvider).nocturne, isTrue);
    expect((await SharedPreferences.getInstance()).getString('settings_theme'), 'nocturne');
    // La page reste ouverte, la coche a suivi.
    expect(find.text("Thème de l'application"), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('theme-nocturne')),
        matching: find.byIcon(Icons.check_circle_rounded)), findsOneWidget);

    await t.tap(find.byKey(const Key('theme-clair')));
    await t.pumpAndSettle();
    expect(c.read(settingsProvider).themeMode, ThemeMode.light);
    expect(c.read(settingsProvider).nocturne, isFalse);

    await t.tap(find.byIcon(Icons.arrow_back_ios_new_rounded).last);
    await t.pumpAndSettle();
    expect(find.descendant(of: find.byKey(const Key('reglage-theme')),
        matching: find.text(c.read(settingsProvider).themeName)), findsOneWidget);
  });

  testParametres('tout mettre en pause, puis reprendre les réglages d\'avant', (t) async {
    final c = await monter(t);
    await t.tap(find.byKey(const Key('reglage-notifications')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('notif-pause')));
    await t.pumpAndSettle();
    final s = c.read(settingsProvider);
    expect(s.notifPause, isTrue);
    expect([s.notifMatch, s.notifPromo, s.notifReferral, s.notifPremium], everyElement(isFalse));
    expect(find.text('Toutes les notifications sont en pause'), findsOneWidget);
    // Figées pendant la pause.
    final premium = t.widget<Switch>(find.descendant(of: find.byKey(const Key('notif-premium')), matching: find.byType(Switch)));
    expect(premium.onChanged, isNull);

    await t.tap(find.byIcon(Icons.arrow_back_ios_new_rounded).last);
    await t.pumpAndSettle();
    expect(find.descendant(of: find.byKey(const Key('reglage-notifications')), matching: find.text('En pause')),
        findsOneWidget);

    await t.tap(find.byKey(const Key('reglage-notifications')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('notif-pause')));
    await t.pumpAndSettle();
    final r = c.read(settingsProvider);
    expect(r.notifPause, isFalse);
    // Les promotions étaient coupées avant la pause : elles le restent.
    expect([r.notifMatch, r.notifPromo, r.notifReferral, r.notifPremium], [true, false, true, true]);
  });

  testParametres('la protection : faible sans code ni biométrie, renforcée avec', (t) async {
    final c = await monter(t);
    final protection = find.byKey(const Key('reglage-protection'));
    expect(find.descendant(of: protection, matching: find.text('Faible : active le code PIN ou la biométrie')),
        findsOneWidget);
    expect(find.descendant(of: protection, matching: find.byIcon(Icons.error_rounded)), findsOneWidget);
    await c.read(settingsProvider.notifier).setBioEnabled(true);
    await t.pumpAndSettle();
    expect(find.descendant(of: protection, matching: find.text('Renforcée')), findsOneWidget);
  });

  testParametres('partager par QR code, et les réseaux sociaux', (t) async {
    await monter(t);
    await t.scrollUntilVisible(find.byKey(const Key('reglage-qr')), 200, scrollable: find.byType(Scrollable).first);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('reglage-qr')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('qr-partage')), findsOneWidget);
    expect(find.text('Fais scanner ce code'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.tap(find.byIcon(Icons.arrow_back_ios_new_rounded).last);
    await t.pumpAndSettle();

    await t.tap(find.byKey(const Key('reglage-reseaux')));
    await t.pumpAndSettle();
    for (final r in ['telegram', 'whatsapp', 'facebook']) {
      expect(find.byKey(Key('reseau-$r')), findsOneWidget);
    }
  });

  testParametres('« Noter l\'application » : seulement pour une version des boutiques', (t) async {
    await monter(t);
    expect(find.byKey(const Key('reglage-noter'), skipOffstage: false), findsNothing);
    await monter(t, store: true);
    expect(find.byKey(const Key('reglage-noter'), skipOffstage: false), findsOneWidget);
  });

  testParametres('« Se déconnecter » en bas de Mon compte, pour un compte connecté', (t) async {
    await monter(t);
    expect(find.byKey(const Key('reglage-deconnexion'), skipOffstage: false), findsNothing);
    await monter(t, connecte: true);
    await t.scrollUntilVisible(find.byKey(const Key('reglage-deconnexion')), 200, scrollable: find.byType(Scrollable).first);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('reglage-deconnexion')));
    await t.pumpAndSettle();
    expect(find.text('Déconnexion ?'), findsOneWidget);
  });

  test('Nocturne : noir pur, et les textes se lisent dessus', () {
    expect(AppTheme.nocturne.scaffoldBackgroundColor, const Color(0xFF000000));
    expect(AppTheme.nocturne.extension<ThemeNocturne>(), isNotNull);
    expect(AppTheme.dark.extension<ThemeNocturne>(), isNull);
    double contraste(Color a, Color b) {
      final la = a.computeLuminance(), lb = b.computeLuminance();
      return ((la > lb ? la : lb) + 0.05) / ((la > lb ? lb : la) + 0.05);
    }
    const cl = AppClNocturne();
    for (final fond in [cl.bg, cl.surface, cl.surfaceD]) {
      for (final texte in [cl.textP, cl.textS, cl.textM]) {
        expect(contraste(texte, fond), greaterThanOrEqualTo(4.5), reason: '$texte sur $fond');
      }
    }
  });

  testParametres('context.cl suit le thème Nocturne', (t) async {
    AppCl? lu;
    await t.pumpWidget(MaterialApp(theme: AppTheme.nocturne,
      home: Builder(builder: (context) { lu = context.cl; return const SizedBox(); })));
    expect(lu, isA<AppClNocturne>());
    expect(lu!.bg, const Color(0xFF000000));
  });

  testParametres('l\'onglet d\'ouverture se choisit sur sa page', (t) async {
    await monter(t);
    await t.tap(find.byKey(const Key('reglage-onglet')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('onglet-suivis')));
    await t.pumpAndSettle();
    expect(find.descendant(of: find.byKey(const Key('reglage-onglet')), matching: find.text('Suivis')), findsOneWidget);
  });

  testParametres('la carte de version : à jour', (t) async {
    await monter(t, config: {'apkLatestVersion': '1.0.35', 'apkMinVersion': '1.0.28',
        'apkUrl': 'https://pronowin.space/downloads/pronowin.apk'});
    await t.scrollUntilVisible(find.byKey(const Key('carte-version')), 200, scrollable: find.byType(Scrollable).first);
    await t.pumpAndSettle();
    expect(find.text("Vous utilisez la dernière version de l'appli"), findsOneWidget);
    expect(find.text('1.0.35'), findsOneWidget);
  });

  testParametres('la carte de version : une mise à jour à installer', (t) async {
    await monter(t, config: {'apkLatestVersion': '1.0.36', 'apkMinVersion': '1.0.28',
        'apkUrl': 'https://pronowin.space/downloads/pronowin.apk'});
    await t.scrollUntilVisible(find.byKey(const Key('carte-version')), 200, scrollable: find.byType(Scrollable).first);
    await t.pumpAndSettle();
    expect(find.text('Une nouvelle version est disponible'), findsOneWidget);
    expect(find.text('1.0.35 → 1.0.36 · Touche pour mettre à jour'), findsOneWidget);
  });

  testParametres('serveur muet : la version seule, sans rien affirmer', (t) async {
    await monter(t);
    await t.scrollUntilVisible(find.byKey(const Key('carte-version')), 200, scrollable: find.byType(Scrollable).first);
    await t.pumpAndSettle();
    expect(find.text("Version de l'application"), findsOneWidget);
    expect(find.text("Vous utilisez la dernière version de l'appli"), findsNothing);
  });

  testParametres('petit écran, texte agrandi : rien ne déborde', (t) async {
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

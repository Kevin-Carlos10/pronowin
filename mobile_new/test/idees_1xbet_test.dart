import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronowin/core/services/cache_fichiers.dart';
import 'package:pronowin/core/theme/app_theme.dart';
import 'package:pronowin/features/onboarding/presentation/pages/onboarding_page.dart';
import 'package:pronowin/features/parametres/presentation/widgets/apercu_technique.dart';
import 'package:pronowin/features/parrainage/presentation/pages/parrainage_page.dart';
import 'package:pronowin/shared/utils/partage_parrainage.dart';

import 'aides/banc_ecran.dart';

/// Quatre idées reprises de 1xBet (7 novembre 2026), rien de ce qui sert à
/// parier : taille du cache, aperçu technique à copier, présentation à revoir,
/// code QR de parrainage.
void main() {
  setUpAll(() async => preparerBanc());

  group('cache', () {
    late Directory tmp;
    setUp(() {
      tmp = Directory.systemTemp.createTempSync('cache_pw');
      CacheFichiers.dossier = () async => tmp;
    });
    tearDown(() {
      CacheFichiers.dossier = () async => tmp;
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('compte et efface les images, jamais la mise à jour en cours', () async {
      Directory('${tmp.path}/libCachedImageData').createSync();
      File('${tmp.path}/libCachedImageData/a.png').writeAsBytesSync(List.filled(3000, 1));
      File('${tmp.path}/b.jpg').writeAsBytesSync(List.filled(1000, 1));
      Directory('${tmp.path}/maj').createSync();
      File('${tmp.path}/maj/pronowin.apk').writeAsBytesSync(List.filled(50000, 1));

      expect(await CacheFichiers.taille(), 4000);
      await CacheFichiers.vider();
      expect(await CacheFichiers.taille(), 0);
      expect(File('${tmp.path}/maj/pronowin.apk').existsSync(), isTrue);
    });

    test('lisible : Ko, Mo avec virgule, MB en anglais', () {
      expect(CacheFichiers.lisible(0), '0 Ko');
      expect(CacheFichiers.lisible(524288), '512 Ko');
      expect(CacheFichiers.lisible(88394547), '84,3 Mo');
      expect(CacheFichiers.lisible(88394547, langue: 'en'), '84.3 MB');
    });
  });

  testWidgets('aperçu technique : version, canal, compte, installation ; « Copier » remplit le presse-papiers', (t) async {
    String? copie;
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (c) async {
      if (c.method == 'Clipboard.setData') copie = (c.arguments as Map)['text'] as String;
      return null;
    });
    addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    Future<PackageInfo> infos() async => PackageInfo(appName: 'PronoWin', packageName: 'com.pronowin.app',
        version: '1.0.34', buildNumber: '59', installTime: DateTime(2026, 10, 23, 17, 35));

    await t.pumpWidget(ProviderScope(
      overrides: donneesCommunes(),
      child: MaterialApp(theme: AppTheme.dark, home: Scaffold(body: Consumer(builder: (context, ref, _) =>
        TextButton(onPressed: () => afficherApercuTechnique(context, ref, infos: infos, systeme: 'iOS 27.2'),
          child: const Text('ouvrir'))))),
    ));
    await t.tap(find.text('ouvrir'));
    await t.pumpAndSettle();
    expect(find.text('1.0.34 (59)'), findsOneWidget);
    expect(find.text('iOS 27.2'), findsOneWidget);
    expect(find.text('u1'), findsOneWidget, reason: 'l\'identifiant du compte, pour le support');
    expect(find.text('23/10/2026 17:35'), findsOneWidget);

    await t.tap(find.byKey(const Key('copier-apercu')));
    await t.pumpAndSettle();
    expect(copie, contains('Version : 1.0.34 (59)'));
    expect(copie, contains('Compte : u1'));
    expect(find.text('Informations copiées'), findsOneWidget);
  });

  testWidgets('présentation revue : « Passer » ramène en arrière, sans toucher au premier lancement', (t) async {
    SharedPreferences.setMockInitialValues({});
    final routeur = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, _) => const Scaffold(body: Text('PARAMETRES'))),
      GoRoute(path: '/presentation', builder: (_, _) => const OnboardingPage(revoir: true)),
    ]);
    await t.pumpWidget(ProviderScope(overrides: donneesCommunes(),
      child: MaterialApp.router(theme: AppTheme.dark, routerConfig: routeur)));
    // L'accueil anime en boucle : pas de pumpAndSettle.
    Future<void> attendre() async { for (var i = 0; i < 10; i++) { await t.pump(const Duration(milliseconds: 100)); } }
    routeur.push('/presentation');
    await attendre();
    await t.tap(find.text('Passer'));
    await attendre();
    expect(find.text('PARAMETRES'), findsOneWidget);
    expect((await SharedPreferences.getInstance()).getBool('onboarding_done'), isNull);
  });

  testWidgets('code QR de parrainage : le site avec le code, et le code lisible dessous', (t) async {
    expect(lienQrParrainage('1A639B'), endsWith('/?parrain=1A639B'));
    await t.pumpWidget(MaterialApp(theme: AppTheme.dark, home: Scaffold(body: Builder(builder: (context) =>
      TextButton(onPressed: () => afficherQrParrainage(context, '1A639B'), child: const Text('qr'))))));
    await t.tap(find.text('qr'));
    await t.pumpAndSettle();
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('1A639B')), findsWidgets);
    expect(find.text('1A639B'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}

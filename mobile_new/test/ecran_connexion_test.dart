import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pronowin/core/network/dio_client.dart';
import 'package:pronowin/core/storage/secure_storage.dart';
import 'package:pronowin/core/theme/app_theme.dart';
import 'package:pronowin/features/auth/presentation/pages/email_auth_page.dart';
import 'package:pronowin/features/auth/presentation/pages/email_otp_page.dart';
import 'package:pronowin/features/auth/presentation/providers/auth_provider.dart';

/// L'écran de connexion refait (20 novembre 2026), puis en feuille
/// « Connexion ou inscription » (24 novembre 2026).
class _Stockage extends SecureStorageService {
  final Map<String, String> v = {};
  @override
  Future<String?> read(String key) async => v[key];
  @override
  Future<void> write(String key, String value) async => v[key] = value;
  @override
  Future<void> deleteAll() async => v.clear();
}

void main() {
  /// [calme] : attendre que tout s'arrête. Pas pour l'écran du code, dont le
  /// compte à rebours et le curseur ne s'arrêtent jamais.
  Future<ProviderContainer> monter(WidgetTester t, Widget page,
      {Size taille = const Size(390, 844), bool calme = true}) async {
    t.view.physicalSize = taille * 2;
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    final c = ProviderContainer(overrides: [
      dioProvider.overrideWithValue(Dio()),
      secureStorageProvider.overrideWithValue(_Stockage()),
    ]);
    addTearDown(c.dispose);
    await t.pumpWidget(UncontrolledProviderScope(container: c,
      child: MaterialApp(theme: AppTheme.dark, home: page)));
    if (calme) {
      await t.pumpAndSettle();
    } else {
      for (var i = 0; i < 5; i++) {
        await t.pump(const Duration(milliseconds: 200));
      }
    }
    return c;
  }

  Future<void> demonter(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 61));
  }

  testWidgets('sur iPad, les chemins gardent une largeur de lecture', (t) async {
    await monter(t, const EmailAuthPage(), taille: const Size(820, 1180));
    final google = t.getSize(find.ancestor(
      of: find.text('CONTINUER AVEC GOOGLE'), matching: find.byType(Material)).first);
    expect(google.width, lessThanOrEqualTo(largeurConnexion));
    expect(t.takeException(), isNull);
  });

  testWidgets('le consentement nomme les conditions et la confidentialité', (t) async {
    await monter(t, const EmailAuthPage());
    final texte = t.widget<Text>(find.byKey(const Key('connexion-consentement'))).textSpan!.toPlainText();
    expect(texte, contains("conditions d'utilisation"));
    expect(texte, contains('politique de confidentialité'));
    // Sous les chemins, comme sur le modèle.
    expect(t.getTopLeft(find.byKey(const Key('connexion-consentement'))).dy,
      greaterThan(t.getTopLeft(find.text('CONTINUER AVEC UN E-MAIL')).dy));
  });

  testWidgets('la feuille : titre, trois avantages réels, chemins en capitales lus normalement', (t) async {
    await monter(t, const EmailAuthPage());
    expect(find.text('Connexion ou inscription'), findsOneWidget);
    expect(find.byKey(const Key('connexion-avantages')), findsOneWidget);
    for (final a in ['Suis tes équipes favorites', 'Alertes de tes matchs suivis', 'Tes favoris sur tous tes appareils']) {
      expect(find.text(a), findsOneWidget);
    }
    expect(find.text('CONTINUER AVEC GOOGLE'), findsOneWidget);
    // Le lecteur d'écran lit le libellé tel qu'il s'écrit, pas en capitales.
    expect(find.bySemanticsLabel('Continuer avec Google'), findsOneWidget);
    expect(find.byTooltip('Retour'), findsOneWidget);
    expect(find.byTooltip('Fermer'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('écran étroit, texte agrandi : rien ne déborde', (t) async {
    t.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    await monter(t, const EmailAuthPage(), taille: const Size(320, 640));
    expect(t.takeException(), isNull);
  });

  testWidgets('une adresse sans domaine est refusée sur place, sans appel', (t) async {
    final c = await monter(t, const EmailAuthPage());
    await t.tap(find.text('CONTINUER AVEC UN E-MAIL'));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('connexion-email')), 'awa.gmail.com');
    await t.tap(find.text('Recevoir mon code'));
    await t.pumpAndSettle();
    expect(find.text('Email invalide'), findsOneWidget);
    expect(c.read(authProvider), isNot(isA<AuthLoading>()));
    // Et l'on revient au choix sans fermer l'écran.
    await t.tap(find.text('Autres options de connexion'));
    await t.pumpAndSettle();
    expect(find.text('CONTINUER AVEC GOOGLE'), findsOneWidget);
    // Le bouton rond de retour aussi.
    await t.tap(find.text('CONTINUER AVEC UN E-MAIL'));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Retour'));
    await t.pumpAndSettle();
    expect(find.text('CONTINUER AVEC GOOGLE'), findsOneWidget);
  });

  testWidgets('le code : adresse modifiable, conseil si rien n\'arrive, compte à rebours en minutes', (t) async {
    await monter(t, const EmailOtpPage(email: 'awa.traore@gmail.com'), calme: false);
    // L'adresse masquée, dans la phrase.
    expect(find.textContaining('aw********@gmail.com', findRichText: true), findsOneWidget);
    expect(find.byKey(const Key('otp-modifier-adresse')), findsOneWidget);
    expect(find.byKey(const Key('otp-conseil-spam')), findsOneWidget);
    await t.pump(const Duration(seconds: 2));
    expect(find.textContaining(RegExp(r'Renvoyer le code dans 0:5\d')), findsOneWidget);
    await demonter(t);
  });

  testWidgets('quitter l\'écran du code ne libère pas deux fois le champ', (t) async {
    // Le champ du code libérait lui-même son contrôleur, que la page libérait
    // aussi : « A TextEditingController was used after being disposed ».
    await monter(t, const EmailOtpPage(email: 'awa.traore@gmail.com'), calme: false);
    await t.enterText(find.byType(TextFormField).first, '123');
    await t.pump();
    await demonter(t);
    expect(t.takeException(), isNull);
  });
}

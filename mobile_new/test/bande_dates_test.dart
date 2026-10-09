import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronowin/core/theme/app_theme.dart';
import 'package:pronowin/features/pronostics/presentation/pages/pronostics_page.dart';
import 'package:pronowin/l10n/app_strings.dart';

import 'aides/banc_ecran.dart';

/// La bande des dates de l'onglet « Pronos » garde le jour choisi en vue.
///
/// Elle ne se recentrait qu'au tout premier affichage. Reconstruite au retour
/// sur l'onglet — depuis « Pour toi », la recherche, les filtres —, elle
/// repartait de son début, trente jours en arrière : vu en test sur iPhone,
/// « sam. 5, dim. 6… » de septembre, aujourd'hui hors de vue.
void main() {
  setUpAll(preparerBanc);

  const largeur = 390.0;

  Future<void> monter(WidgetTester t) async {
    SharedPreferences.setMockInitialValues({'pseudo_nudge_dismissed': true});
    t.view.physicalSize = const Size(largeur * 2, 844 * 2);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(
      overrides: donneesCommunes(),
      child: MaterialApp.router(
        routerConfig: GoRouter(routes: [GoRoute(path: '/', builder: (_, _) => const PronosticsPage())]),
        theme: AppTheme.light,
        locale: const Locale('fr'),
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: const [
          AppStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
      ),
    ));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  /// La pastille « Auj. » est-elle construite, et dans la largeur de l'écran ?
  void aujourdhuiEnVue(WidgetTester t) {
    final auj = find.text('Auj.');
    expect(auj, findsOneWidget, reason: 'la pastille du jour n\'est même pas construite');
    final r = t.getRect(auj);
    expect(r.left, greaterThanOrEqualTo(0));
    expect(r.right, lessThanOrEqualTo(largeur));
  }

  /// Démonte avant la fin : les minuteurs de la page ne doivent pas survivre au test.
  Future<void> demonter(WidgetTester t) async {
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump(const Duration(minutes: 1));
  }

  testWidgets('aujourd\'hui en vue à l\'ouverture', (t) async {
    await monter(t);
    aujourdhuiEnVue(t);
    await demonter(t);
  });

  testWidgets('aujourd\'hui toujours en vue au retour depuis « Pour toi »', (t) async {
    await monter(t);
    await t.tap(find.text('Pour Toi'));
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    await t.tap(find.text('Pronos').first);
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    aujourdhuiEnVue(t);
    await demonter(t);
  });
}

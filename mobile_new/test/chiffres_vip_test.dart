import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pronowin/core/theme/app_theme.dart';
import 'package:pronowin/shared/widgets/chiffres_vip.dart';

import 'aides/banc_ecran.dart';

/// Les chiffres du mur Premium (24 novembre 2026) : des comptes, pas un taux,
/// réservé aux abonnés. Le serveur tait les comptes trop petits ; l'écran
/// n'affiche que ce qu'il reçoit.
void main() {
  setUpAll(preparerBanc);

  test('la réponse du serveur ; tout nul, rien à montrer', () {
    final c = ChiffresVip.depuisApi({'periode_jours': 30, 'vip_publies': 42, 'competitions': 12, 'vip_aujourdhui': null});
    expect([c.vipPublies, c.competitions, c.vipAujourdhui], [42, 12, null]);
    expect(c.vide, isFalse);
    expect(ChiffresVip.depuisApi({'periode_jours': 30}).vide, isTrue);
  });

  Future<void> monter(WidgetTester t, ChiffresVip? c, {bool sombre = false}) async {
    await t.pumpWidget(ProviderScope(
      overrides: [chiffresVipProvider.overrideWith((ref) async => c)],
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: Padding(
          padding: const EdgeInsets.all(16),
          child: BandeauChiffresVip(surFondSombre: sombre))),
      ),
    ));
    await t.pump();
  }

  testWidgets('trois chiffres, chacun avec sa légende', (t) async {
    await monter(t, const ChiffresVip(periodeJours: 30, vipPublies: 42, competitions: 12, vipAujourdhui: 3));
    expect(find.text('42'), findsOneWidget);
    expect(find.text('pronostics VIP publiés en 30 jours'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('compétitions couvertes'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text("pronostics VIP aujourd'hui"), findsOneWidget);
    // Aucun taux.
    expect(find.textContaining('%'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('un chiffre que le serveur tait ne s\'affiche pas ; au singulier', (t) async {
    await monter(t, const ChiffresVip(periodeJours: 30, vipPublies: 42, vipAujourdhui: 1), sombre: true);
    expect(find.text('compétitions couvertes'), findsNothing);
    expect(find.text("pronostic VIP aujourd'hui"), findsOneWidget);
  });

  testWidgets('rien à annoncer, ou serveur muet : pas de bloc', (t) async {
    await monter(t, const ChiffresVip(periodeJours: 30));
    expect(find.byKey(const Key('chiffres-vip')), findsNothing);
    await monter(t, null);
    expect(find.byKey(const Key('chiffres-vip')), findsNothing);
  });

  testWidgets('écran étroit, texte agrandi : rien ne déborde', (t) async {
    t.view.physicalSize = const Size(320 * 2, 600 * 2);
    t.view.devicePixelRatio = 2;
    t.platformDispatcher.textScaleFactorTestValue = 1.8;
    addTearDown(t.view.reset);
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    await monter(t, const ChiffresVip(periodeJours: 30, vipPublies: 142, competitions: 12, vipAujourdhui: 13));
    expect(t.takeException(), isNull);
  });
}

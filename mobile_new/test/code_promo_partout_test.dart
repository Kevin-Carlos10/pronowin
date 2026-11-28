import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:pronowin/core/config/bookmaker_affiliation.dart';
import 'package:pronowin/core/theme/app_theme.dart';
import 'package:pronowin/shared/widgets/code_promo.dart';

import 'aides/banc_ecran.dart';

/// Le code promo du partenaire sur toutes les versions (7 novembre 2026,
/// décision du titulaire du compte) : carte, bandeau, page.
void main() {
  setUpAll(() async => preparerBanc());

  const promo = PromoPartenaire(code: 'PRONOWIN2026', nom: '1xBet',
      lien: 'https://reffpa.com/L?tag=d_1793663m_97c_&site=1793663&ad=97');

  Future<void> monter(WidgetTester t, Widget ecran, {PromoPartenaire? valeur = promo, double echelle = 1}) async {
    t.view.physicalSize = const Size(720, 1800);
    t.view.devicePixelRatio = 2;
    t.platformDispatcher.textScaleFactorTestValue = echelle;
    addTearDown(t.view.reset);
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    await t.pumpWidget(ProviderScope(
      overrides: [...donneesCommunes(), promoPartenaireProvider.overrideWith((ref) async => valeur)],
      child: MaterialApp.router(theme: AppTheme.dark, routerConfig: GoRouter(routes: [
        GoRoute(path: '/', builder: (_, _) => Scaffold(body: ListView(padding: const EdgeInsets.all(16), children: [ecran]))),
        GoRoute(path: '/code-promo', builder: (_, _) => const PageCodePromo()),
        GoRoute(path: '/parametres/jeu-responsable', builder: (_, _) => const Text('JEU RESPONSABLE')),
      ])),
    ));
    await t.pump();
    await t.pump();
  }

  testWidgets('bandeau : le code, « Copier » remplit le presse-papiers', (t) async {
    String? copie;
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (c) async {
      if (c.method == 'Clipboard.setData') copie = (c.arguments as Map)['text'] as String;
      return null;
    });
    addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await monter(t, const BandeauCodePromo());
    expect(find.text('PRONOWIN2026'), findsOneWidget);
    expect(find.text('Bonus 1xBet avec notre code promo'), findsOneWidget);
    await t.tap(find.byTooltip('Copier le code'));
    await t.pump();
    expect(copie, 'PRONOWIN2026');
  });

  testWidgets('bandeau → page : le code, les étapes, « Ouvrir 1xBet », la mention 18+ et le jeu responsable', (t) async {
    await monter(t, const BandeauCodePromo());
    await t.tap(find.byKey(const Key('bandeau-code-promo')));
    await t.pumpAndSettle();
    expect(find.text('Code promo 1xBet'), findsOneWidget);
    expect(find.byKey(const Key('code-promo-texte')), findsOneWidget);
    expect(find.text('Saisis le code PRONOWIN2026 dans le champ « code promo ».'), findsOneWidget);
    expect(find.byKey(const Key('ouvrir-partenaire')), findsOneWidget);
    expect(find.text(BookmakerAffiliation.mention), findsOneWidget);
    await t.tap(find.text('Jeu responsable'));
    await t.pumpAndSettle();
    expect(find.text('JEU RESPONSABLE'), findsOneWidget);
  });

  testWidgets('carte de l\'accueil, et sans lien : pas de bouton « Ouvrir »', (t) async {
    await monter(t, const CarteCodePromo(), valeur: const PromoPartenaire(code: 'PRONOWIN2026', nom: '', lien: ''));
    expect(find.text('PRONOWIN2026'), findsOneWidget);
    expect(find.text('À saisir lors de ton inscription sur notre partenaire.'), findsOneWidget);
    await t.tap(find.byKey(const Key('carte-code-promo')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('ouvrir-partenaire')), findsNothing);
  });

  testWidgets('aucun code configuré : rien du tout', (t) async {
    await monter(t, const Column(children: [BandeauCodePromo(), CarteCodePromo()]), valeur: null);
    expect(find.byType(InkWell), findsNothing);
  });

  for (final echelle in [1.6, 2.0]) {
    testWidgets('texte ×$echelle : bandeau, carte et page sans débordement', (t) async {
      await monter(t, const Column(children: [BandeauCodePromo(), CarteCodePromo()]), echelle: echelle);
      expect(t.takeException(), isNull);
      await t.tap(find.byKey(const Key('carte-code-promo')));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  }
}

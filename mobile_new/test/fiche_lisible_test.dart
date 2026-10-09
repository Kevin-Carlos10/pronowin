// Fiche de match lisible (revue du 9 octobre 2026) : critères du modèle en
// clair avec leur explication, vote en pourcentage, vrais logos WhatsApp et
// Telegram.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/core/theme/app_theme.dart';
import 'package:pronowin/features/pronostics/presentation/pages/match_detail_page.dart';
import 'package:pronowin/features/pronostics/presentation/providers/pronostics_provider.dart';
import 'package:pronowin/features/pronostics/presentation/widgets/comments_section.dart';
import 'package:pronowin/l10n/app_strings.dart';
import 'package:pronowin/shared/widgets/logo_marque.dart';

import 'aides/banc_ecran.dart';

final _analyse = MatchInsights.fromJson({
  'home_team': 'Borussia Dortmund', 'away_team': 'Werder Bremen',
  'percent': {'home': 63, 'draw': 22, 'away': 15},
  'comparisons': [
    {'label': 'Forme', 'home': 63, 'away': 37},
    {'label': 'Attaque', 'home': 80, 'away': 20},
    {'label': 'Défense', 'home': 50, 'away': 50},
    {'label': 'Confrontations', 'home': 71, 'away': 29},
    {'label': 'Poisson', 'home': 100, 'away': 0},
    {'label': 'Synthèse', 'home': 72, 'away': 28},
  ],
});

Widget _app(Widget enfant, {String langue = 'fr', List<Override> surcharges = const []}) =>
    ProviderScope(
      overrides: [...donneesCommunes(), ...surcharges],
      child: MaterialApp(
        theme: AppTheme.light,
        locale: Locale(langue),
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: const [
          AppStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(1.8), disableAnimations: true),
          child: child!),
        home: Scaffold(body: SingleChildScrollView(
          padding: const EdgeInsets.all(16), child: enfant)),
      ),
    );

Future<void> _monter(WidgetTester t, Widget w) async {
  t.view.physicalSize = const Size(640, 2400);
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  await t.pumpWidget(w);
  for (var i = 0; i < 5; i++) { await t.pump(const Duration(milliseconds: 100)); }
}

void main() {
  setUpAll(preparerBanc);

  group('critères du modèle', () {
    for (final langue in ['fr', 'en']) {
      testWidgets('en clair, avec leur explication — $langue, 320 px, texte 180 %', (t) async {
        await _monter(t, _app(analyseModeleSeule('m'), langue: langue, surcharges: [
          matchInsightsProvider('m').overrideWith((ref) async => _analyse),
        ]));
        final fr = langue == 'fr';
        // « Poisson 100/0 » ne disait rien à un parieur.
        expect(find.text('Poisson'), findsNothing);
        expect(find.text(fr ? 'Simulation des buts' : 'Goal simulation'), findsOneWidget);
        expect(find.text(fr ? 'Face à face' : 'Head-to-head'), findsOneWidget);
        expect(find.text(fr ? 'Forme récente' : 'Recent form'), findsOneWidget);
        expect(find.text(fr ? '80 %' : '80%'), findsOneWidget);
        // La synthèse reste le verdict, pas une barre de plus.
        expect(find.text(fr ? '72 %' : '72%'), findsNothing);

        await t.tap(find.byKey(const Key('criteres-aide')));
        for (var i = 0; i < 5; i++) { await t.pump(const Duration(milliseconds: 100)); }
        expect(find.text(fr ? 'Comprendre les critères' : 'Understand the criteria'), findsOneWidget);
        expect(find.textContaining(fr ? 'loi de Poisson' : 'Poisson distribution'), findsOneWidget);
        expect(t.takeException(), isNull);
      });
    }
  });

  group('vote de la communauté', () {
    testWidgets('la part d\'accord se lit en clair, au-dessus de la barre', (t) async {
      await _monter(t, _app(barreDeVoteSeule(
        const PronosticVoteData(agree: 102, disagree: 18, total: 120, userVote: 'AGREE'))));
      expect(find.text('85 % d\'accord'), findsOneWidget);
      expect(find.text('120 votes'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('en anglais, le bouton est traduit', (t) async {
      await _monter(t, _app(barreDeVoteSeule(
        const PronosticVoteData(agree: 1, disagree: 0, total: 1)), langue: 'en'));
      expect(find.text('Agree'), findsOneWidget);
      expect(find.text("D'accord"), findsNothing);
      expect(find.text('100% agree'), findsOneWidget);
      expect(find.text('1 vote'), findsOneWidget);
    });
  });

  group('vrais logos WhatsApp et Telegram', () {
    testWidgets('dessinés en SVG, aux couleurs des marques', (t) async {
      await t.pumpWidget(const Directionality(
        textDirection: TextDirection.ltr,
        child: Row(children: [LogoMarque(Marque.whatsapp), LogoMarque(Marque.telegram)])));
      expect(find.byType(SvgPicture), findsNWidgets(2));
      expect(Marque.whatsapp.couleur, const Color(0xFF25D366));
      expect(Marque.telegram.couleur, const Color(0xFF26A5E4));
    });

    // Les trois endroits qui ouvrent WhatsApp ou Telegram : plus aucune
    // icône générique (bulle, avion de papier) à côté de leur nom.
    for (final f in [
      'lib/features/pronostics/presentation/widgets/comments_section.dart',
      'lib/features/pronostics/presentation/pages/match_detail/partage.dart',
      'lib/features/parametres/presentation/pages/parametres_page.dart',
    ]) {
      test('logos réels : $f', () {
        final src = File(f).readAsStringSync();
        expect(src, contains('Marque.whatsapp'));
        expect(src, contains('Marque.telegram'));
        expect(RegExp(r"Icons\.(chat|send)_rounded,\s*label: '(WhatsApp|Telegram)'").hasMatch(src), isFalse);
        expect(RegExp(r"icone: Icons\.(chat|send)_rounded").hasMatch(src), isFalse);
      });
    }
  });
}

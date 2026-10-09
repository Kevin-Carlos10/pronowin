import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/core/theme/app_theme.dart';
import 'package:pronowin/features/pronostics/data/models/match_model.dart';
import 'package:pronowin/features/pronostics/presentation/pages/match_detail_page.dart';
import 'package:pronowin/features/pronostics/presentation/providers/fiche_match_provider.dart';
import 'package:pronowin/l10n/app_strings.dart';
import 'aides/banc_ecran.dart';

MatchRecent recent(
  String adversaire,
  int pour,
  int contre, {
  bool domicile = true,
}) => MatchRecent(
  date: DateTime(2026, 9, 19),
  adversaire: adversaire,
  domicile: domicile,
  butsPour: pour,
  butsContre: contre,
  issue: pour > contre
      ? IssueMatch.victoire
      : pour < contre
      ? IssueMatch.defaite
      : IssueMatch.nul,
);

final forme = FormeRecente(
  [
    recent('VfB Stuttgart', 1, 0, domicile: false),
    recent('SC Paderborn 07', 3, 0),
    recent('Villarreal', 3, 2),
    recent('1899 Hoffenheim', 3, 2, domicile: false),
    recent('HEBC', 5, 0, domicile: false),
    recent('Sixième match', 9, 9),
  ],
  [
    recent('FC Twente', 0, 7, domicile: false),
    recent('Augsburg', 3, 2),
    recent('Cologne', 1, 1, domicile: false),
    recent('RB Leipzig', 3, 1),
    recent('Fribourg', 1, 4, domicile: false),
  ],
);

Future<void> monter(
  WidgetTester t, {
  required ThemeData theme,
  double largeur = 402,
  double echelle = 1.2,
  String langue = 'fr',
  FormeRecente? data,
  String status = 'upcoming',
}) async {
  t.view.physicalSize = Size(largeur * 2, 850 * 2);
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  final match = MatchModel.fromJson({
    'id': 'm',
    'home_team': 'Borussia Dortmund',
    'away_team': 'Werder Bremen',
    'status': status,
    'league': 'Bundesliga',
    'match_date': '2026-10-09T18:30:00Z',
    'home_form_points': 0,
    'away_form_points': 0,
  });
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        formeRecenteProvider('m').overrideWith((ref) async => data ?? forme),
      ],
      child: MaterialApp(
        theme: theme,
        locale: Locale(langue),
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: const [
          AppStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(echelle)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: RepaintBoundary(
                key: const Key('capture-forme'),
                child: formeRecenteSeule(match),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  setUpAll(preparerBanc);
  for (final theme in [AppTheme.light, AppTheme.dark]) {
    for (final langue in ['fr', 'en']) {
      testWidgets('scores et colonnes ${theme.brightness} $langue', (t) async {
        final semantics = t.ensureSemantics();
        await monter(t, theme: theme, langue: langue);
        final gauche = find.byKey(const Key('forme-domicile-score-0'));
        final droite = find.byKey(const Key('forme-exterieur-score-0'));
        expect(t.getTopLeft(gauche).dy, t.getTopLeft(droite).dy);
        expect(t.getTopLeft(gauche).dx, lessThan(t.getTopLeft(droite).dx));
        expect(find.text('0 - 1'), findsOneWidget);
        expect(find.text('7 - 0'), findsOneWidget);
        expect(find.text('1 - 1'), findsOneWidget);
        expect(find.text('9 - 9'), findsNothing); // cinq derniers seulement
        final couleur =
            (t
                        .widget<Container>(
                          find
                              .descendant(
                                of: gauche,
                                matching: find.byType(Container),
                              )
                              .first,
                        )
                        .decoration!
                    as BoxDecoration)
                .color;
        expect(couleur, AppColors.fondSucces); // victoire extérieure
        expect(
          find.bySemanticsLabel(
            RegExp(
              langue == 'fr'
                  ? 'VfB Stuttgart 0 – 1 Borussia Dortmund.*Victoire'
                  : 'VfB Stuttgart 0 – 1 Borussia Dortmund.*Win',
            ),
          ),
          findsOneWidget,
        );
        expect(t.takeException(), isNull);
        semantics.dispose();
        if (const bool.fromEnvironment('CAPTURE_FORME') && langue == 'fr') {
          final boundary = t.renderObject<RenderRepaintBoundary>(
            find.byKey(const Key('capture-forme')),
          );
          await t.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 2);
            final bytes = (await image.toByteData(
              format: ui.ImageByteFormat.png,
            ))!;
            final file = File(
              'build/apercus/forme_${theme.brightness.name}.png',
            );
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes.buffer.asUint8List());
            image.dispose();
          });
        }
      });
    }
    testWidgets('320 px, texte 180 %, scores longs ${theme.brightness}', (
      t,
    ) async {
      await monter(
        t,
        theme: theme,
        largeur: 320,
        echelle: 1.8,
        data: FormeRecente([
          recent('Adversaire avec un nom particulièrement long', 10, 12),
        ], []),
      );
      expect(find.text('10 - 12'), findsOneWidget);
      expect(
        find.text('Aucun match récent connu pour cette équipe.'),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
      await t.tap(find.byKey(const Key('forme-domicile')));
      await t.pumpAndSettle();
      expect(find.text('10-12'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }
  testWidgets('aucun résultat fictif si vide ou match terminé', (t) async {
    await monter(t, theme: AppTheme.light, data: const FormeRecente([], []));
    expect(find.byKey(const Key('forme-comparaison')), findsNothing);
    await monter(t, theme: AppTheme.light, status: 'finished');
    expect(find.byKey(const Key('forme-comparaison')), findsNothing);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronowin/core/theme/app_theme.dart';
import 'package:pronowin/features/pronostics/data/models/match_model.dart';
import 'package:pronowin/features/pronostics/presentation/pages/match_detail_page.dart';
import 'package:pronowin/features/pronostics/presentation/providers/pronostics_provider.dart';
import 'package:pronowin/features/pronostics/presentation/widgets/fil_evenements.dart';
import 'package:pronowin/l10n/app_strings.dart';

import 'aides/banc_ecran.dart';

/// Deux défauts vus sur des captures du 27 novembre 2026, sur des matchs
/// terminés.
void main() {
  setUpAll(preparerBanc);

  group('le bandeau « Pronostic gagnant »', () {
    /// La fiche d'un match terminé dont le pronostic a gagné.
    Future<void> monter(WidgetTester t, Map<String, Object> preferences) async {
      SharedPreferences.setMockInitialValues({'pseudo_nudge_dismissed': true, ...preferences});
      t.view.physicalSize = const Size(390 * 2, 844 * 2);
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      final match = MatchModel.fromJson({
        ...pronoApi('2', status: 'finished', dans: const Duration(hours: -3)),
        'result': 'WIN', 'home_score': 3, 'away_score': 3,
      });
      await t.pumpWidget(ProviderScope(
        overrides: [
          ...donneesCommunes(),
          matchDetailProvider('2').overrideWith((ref) async => match),
        ],
        child: MaterialApp.router(
          routerConfig: GoRouter(
            routes: [GoRoute(path: '/', builder: (_, _) => const MatchDetailPage(matchId: '2'))],
            errorBuilder: (_, _) => const Scaffold(),
          ),
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
      for (var i = 0; i < 30; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    /// L'opacité effective d'un widget : le produit de ses `Opacity`.
    double opacite(WidgetTester t, Finder f) {
      var o = 1.0;
      for (final e in find.ancestor(of: f, matching: find.byType(Opacity)).evaluate()) {
        o *= (e.widget as Opacity).opacity;
      }
      return o;
    }

    testWidgets('déjà célébré : le libellé et la coche se voient', (t) async {
      // C'était le défaut : l'animation ne se rejouait pas, mais restait à
      // son point de départ — une barre verte vide.
      await monter(t, {'celebrated_win_2': true});
      final libelle = find.text('Pronostic gagnant');
      expect(libelle, findsOneWidget);
      expect(opacite(t, libelle), 1.0);
      expect(opacite(t, find.byIcon(Icons.check_circle_rounded)), 1.0);
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(minutes: 1));
    });

    testWidgets('première consultation : célébré, puis affiché pour de bon', (t) async {
      await monter(t, const {});
      expect(opacite(t, find.text('Pronostic gagnant')), 1.0);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('celebrated_win_2'), isTrue);
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(minutes: 1));
    });
  });

  group('un buteur dans l\'en-tête', () {
    test('les noms possibles, du plus complet au plus court', () {
      expect(variantesNomButeur('Morgan Gibbs-White'), ['M. Gibbs-White', 'Gibbs-White']);
      expect(variantesNomButeur('Kevin De Bruyne'), ['K. De Bruyne', 'De Bruyne']);
      expect(variantesNomButeur('Rodri'), ['Rodri']);
    });

    Future<String> nomAffiche(WidgetTester t, double largeur) async {
      await t.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: SizedBox(
        width: largeur,
        child: const LigneButeur(joueur: 'Morgan Gibbs-White', minutes: "51' (pen.), 72'",
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
      )))));
      return t.widget<Text>(find.byKey(const Key('nom-buteur'))).data!;
    }

    testWidgets('à l\'étroit : le nom de famille, pas « M. ... »', (t) async {
      expect(await nomAffiche(t, 125), 'Gibbs-White');
      // Les minutes restent entières.
      expect(t.widget<Text>(find.byKey(const Key('minutes-buteur'))).data, " 51' (pen.), 72'");
    });

    testWidgets('avec la place : l\'initiale et le nom', (t) async {
      expect(await nomAffiche(t, 420), 'M. Gibbs-White');
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:pronowin/core/theme/app_theme.dart';
import 'package:pronowin/features/pronostics/presentation/pages/historique_page.dart';
import 'package:pronowin/l10n/app_strings.dart';

import 'aides/banc_ecran.dart';

/// L'historique, en français et sans débordement.
///
/// Vu sur iPhone : des filtres « WIN » et « LOSS », un « LOSS » rouge sur un
/// pari remboursé, et des libellés longs qui sortaient de la carte, cote
/// comprise (« … Mikel Oyarz », « @ 1.6 »).
void main() {
  setUpAll(preparerBanc);

  Map<String, dynamic> entree(String id, String? resultat, String libelle) => {
        'id': id, 'result': resultat, 'predictionLabel': libelle, 'oddsRecommended': 1.81,
        'match': {
          'homeTeam': 'Spain', 'awayTeam': 'Czechia', 'league': 'UEFA Nations League',
          'homeScore': 3, 'awayScore': 1, 'matchDate': DateTime.now().subtract(const Duration(days: 2)).toIso8601String(),
        },
      };

  Future<void> monter(WidgetTester t, {double largeur = 360, double hauteur = 800, double echelle = 1,
      List<Map<String, dynamic>>? entrees}) async {
    t.view.physicalSize = Size(largeur * 2, hauteur * 2);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(
      overrides: [
        ...donneesCommunes(),
        historiqueProvider.overrideWith((ref, jours) async => entrees ?? [
              entree('3', 'PUSH', 'Handicap asiatique : Spain -1'),
              entree('1', 'WIN', 'Joueur va marquer un but à tout moment : Mikel Oyarzabal'),
              entree('2', 'LOSS', 'Spain gagne'),
            ]),
      ],
      child: MaterialApp.router(
        routerConfig: GoRouter(routes: [
          GoRoute(path: '/', builder: (_, _) => const HistoriquePage()),
          GoRoute(path: '/compte/activer-premium', builder: (_, _) => const Scaffold(body: Text('OFFRE PREMIUM'))),
        ]),
        theme: AppTheme.light,
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
          child: child!,
        ),
      ),
    ));
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));
  }

  testWidgets('des mots français, et un remboursé qui n\'est pas une défaite', (t) async {
    // Assez haut pour que les trois lignes soient construites.
    await monter(t, largeur: 390, hauteur: 1600);
    expect(find.textContaining('WIN'), findsNothing);
    expect(find.textContaining('LOSS'), findsNothing);
    expect(find.text('Gagné'), findsOneWidget);
    expect(find.text('Perdu'), findsOneWidget);
    expect(find.text('Remboursé'), findsOneWidget);
    expect(find.textContaining('Gagnés'), findsWidgets);   // le filtre
    await t.pumpWidget(const SizedBox.shrink());
  });

  // Décision de l'utilisateur du 17 octobre 2026 : un pronostic Premium reste
  // verrouillé pour un non-abonné après le match. Le serveur envoie
  // `locked: true` et « Pronostic Premium » à la place du choix ; la ligne
  // garde son résultat, gagné comme perdu, et mène vers l'offre.
  testWidgets('Premium verrouillé : résultat visible, choix masqué, mène à l’offre', (t) async {
    Map<String, dynamic> verrouillee(String id, String resultat) => {
          ...entree(id, resultat, 'Pronostic Premium'),
          'locked': true, 'isPremium': true, 'oddsRecommended': null,
        };
    await monter(t, largeur: 390, hauteur: 1600, entrees: [
      verrouillee('1', 'WIN'),
      verrouillee('2', 'LOSS'),
      entree('3', 'WIN', 'Spain gagne'),
    ]);
    expect(find.byKey(const Key('historique-premium-verrouille')), findsNWidgets(2));
    expect(find.text('Pronostic Premium'), findsNWidgets(2));
    expect(find.text('Gagné'), findsNWidgets(2));
    expect(find.text('Perdu'), findsOneWidget, reason: 'le Premium perdu reste affiché');
    expect(find.textContaining('@ '), findsOneWidget, reason: 'aucune cote sur une ligne verrouillée');
    // Le pronostic gratuit garde son choix (nom d'équipe traduit).
    expect(find.textContaining(' gagne'), findsOneWidget);

    await t.tap(find.byKey(const Key('historique-premium-verrouille')).first);
    await t.pumpAndSettle();
    expect(find.text('OFFRE PREMIUM'), findsOneWidget);
    await t.pumpWidget(const SizedBox.shrink());
  });

  for (final echelle in [1.0, 1.4]) {
    testWidgets('un libellé long ne déborde pas · texte ${(echelle * 100).round()} %', (t) async {
      await monter(t, largeur: 320, echelle: echelle);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
    });
  }
}

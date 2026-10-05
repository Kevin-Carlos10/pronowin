import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pronowin/core/theme/app_theme.dart';
import 'package:pronowin/features/pronostics/presentation/pages/match_detail_page.dart';
import 'package:pronowin/features/pronostics/presentation/providers/pronostics_provider.dart';
import 'package:pronowin/l10n/catalog_en.dart';

import 'aides/banc_ecran.dart';

/// Sous le classement, les quatre palmarès que l'API publie : buteurs,
/// passeurs, cartons jaunes et rouges. Seuls les buteurs étaient affichés.
void main() {
  setUpAll(preparerBanc);

  TopScorer j(int rang, String nom, {int buts = 0, int passes = 0, int jaunes = 0, int rouges = 0}) =>
      TopScorer(rank: rang, name: nom, team: 'RC Lens', goals: buts, assists: passes,
          penalties: 0, appearances: 8, yellowCards: jaunes, redCards: rouges);

  final donnees = <Palmares, List<TopScorer>>{
    Palmares.buteurs:  [j(1, 'Wesley Saïd', buts: 7, passes: 2), j(2, 'Florian Sotoca', buts: 5)],
    Palmares.passeurs: [j(1, 'Florian Thauvin', passes: 6, buts: 1)],
    Palmares.jaunes:   [j(1, 'Andy Diouf', jaunes: 5), j(2, 'Kevin Danso', jaunes: 4, rouges: 1)],
    // Aucun carton rouge cette saison : rien que des zéros.
    Palmares.rouges:   [j(1, 'Personne', rouges: 0)],
  };

  Future<void> monter(WidgetTester t, {double echelle = 1, double largeur = 390,
      Map<Palmares, List<TopScorer>>? avec}) async {
    t.view.physicalSize = Size(largeur * 2, 1400);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    final d = avec ?? donnees;
    await t.pumpWidget(ProviderScope(
      overrides: [
        topScorersProvider.overrideWith((ref, p) async => d[p.palmares] ?? const []),
      ],
      child: MaterialApp(
        theme: AppTheme.dark,
        home: MediaQuery(
          data: MediaQueryData(size: Size(largeur, 700), textScaler: TextScaler.linear(echelle)),
          child: Scaffold(body: SingleChildScrollView(child: palmaresCompetitionSeul('FL1'))),
        ),
      ),
    ));
    await t.pump();
    await t.pump();
  }

  testWidgets('les buteurs d\'abord, puis chaque palmarès au toucher', (t) async {
    await monter(t);
    expect(find.text('Meilleurs joueurs de la compétition'), findsOneWidget);
    expect(find.text('Wesley Saïd'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);

    await t.tap(find.byKey(const Key('palmares-passeurs')));
    await t.pump(); await t.pump();
    expect(find.text('Florian Thauvin'), findsOneWidget);
    expect(find.text('6'), findsOneWidget);
    expect(find.text('Wesley Saïd'), findsNothing);

    await t.tap(find.byKey(const Key('palmares-jaunes')));
    await t.pump(); await t.pump();
    expect(find.text('Andy Diouf'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
  });

  testWidgets('une liste de zéros n\'est pas un classement', (t) async {
    await monter(t);
    await t.tap(find.byKey(const Key('palmares-rouges')));
    await t.pump(); await t.pump();
    expect(find.text('Personne'), findsNothing);
    expect(find.text('Pas encore de données pour ce classement cette saison.'), findsOneWidget);
  });

  testWidgets('sans buteurs publiés, la carte ne s\'affiche pas', (t) async {
    await monter(t, avec: {});
    expect(find.text('Meilleurs joueurs de la compétition'), findsNothing);
  });

  for (final largeur in [320.0, 390.0]) {
    testWidgets('texte à 180 % · ${largeur.toInt()} px : rien ne déborde', (t) async {
      await monter(t, echelle: 1.8, largeur: largeur);
      await t.tap(find.byKey(const Key('palmares-jaunes')));
      await t.pump(); await t.pump();
      expect(t.takeException(), isNull);
    });
  }

  test('les nouveaux textes sont traduits', () {
    for (final cle in [
      'Meilleurs joueurs de la compétition', 'Buteurs', 'Passeurs', 'Cartons jaunes', 'Cartons rouges',
      'Ce classement est momentanément indisponible.',
      'Pas encore de données pour ce classement cette saison.', '{arg0} m.',
    ]) {
      expect(englishMessages, contains(cle), reason: cle);
    }
  });
}

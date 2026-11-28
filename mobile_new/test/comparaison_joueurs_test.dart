import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:pronowin/core/theme/app_theme.dart';
import 'package:pronowin/features/joueurs/presentation/pages/comparaison_joueurs_page.dart';
import 'package:pronowin/features/joueurs/presentation/pages/fiche_joueur_page.dart';
import 'package:pronowin/features/joueurs/presentation/providers/fiche_joueur_provider.dart';
import 'package:pronowin/features/pronostics/presentation/providers/recherche_provider.dart';
import 'package:pronowin/features/pronostics/presentation/widgets/infos_joueurs.dart';

import 'aides/banc_ecran.dart';

/// Fiche joueur refaite et comparaison de deux joueurs (7 novembre 2026).
void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR');
    await preparerBanc();
  });

  const kane = FicheJoueur(id: 184, name: 'Harry Kane', season: 2026, age: 33, height: '188', weight: '86 kg',
    nationality: 'England',
    stats: [StatsCompetition(team: 'Bayern München', league: 'Bundesliga', position: 'Attacker',
      appearances: 9, minutes: 800, goals: 12, assists: 3, rating: 8.12, yellowCards: 1, passAccuracy: 78)]);
  const olise = FicheJoueur(id: 999, name: 'Michael Olise', season: 2026,
    stats: [StatsCompetition(team: 'Bayern München', league: 'Bundesliga', position: 'Midfielder',
      appearances: 9, minutes: 760, goals: 5, assists: 7, rating: 7.6, yellowCards: 0, passAccuracy: 84)]);

  Future<void> monter(WidgetTester t, Widget page, {double echelle = 1}) async {
    t.view.physicalSize = const Size(780, 3200);
    t.view.devicePixelRatio = 2;
    t.platformDispatcher.textScaleFactorTestValue = echelle;
    addTearDown(t.view.reset);
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    await t.pumpWidget(ProviderScope(
      overrides: [
        ...donneesCommunes(),
        ficheJoueurProvider.overrideWith((ref, id) async => id == 184 ? kane : olise),
        rechercheEquipesJoueursProvider.overrideWith((ref, terme) async => const ResultatsRecherche(joueurs: [
          JoueurTrouve(id: 184, nom: 'H. Kane'), JoueurTrouve(id: 999, nom: 'M. Olise', nationalite: 'France')])),
      ],
      child: MaterialApp(theme: AppTheme.dark, home: page),
    ));
    await t.pump();
    await t.pump();
  }

  testWidgets('fiche : note de la saison en pastille, cases d\'identité avec unités', (t) async {
    await monter(t, const FichePremier());
    expect(find.widgetWithText(PastilleNote, '8.1'), findsOneWidget);
    expect(find.text('188 cm'), findsOneWidget, reason: 'la taille sans unité en reçoit une');
    expect(find.text('86 kg'), findsOneWidget);
    expect(find.text('33 ans'), findsOneWidget);
    expect(find.byKey(const Key('comparer-joueur')), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('comparer : choisir l\'autre joueur (lui-même exclu), puis la saison côte à côte', (t) async {
    await monter(t, const FichePremier());
    await t.tap(find.byKey(const Key('comparer-joueur')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('recherche-comparaison')), 'oli');
    await t.pumpAndSettle();
    expect(find.byKey(const Key('choix-joueur-184')), findsNothing, reason: 'pas avec lui-même');
    await t.tap(find.byKey(const Key('choix-joueur-999')));
    await t.pumpAndSettle();

    expect(find.byType(ComparaisonJoueursPage), findsOneWidget);
    expect(find.text('Harry Kane'), findsOneWidget);
    expect(find.text('Michael Olise'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(find.text('84 %'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('comparaison, texte agrandi ×1,8 : rien ne déborde', (t) async {
    await monter(t, const ComparaisonJoueursPage(idA: 184, idB: 999), echelle: 1.8);
    expect(t.takeException(), isNull);
  });
}

/// La fiche de Kane, comme le routeur l'ouvre.
class FichePremier extends StatelessWidget {
  const FichePremier({super.key});
  @override
  Widget build(BuildContext context) => const FicheJoueurPage(id: 184);
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:pronowin/core/theme/app_theme.dart';
import 'package:pronowin/features/pronostics/presentation/pages/search_page.dart';
import 'package:pronowin/features/pronostics/presentation/providers/pronostics_provider.dart';
import 'package:pronowin/features/pronostics/presentation/providers/recherche_provider.dart';

import 'aides/banc_ecran.dart';

/// La recherche trouve aussi les équipes et les joueurs, et ouvre leur fiche
/// (7 novembre 2026, comme Sofascore et FotMob).
void main() {
  setUpAll(() async => preparerBanc());

  Future<void> taper(WidgetTester t, {required ResultatsRecherche autres}) async {
    await t.pumpWidget(ProviderScope(
      overrides: [
        ...donneesCommunes(),
        rechercheMatchsProvider.overrideWith((ref, terme) async => const []),
        rechercheEquipesJoueursProvider.overrideWith((ref, terme) async => autres),
      ],
      child: MaterialApp.router(
        theme: AppTheme.dark,
        routerConfig: GoRouter(routes: [
          GoRoute(path: '/', builder: (_, _) => const SearchPage()),
          GoRoute(path: '/equipes/:id', builder: (_, e) => Text('EQUIPE ${e.pathParameters['id']}')),
          GoRoute(path: '/joueurs/:id', builder: (_, e) => Text('JOUEUR ${e.pathParameters['id']}')),
        ]),
      ),
    ));
    await t.enterText(find.byType(TextField), 'bayer');
    await t.pumpAndSettle();
  }

  testWidgets('équipes et joueurs, chacun ouvre sa fiche', (t) async {
    await taper(t, autres: const ResultatsRecherche(
      equipes: [EquipeTrouvee(id: 157, nom: 'Bayern München', competition: 'BL1')],
      joueurs: [JoueurTrouve(id: 184, nom: 'H. Kane', poste: 'Attacker', nationalite: 'England')],
    ));
    expect(find.text('ÉQUIPES'), findsOneWidget);
    expect(find.text('JOUEURS'), findsOneWidget);
    expect(find.text('Attaquant · England'), findsOneWidget);
    expect(find.text('Aucun résultat pour "bayer"'), findsNothing,
        reason: 'pas de match, mais une équipe et un joueur');

    await t.tap(find.byKey(const Key('equipe-157')));
    await t.pumpAndSettle();
    expect(find.text('EQUIPE 157'), findsOneWidget);
  });

  testWidgets('un joueur ouvre sa fiche', (t) async {
    await taper(t, autres: const ResultatsRecherche(joueurs: [JoueurTrouve(id: 184, nom: 'H. Kane')]));
    await t.tap(find.byKey(const Key('joueur-184')));
    await t.pumpAndSettle();
    expect(find.text('JOUEUR 184'), findsOneWidget);
  });

  testWidgets('rien du tout : le message d\'absence', (t) async {
    await taper(t, autres: ResultatsRecherche.vide);
    expect(find.text('Aucun résultat pour "bayer"'), findsOneWidget);
  });
}

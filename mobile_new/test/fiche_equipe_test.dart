import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:pronowin/core/theme/app_theme.dart';
import 'package:pronowin/features/equipes/presentation/pages/fiche_equipe_page.dart';
import 'package:pronowin/features/equipes/presentation/providers/fiche_equipe_provider.dart';
import 'package:pronowin/l10n/catalog_en.dart';

import 'aides/banc_ecran.dart';

/// La fiche d'une équipe : un écusson de la fiche du match s'ouvre désormais
/// sur le club, son bilan, son stade, son entraîneur et son effectif.
void main() {
  setUpAll(preparerBanc);

  test("l'identifiant de l'équipe se lit dans l'adresse de son logo", () {
    expect(idEquipeDepuisLogo('https://media.api-sports.io/football/teams/116.png'), 116);
    expect(idEquipeDepuisLogo('https://crests.football-data.org/524.svg'), isNull);
    expect(idEquipeDepuisLogo(null), isNull);
  });

  const lens = FicheEquipe(
    id: 116, name: 'Lens', country: 'France', founded: 1906, season: 2026,
    logo: 'https://media.api-sports.io/football/teams/116.png',
    venue: (name: 'Stade Bollaert-Delelis', city: 'Lens', capacity: 38223, image: null),
    coach: (name: 'Pierre Sage', age: 47, nationality: 'France', photo: null),
    bilan: BilanSaison(forme: 'LDWWWDW', systeme: '3-4-3', joues: 8, victoires: 5, nuls: 2, defaites: 1,
        cleanSheets: 4, sansMarquer: 1, butsPour: '1.9', butsContre: '0.8'),
    squad: [
      JoueurEffectif(id: 11, name: 'Robin Risser', number: 40, position: 'Goalkeeper', age: 22),
      JoueurEffectif(id: 12, name: 'Kevin Danso', number: 4, position: 'Defender', age: 27),
      JoueurEffectif(id: 13, name: 'Wesley Saïd', number: 22, position: 'Attacker', age: 31),
    ],
  );

  Future<void> monter(WidgetTester t, {double echelle = 1, double largeur = 390, FicheEquipe f = lens}) async {
    t.view.physicalSize = Size(largeur * 2, 1900 * 2);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    final routeur = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, _) => MediaQuery(
        data: MediaQueryData(size: Size(largeur, 1900), textScaler: TextScaler.linear(echelle)),
        child: const FicheEquipePage(id: 116, apercu: (nom: 'Lens', logo: null, competition: 'FL1')))),
      GoRoute(path: '/joueurs/:id', builder: (_, s) => Scaffold(body: Text('joueur ${s.pathParameters['id']}'))),
    ]);
    await t.pumpWidget(ProviderScope(
      overrides: [ficheEquipeProvider.overrideWith((ref, p) async {
        // La compétition d'où l'on vient est transmise : c'est elle qui donne le bilan.
        expect(p.competition, 'FL1');
        return f;
      })],
      child: MaterialApp.router(theme: AppTheme.dark, routerConfig: routeur),
    ));
    await t.pump();
    await t.pump();
  }

  testWidgets('le club, son bilan, son stade, son entraîneur, son effectif', (t) async {
    await monter(t);
    expect(find.text('France · fondé en 1906'), findsOneWidget);
    expect(find.text('Saison 2026-27'), findsOneWidget);
    expect(find.text('5'), findsWidgets);
    expect(find.text('3-4-3'), findsOneWidget);
    expect(find.text('Stade Bollaert-Delelis'), findsOneWidget);
    expect(find.textContaining('38'), findsWidgets);
    expect(find.text('Pierre Sage'), findsOneWidget);
    expect(find.text('GARDIENS'), findsOneWidget);
    expect(find.text('Wesley Saïd'), findsOneWidget);
  });

  testWidgets('un joueur de l\'effectif ouvre sa fiche', (t) async {
    await monter(t);
    await t.ensureVisible(find.text('Wesley Saïd'));
    await t.tap(find.text('Wesley Saïd'));
    await t.pumpAndSettle();
    expect(find.text('joueur 13'), findsOneWidget);
  });

  for (final largeur in [320.0, 390.0]) {
    testWidgets('texte à 180 % · ${largeur.toInt()} px : rien ne déborde', (t) async {
      await monter(t, echelle: 1.8, largeur: largeur);
      expect(t.takeException(), isNull);
    });
  }

  test('les textes de la fiche équipe sont traduits', () {
    for (final cle in ['Fiche équipe', 'Effectif', 'Entraîneur', 'Stade', 'Système le plus utilisé',
        'Matchs sans encaisser', "ouvrir la fiche de l'équipe", '{arg0} places']) {
      expect(englishMessages, contains(cle), reason: cle);
    }
  });
}

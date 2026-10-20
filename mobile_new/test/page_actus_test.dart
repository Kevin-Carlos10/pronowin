import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pronowin/core/widgets/team_logo_widget.dart';
import 'package:pronowin/features/accueil/presentation/providers/accueil_provider.dart';
import 'package:pronowin/features/actualites/actualites.dart';
import 'package:pronowin/features/actualites/page_actus.dart';
import 'package:pronowin/features/actualites/page_article.dart';
import 'package:pronowin/shared/providers/favoris_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// La page Actus au modèle de FotMob, la page d'un article, et le badge des
/// non-lues de Compte (20 octobre 2026).
class _Suivis extends FavorisNotifier {
  _Suivis(this.ids);
  final Set<String> ids;
  @override
  Future<EtatFavoris> build() async => EtatFavoris(matchIds: ids);
}

final _actus = <Map<String, dynamic>>[
  {'id': 'rss_1', 'titre': 'Mercato : un transfert record se prépare cet hiver', 'resume': 'Résumé du flux.',
   'categorie': 'RMC Sport', 'source': 'RMC Sport', 'image_url': null, 'source_url': 'https://rmcsport.bfmtv.com/a',
   'created_at': DateTime.now().subtract(const Duration(minutes: 30)).toUtc().toIso8601String(), 'from_rss': true},
  {'id': 'resume_r1', 'titre': "Marseille s'impose largement chez Angers (2-5)",
   'resume': "Score à la mi-temps : 1-2.\n\nButs — Angers : Rao-Lisoa (14').",
   'categorie': 'Ligue 1', 'image_url': null, 'source_url': null,
   'created_at': DateTime.now().subtract(const Duration(hours: 3)).toUtc().toIso8601String(), 'from_rss': false,
   'type': 'resume_match', 'match_id': 'm-om', 'score': '2-5',
   'logo_domicile': 'https://media.api-sports.io/football/teams/77.png',
   'logo_exterieur': 'https://media.api-sports.io/football/teams/81.png'},
];

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<ProviderContainer> monter(WidgetTester t,
      {Set<String> suivis = const {}, Future<List<Map<String, dynamic>>>? chargement}) async {
    // Un téléphone (390 × 844) : à 800 px de large, la grande carte repousse
    // la suite hors de l'écran, et la liste ne la construit pas.
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final routeur = GoRouter(initialLocation: '/actualites', routes: [
      GoRoute(path: '/actualites', builder: (_, _) => const PageActus()),
      GoRoute(path: '/actualites/article', builder: (_, s) => PageArticle(news: s.extra as Map<String, dynamic>)),
      GoRoute(path: '/pronostics/:id', builder: (_, s) => Text('fiche ${s.pathParameters['id']}')),
      GoRoute(path: '/navigateur', builder: (_, s) => Text('nav ${(s.extra as Map)['url']}')),
    ]);
    final conteneur = ProviderContainer(overrides: [
      toutesActualitesProvider.overrideWith((ref) => chargement ?? Future.value(_actus)),
      favorisProvider.overrideWith(() => _Suivis(suivis)),
    ]);
    addTearDown(conteneur.dispose);
    await t.pumpWidget(UncontrolledProviderScope(container: conteneur,
      child: MaterialApp.router(routerConfig: routeur)));
    for (var i = 0; i < 10; i++) { await t.pump(const Duration(milliseconds: 100)); }
    return conteneur;
  }

  testWidgets('pendant le chargement : la forme de la page en gris', (t) async {
    await monter(t, chargement: Completer<List<Map<String, dynamic>>>().future);
    expect(find.byKey(const Key('actus-squelette')), findsOneWidget);
    expect(find.text('Actualités'), findsOneWidget);
  });

  testWidgets('onglets comme FotMob ; « Pour toi » ouvre sur Tendance, le match suivi en tête', (t) async {
    await monter(t, suivis: {'m-om'});
    for (final o in ['pour-toi', 'recent', 'resumes', 'medias']) {
      expect(find.byKey(Key('onglet-actus-$o')), findsOneWidget, reason: o);
    }
    // Aucun article de la rédaction : pas d'onglet vide.
    expect(find.byKey(const Key('onglet-actus-redaction')), findsNothing);
    expect(find.text('Tendance'), findsOneWidget);
    // Le résumé du match suivi passe devant l'article plus récent.
    final resume = t.getRect(find.byKey(const Key('actu-resume_r1')));
    final media = t.getRect(find.byKey(const Key('actu-rss_1')));
    expect(resume.top, lessThan(media.top));
    // Sans photo, un résumé montre les deux logos et le score.
    expect(find.byType(TeamLogoWidget), findsNWidgets(2));
    expect(find.text('2-5'), findsOneWidget);
    expect(find.textContaining('Il y a 3 h'), findsOneWidget);
  });

  testWidgets('onglet Médias : les seuls titres des médias', (t) async {
    await monter(t);
    // Comme chez FotMob, la barre d'onglets défile : « Médias » est hors champ.
    await t.ensureVisible(find.byKey(const Key('onglet-actus-medias')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('onglet-actus-medias')));
    await t.pumpAndSettle();
    expect(find.textContaining('Mercato'), findsOneWidget);
    expect(find.textContaining('Marseille'), findsNothing);
  });

  testWidgets("un résumé s'ouvre en page article, est marqué lu, et mène à la fiche du match", (t) async {
    final c = await monter(t);
    await t.tap(find.byKey(const Key('actu-resume_r1')));
    await t.pumpAndSettle();
    expect(find.byType(PageArticle), findsOneWidget);
    expect(find.text('Score à la mi-temps : 1-2.'), findsOneWidget);
    expect(find.text("Buts — Angers : Rao-Lisoa (14')."), findsOneWidget);
    expect(find.textContaining('PronoWin · Ligue 1 ·'), findsOneWidget);
    expect(find.byKey(const Key('article-partager')), findsOneWidget);
    expect(c.read(actualitesLuesProvider), contains('resume_r1'));
    await t.tap(find.byKey(const Key('actu-voir-match')));
    await t.pumpAndSettle();
    expect(find.text('fiche m-om'), findsOneWidget);
  });

  testWidgets("un titre de média mène à l'article d'origine ; le bouton rond revient en arrière", (t) async {
    await monter(t);
    await t.tap(find.byKey(const Key('actu-rss_1')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('actu-voir-match')), findsNothing);
    expect(find.text("Lire l'article sur RMC Sport"), findsOneWidget);
    await t.tap(find.byKey(const Key('article-retour')));
    await t.pumpAndSettle();
    expect(find.byType(PageActus), findsOneWidget);
    await t.tap(find.byKey(const Key('actu-rss_1')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('actu-lire-original')));
    await t.pumpAndSettle();
    expect(find.text('nav https://rmcsport.bfmtv.com/a'), findsOneWidget);
  });

  test("le badge de Compte : les actualités de l'accueil pas encore ouvertes", () async {
    final c = ProviderContainer(overrides: [actualitesProvider.overrideWith((ref) async => _actus)]);
    addTearDown(c.dispose);
    await c.read(actualitesProvider.future);
    expect(c.read(actualitesNonLuesProvider), 2);
    await c.read(actualitesLuesProvider.notifier).marquer('rss_1');
    expect(c.read(actualitesNonLuesProvider), 1);
  });

  testWidgets("« il y a » dans la langue de l'application", (t) async {
    late BuildContext ctx;
    await t.pumpWidget(MaterialApp(home: Builder(builder: (c) { ctx = c; return const SizedBox(); })));
    final maintenant = DateTime(2026, 10, 20, 12);
    expect(ilYa(ctx, maintenant.subtract(const Duration(seconds: 30)), maintenant: maintenant), "À l'instant");
    expect(ilYa(ctx, maintenant.subtract(const Duration(minutes: 25)), maintenant: maintenant), 'Il y a 25 min');
    expect(ilYa(ctx, maintenant.subtract(const Duration(hours: 5)), maintenant: maintenant), 'Il y a 5 h');
    expect(ilYa(ctx, maintenant.subtract(const Duration(days: 1, hours: 2)), maintenant: maintenant), 'Hier');
  });
}

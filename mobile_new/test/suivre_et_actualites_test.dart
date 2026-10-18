import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pronowin/features/accueil/presentation/pages/accueil_page.dart';
import 'package:pronowin/features/parametres/presentation/providers/settings_provider.dart';
import 'package:pronowin/shared/providers/favoris_provider.dart';
import 'package:pronowin/shared/widgets/suivre_match.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Suivre un match, et la page Actualités (18 octobre 2026).
///
/// Un seul match mis en favori en trente jours : le marque-page « Ajouter aux
/// favoris » ne disait pas qu'il déclenchait les alertes de but. C'est
/// désormais une cloche « Suivre ce match », qui dit ce qu'on recevra.
class _FavorisFaux extends FavorisNotifier {
  _FavorisFaux({this.echec = false});
  final bool echec;
  @override
  Future<EtatFavoris> build() async => const EtatFavoris();
  @override
  Future<void> basculerMatch(String matchId) async {
    if (echec) return; // le serveur a refusé : l'état ne bouge pas
    final ids = {...state.value!.matchIds};
    ids.contains(matchId) ? ids.remove(matchId) : ids.add(matchId);
    state = AsyncData(EtatFavoris(matchIds: ids));
  }
}

Future<void> monterBouton(WidgetTester t, {bool echec = false, bool termine = false}) async {
  await t.pumpWidget(ProviderScope(
    overrides: [favorisProvider.overrideWith(() => _FavorisFaux(echec: echec))],
    child: MaterialApp.router(routerConfig: GoRouter(routes: [
      GoRoute(path: '/', builder: (_, _) => Scaffold(body: Consumer(builder: (context, ref, _) {
        // Les réglages sont chargés au démarrage de l'application, bien avant
        // qu'on suive un match : ici aussi.
        ref.watch(settingsProvider);
        final suivi = ref.watch(favorisProvider).valueOrNull?.matchIds.contains('m1') ?? false;
        return IconButton(
          key: const Key('cloche'),
          tooltip: libelleSuivi(context, suivi),
          icon: Icon(iconeSuivi(suivi)),
          onPressed: () => basculerSuivi(context, 'm1', termine: termine),
        );
      }))),
      GoRoute(path: '/parametres', builder: (_, _) => const Text('paramètres')),
    ])),
  ));
  await t.pump();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('suivre un match', () {
    testWidgets('une cloche, et le premier appui dit ce qu\'on recevra', (t) async {
      await monterBouton(t);
      expect(find.byIcon(iconeMatchNonSuivi), findsOneWidget);
      expect(find.byTooltip('Suivre ce match'), findsOneWidget);
      await t.tap(find.byKey(const Key('cloche')));
      await t.pump();
      await t.pump();
      expect(find.byIcon(iconeMatchSuivi), findsOneWidget);
      expect(find.text("Match suivi : tu recevras le coup d'envoi, les buts et le résultat."), findsOneWidget);
      await t.tap(find.byKey(const Key('cloche')));
      await t.pump();
      // Le message précédent se retire avant que le suivant n'entre.
      await t.pump(const Duration(milliseconds: 800));
      expect(find.text('Tu ne suis plus ce match.'), findsOneWidget);
    });

    testWidgets('alertes de match coupées dans les Paramètres : on le dit', (t) async {
      SharedPreferences.setMockInitialValues({'notif_match': false});
      await monterBouton(t);
      await t.pump(const Duration(milliseconds: 50)); // les réglages se chargent
      await t.tap(find.byKey(const Key('cloche')));
      await t.pump();
      await t.pump();
      expect(find.text('Match suivi, mais les alertes de match sont coupées dans les Paramètres.'), findsOneWidget);
      expect(find.text('Activer'), findsOneWidget);
    });

    testWidgets('match terminé : ajouté aux matchs suivis, sans promesse d\'alerte', (t) async {
      await monterBouton(t, termine: true);
      await t.tap(find.byKey(const Key('cloche')));
      await t.pump();
      await t.pump();
      expect(find.text('Match ajouté à tes matchs suivis.'), findsOneWidget);
    });

    testWidgets('le serveur refuse : rien n\'est annoncé', (t) async {
      await monterBouton(t, echec: true);
      await t.tap(find.byKey(const Key('cloche')));
      await t.pump();
      await t.pump();
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byIcon(iconeMatchNonSuivi), findsOneWidget);
    });
  });

  group('page Actualités', () {
    final actus = <Map<String, dynamic>>[
      {'id': 'resume_r1', 'titre': "Marseille s'impose largement chez Angers (2-5)", 'resume': 'Score à la mi-temps : 1-2.',
       'categorie': 'Ligue 1', 'emoji': '⚽', 'image_url': null, 'source_url': null, 'is_pinned': false,
       'date': 'Il y a 1h', 'created_at': '2026-10-18T16:44:00Z', 'from_rss': false,
       'type': 'resume_match', 'match_id': 'm-om'},
      {'id': 'rss_1', 'titre': 'Mercato : un transfert record se prépare cet hiver', 'resume': 'Résumé du flux.',
       'categorie': 'RMC Sport', 'emoji': '📻', 'image_url': null, 'source_url': 'https://rmcsport.bfmtv.com/a',
       'is_pinned': false, 'date': 'Il y a 2h', 'created_at': '2026-10-18T15:00:00Z', 'from_rss': true},
    ];

    Future<void> monterPage(WidgetTester t) async {
      final routeur = GoRouter(initialLocation: '/actualites', routes: [
        GoRoute(path: '/actualites', builder: (_, _) => const PageActualites()),
        GoRoute(path: '/pronostics/:id', builder: (_, s) => Text('fiche ${s.pathParameters['id']}')),
      ]);
      await t.pumpWidget(ProviderScope(
        overrides: [toutesActualitesProvider.overrideWith((ref) async => actus)],
        child: MaterialApp.router(routerConfig: routeur),
      ));
      await t.pumpAndSettle();
    }

    testWidgets('filtres par famille ; un résumé ouvre la fiche du match', (t) async {
      await monterPage(t);
      expect(find.byKey(const Key('filtre-actus-resumes')), findsOneWidget);
      expect(find.byKey(const Key('filtre-actus-medias')), findsOneWidget);
      // Aucun article de la rédaction : pas de filtre vide.
      expect(find.byKey(const Key('filtre-actus-redaction')), findsNothing);

      await t.tap(find.byKey(const Key('filtre-actus-resumes')));
      await t.pumpAndSettle();
      expect(find.textContaining('Mercato'), findsNothing);

      await t.tap(find.textContaining('Marseille'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('actu-voir-match')), findsOneWidget);
      expect(find.text("Lire l'article complet"), findsNothing);
      await t.tap(find.byKey(const Key('actu-voir-match')));
      await t.pumpAndSettle();
      expect(find.text('fiche m-om'), findsOneWidget);
    });

    testWidgets('un article de média garde son lien vers l\'original, sans fiche de match', (t) async {
      await monterPage(t);
      await t.tap(find.textContaining('Mercato'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('actu-voir-match')), findsNothing);
      expect(find.text("Lire l'article complet"), findsOneWidget);
    });
  });
}

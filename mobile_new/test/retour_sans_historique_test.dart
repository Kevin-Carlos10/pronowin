import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pronowin/shared/utils/retour.dart';

/// Une page ouverte par notification doit pouvoir revenir en arrière.
///
/// Les notifications transportent un lien profond — `/pronostics/{id}` pour un
/// match, `/compte` pour le parrainage. En la tapant, `fcm_service` appelle
/// `context.go(deepLink)`, ce qui **remplace** la pile de navigation : l'écran
/// d'arrivée devient l'unique route.
///
/// Les flèches retour appelaient alors `context.pop()`, `canPop()` valait
/// `false`, et go_router levait `GoError: There is nothing to pop`.
/// Crashlytics l'a mesuré sur la 1.0.0 : 41 plantages pour 4 utilisateurs. Ce
/// n'est pas un cas limite, c'est le geste de quiconque tape une notification
/// puis revient en arrière.
///
/// Le motif correct existait dans `completer_profil_page.dart` — écrit une
/// fois, oublié dans les vingt autres endroits. Il vit maintenant dans
/// `retour.dart`, et ce contrôle vérifie les deux choses qui comptent : que la
/// fonction se comporte bien dans les deux situations, et qu'aucun écran ne
/// soit revenu au `pop()` nu.
void main() {
  group('retourOuAller', () {
    testWidgets('dépile quand il y a un historique', (tester) async {
      final routeur = GoRouter(
        initialLocation: '/depart',
        routes: [
          GoRoute(path: '/depart', builder: (c, s) => Scaffold(
            body: TextButton(
              onPressed: () => c.push('/arrivee'),
              child: const Text('aller')))),
          GoRoute(path: '/arrivee', builder: (c, s) => Scaffold(
            body: TextButton(
              onPressed: () => retourOuAller(c, repli: '/repli'),
              child: const Text('retour')))),
          GoRoute(path: '/repli', builder: (c, s) =>
            const Scaffold(body: Text('repli'))),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: routeur));

      await tester.tap(find.text('aller'));
      await tester.pumpAndSettle();
      expect(find.text('retour'), findsOneWidget);

      await tester.tap(find.text('retour'));
      await tester.pumpAndSettle();

      // On revient d'où l'on vient — pas sur le repli. Sans ce point, une
      // fonction qui irait toujours au repli passerait le test suivant en
      // cassant la navigation normale de toute l'application.
      expect(find.text('aller'), findsOneWidget,
        reason: 'avec un historique, le retour doit dépiler, pas rediriger');
      expect(find.text('repli'), findsNothing);
    });

    testWidgets('va au repli quand la pile est vide, sans lever', (tester) async {
      // `initialLocation` reproduit exactement l'effet d'un `go(deepLink)` :
      // une seule route, rien à dépiler.
      final routeur = GoRouter(
        initialLocation: '/arrivee',
        routes: [
          GoRoute(path: '/arrivee', builder: (c, s) => Scaffold(
            body: TextButton(
              onPressed: () => retourOuAller(c, repli: '/repli'),
              child: const Text('retour')))),
          GoRoute(path: '/repli', builder: (c, s) =>
            const Scaffold(body: Text('repli'))),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: routeur));

      await tester.tap(find.text('retour'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull,
        reason: 'c\'est le plantage signalé : GoError « There is nothing to pop »');
      expect(find.text('repli'), findsOneWidget);
    });
  });

  test('aucun écran de page ne dépile sans garde', () {
    // Les fermetures de boîtes de dialogue et de feuilles passent par
    // `Navigator.of(context).pop()` : là, il y a toujours quelque chose à
    // fermer, et les toucher casserait la fermeture. Seul le `context.pop()`
    // de go_router est concerné.
    //
    // Deux exemptions, chacune vérifiable à l'œil : le premier départ d'un
    // double `pop()` ferme la boîte de confirmation avant de quitter la page.
    // C'est le second qui est gardé.
    const exempts = {
      'lib/features/abonnement/presentation/pages/activer_premium_page.dart': 1,
      'lib/features/parrainage/presentation/pages/retrait_parrainage_page.dart': 1,
      'lib/shared/utils/retour.dart': 1,   // la garde elle-même
    };

    final fautes = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final chemin = f.path.replaceAll('\\', '/');
      final lignes = f.readAsLinesSync();

      var nus = <String>[];
      for (var i = 0; i < lignes.length; i++) {
        final l = lignes[i];
        if (l.trimLeft().startsWith('//') || l.trimLeft().startsWith('///')) continue;
        if (!l.contains('context.pop()')) continue;
        if (l.contains('canPop')) continue;      // garde en ligne
        nus.add('$chemin:${i + 1} ${l.trim()}');
      }

      final autorises = exempts[chemin] ?? 0;
      if (nus.length > autorises) {
        fautes.addAll(nus.skip(autorises));
      }
    }

    expect(fautes, isEmpty,
      reason: 'ces retours planteront sur une page ouverte par notification : '
              'go() remplace la pile, il n\'y a rien à dépiler. Utiliser '
              '`retourOuAller(context, repli: ...)`');
  });
}

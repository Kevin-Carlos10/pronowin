import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// La recherche interroge le serveur, pas la page chargée.
///
/// L'écran filtrait `pagedState.matches` — la liste **déjà chargée** du
/// provider paginé : vingt matchs, ceux de la page courante et des filtres
/// courants. Il ne demandait ni les pages suivantes, ni le serveur avec le
/// terme saisi.
///
/// Une équipe qui existe mais dont la page n'avait pas été téléchargée était
/// annoncée absente, et le résultat dépendait du nombre de fois qu'on avait
/// fait défiler la liste — un compte qui vient d'ouvrir l'application ne
/// trouvait presque rien.
///
/// Le pendant serveur est `backend/src/__tests__/recherche_matchs.test.ts`.
void main() {
  late String page;
  late String provider;
  late String source;

  setUpAll(() {
    /// Le code seul : les commentaires citent volontairement l'ancien filtre
    /// pour expliquer ce qui a été retiré, et cette explication doit rester
    /// lisible sans faire tomber le contrôle.
    String codeSeul(String s) => s
        .split('\n')
        .where((l) {
          final t = l.trimLeft();
          return !t.startsWith('//') && !t.startsWith('*');
        })
        .join('\n');

    String lire(String chemin) {
      final f = File(chemin);
      if (!f.existsSync()) fail('Fichier introuvable : $chemin');
      return codeSeul(f.readAsStringSync());
    }

    page = lire('lib/features/pronostics/presentation/pages/search_page.dart');
    provider = lire(
        'lib/features/pronostics/presentation/providers/pronostics_provider.dart');
    source = lire(
        'lib/features/pronostics/data/datasources/pronostics_remote_datasource.dart');
  });

  group('le filtre local a disparu', () {
    test('la page ne parcourt plus la liste chargée', () {
      expect(page.contains('m.homeTeam.toLowerCase().contains(q)'), isFalse,
          reason: 'ce filtre ne voyait que la page courante');
      expect(page.contains('pagedState.matches'), isFalse);
    });

    test('elle consulte le provider de recherche', () {
      // C'est la **lecture** qui compte, pas la simple présence du nom :
      // l'invalidation du bouton « Réessayer » le mentionne aussi, si bien
      // qu'un retour au filtre local passait le contrôle. Vérifié en le
      // remettant.
      expect(page, contains('ref.watch(rechercheMatchsProvider(terme))'));
      expect(page.contains('matchesPaginatedProvider'), isFalse,
          reason: 'la page ne doit plus dépendre de la liste paginée');
    });

    test('elle distingue chargement, erreur et résultats', () {
      expect(page, contains('loading:'));
      expect(page, contains('error:'));
      expect(page, contains('_NoResults'));
    });
  });

  group('le terme part au serveur', () {
    test('la requête porte le paramètre `q`', () {
      expect(source, contains("'q':"));
      expect(source, contains('recherche'));
    });

    test('le provider demande sans filtre de date ni de statut', () {
      // Chercher, c'est regarder partout. Réappliquer les filtres courants
      // reproduirait le défaut sous une autre forme.
      expect(provider, contains('GetMatchesParams(recherche: t, limit: 50)'));
    });

    test('il ne cherche pas sous deux caractères', () {
      // Même seuil que le serveur : en deçà, l'appel ne ramènerait que les
      // premiers matchs, sans rapport avec la saisie.
      expect(provider, contains('if (t.length < 2) return const []'));
      expect(page, contains('terme.length < 2'));
    });

    test('les résultats sont ordonnés par date', () {
      expect(provider, contains('a.matchDate.compareTo(b.matchDate)'));
    });
  });
}

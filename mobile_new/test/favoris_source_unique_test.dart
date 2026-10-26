import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronowin/shared/providers/favoris_provider.dart';

/// Les favoris, une source et un identifiant.
///
/// ── Deux providers portant le même nom ────────────────────────────────────
///
/// Il existait deux `FavoritesNotifier`, exposés tous deux sous le nom
/// `favoritesProvider` — l'un dans le module Accueil, l'autre dans Pronostics.
/// Selon le fichier importé, le même nom rendait un `AsyncValue<Set<String>>`
/// ou un `FavoritesState`. Ils ne s'invalidaient jamais l'un l'autre : une
/// étoile allumée sur l'Accueil restait éteinte sur la liste des pronostics.
///
/// ── Et ils ne parlaient pas des mêmes identifiants ────────────────────────
///
/// `/favorites` renvoie `id` (celui du **pronostic** quand le match en a un) et
/// `match_id` (toujours celui du **match**). L'Accueil lisait `match_id`, les
/// Pronostics lisaient `id` : deux ensembles différents pour les mêmes favoris,
/// comparés ensuite à des `match.id` qui valent tantôt l'un, tantôt l'autre
/// selon la liste d'où l'on vient.
///
/// ── Et ils survivaient au changement de compte ────────────────────────────
///
/// `fav_matches` et `fav_leagues` n'étaient rattachées à personne, et
/// `CacheService.clearAll()` ne supprime que les clés préfixées `cache_`. Un
/// second compte sur le même téléphone héritait des favoris du premier — et de
/// ses abonnements aux notifications par match.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('les clés sont rattachées à un compte', () {
    test('deux comptes ne partagent aucune clé', () {
      expect(cleFavorisMatchs('u1'), isNot(cleFavorisMatchs('u2')));
      expect(cleFavorisLigues('u1'), isNot(cleFavorisLigues('u2')));
    });

    test('les clés portent l\'identifiant du compte', () {
      expect(cleFavorisMatchs('u1'), contains('u1'));
      expect(cleFavorisLigues('u1'), contains('u1'));
    });

    test('les anciennes clés globales ne sont plus employées', () {
      // `fav_matches` et `fav_leagues` étaient communes à tous les comptes.
      expect(cleFavorisMatchs('u1'), isNot('fav_matches'));
      expect(cleFavorisLigues('u1'), isNot('fav_leagues'));
    });
  });

  group('la déconnexion efface les favoris locaux', () {
    test('de tous les comptes présents sur l\'appareil', () async {
      SharedPreferences.setMockInitialValues({
        cleFavorisMatchs('u1'): ['m1', 'm2'],
        cleFavorisLigues('u1'): ['Ligue 1'],
        cleFavorisMatchs('u2'): ['m3'],
      });

      // Les sujets FCM ne sont pas résiliables hors appareil : le banc porte
      // sur l'effacement, pas sur l'abonnement.
      await effacerFavorisLocaux(resilierSujets: false);

      final p = await SharedPreferences.getInstance();
      expect(p.getStringList(cleFavorisMatchs('u1')), isNull);
      expect(p.getStringList(cleFavorisLigues('u1')), isNull);
      expect(p.getStringList(cleFavorisMatchs('u2')), isNull);
    });

    test('sans toucher au reste', () async {
      // Contrepartie : un effacement trop large emporterait le jeton de
      // session ou les préférences d'affichage.
      SharedPreferences.setMockInitialValues({
        cleFavorisMatchs('u1'): ['m1'],
        'theme_mode': 'dark',
        'cache_matches_all': '{}',
      });

      await effacerFavorisLocaux(resilierSujets: false);

      final p = await SharedPreferences.getInstance();
      expect(p.getString('theme_mode'), 'dark');
      expect(p.getString('cache_matches_all'), '{}');
    });
  });

  group('une seule source dans le code', () {
    late List<String> sources;

    /// Le code seul : les commentaires citent volontairement l'ancien nom
    /// pour expliquer ce qui a été supprimé, et cette explication doit rester
    /// lisible sans faire tomber le contrôle.
    String codeSeul(String source) => source
        .split('\n')
        .where((l) {
          final t = l.trimLeft();
          return !t.startsWith('//') && !t.startsWith('*');
        })
        .join('\n');

    setUpAll(() {
      sources = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .map((f) => codeSeul(f.readAsStringSync()))
          .toList();
    });

    test('plus aucun `favoritesProvider`', () {
      final restants = sources.where((s) => s.contains('favoritesProvider'));
      expect(restants, isEmpty,
          reason: 'deux providers portaient ce nom, dans deux fichiers');
    });

    test('plus aucun `FavoritesNotifier`', () {
      expect(sources.where((s) => s.contains('class FavoritesNotifier')),
          isEmpty);
    });

    test('le module Pronostics n\'a plus son provider de favoris', () {
      expect(
        File('lib/features/pronostics/presentation/providers/favorites_provider.dart')
            .existsSync(),
        isFalse,
      );
    });
  });

  group('l\'identifiant retenu est celui du match', () {
    late String source;

    setUpAll(() {
      source = File('lib/shared/providers/favoris_provider.dart')
          .readAsStringSync();
    });

    test('la lecture prend `match_id`, jamais `id`', () {
      expect(source, contains("['match_id']"));
      expect(
        RegExp(r"\)\['id'\]").hasMatch(source),
        isFalse,
        reason: "`id` vaut l'identifiant du pronostic quand il y en a un",
      );
    });

    test('la déconnexion est câblée à l\'authentification', () {
      final auth = File(
        'lib/features/auth/presentation/providers/auth_provider.dart',
      ).readAsStringSync();

      // Autant d'effacements de favoris que d'effacements de cache : chaque
      // changement de session doit emporter les deux.
      expect('effacerFavorisLocaux()'.allMatches(auth).length,
          'CacheService.clearAll()'.allMatches(auth).length);
    });
  });
}

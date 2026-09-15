import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/network/dio_client.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../features/pronostics/data/models/match_model.dart';
import '../../features/pronostics/domain/entities/match_entity.dart';

/// Les favoris, une seule fois, avec un identifiant canonique.
///
/// ── Deux sources pour la même notion ───────────────────────────────────────
///
/// Il existait deux `FavoritesNotifier`, **portant le même nom de provider**
/// dans deux fichiers : celui de l'Accueil et celui des Pronostics. Selon le
/// fichier importé, `favoritesProvider` rendait un `AsyncValue<Set<String>>`
/// ou un `FavoritesState`. Ils ne s'invalidaient jamais l'un l'autre : mettre
/// un match en favori depuis l'Accueil laissait l'étoile éteinte sur la liste
/// des pronostics, et inversement.
///
/// Pire, ils ne parlaient pas des mêmes identifiants. `/favorites` renvoie
/// deux champs :
///
///   * `id` — l'identifiant du **pronostic** quand le match en a un, sinon
///     celui du match. Il sert à naviguer vers le détail ;
///   * `match_id` — toujours celui du **match**. C'est lui que l'endpoint de
///     retrait exige.
///
/// L'Accueil lisait `match_id`, les Pronostics lisaient `id`. Deux ensembles
/// d'identifiants différents pour les mêmes favoris, comparés ensuite à des
/// `match.id` qui valent tantôt l'un, tantôt l'autre selon la liste d'où l'on
/// vient. L'étoile était juste par coïncidence.
///
/// Ici, un seul ensemble, et un seul identifiant : celui du match.
///
/// ── Des favoris qui survivaient au changement de compte ───────────────────
///
/// Les clés `fav_matches` et `fav_leagues` n'étaient rattachées à personne, et
/// `CacheService.clearAll()` ne supprime que les clés préfixées `cache_`. Un
/// second compte ouvert sur le même téléphone héritait donc des favoris du
/// premier — et de ses abonnements aux notifications par match, qui ne sont
/// jamais résiliés.
///
/// Les clés portent désormais l'identifiant du compte, et la déconnexion
/// résilie les sujets FCM.
@immutable
class EtatFavoris {
  /// Identifiants de **match**, toujours — jamais de pronostic.
  final Set<String> matchIds;

  /// Ligues suivies, par leur nom tel que l'API l'écrit.
  final Set<String> ligues;

  const EtatFavoris({this.matchIds = const {}, this.ligues = const {}});

  EtatFavoris copyWith({Set<String>? matchIds, Set<String>? ligues}) =>
      EtatFavoris(
        matchIds: matchIds ?? this.matchIds,
        ligues:   ligues   ?? this.ligues,
      );
}

/// Préfixe des clés locales, sans le compte.
const _prefixeMatchs = 'favoris_matchs';
const _prefixeLigues = 'favoris_ligues';

/// Les clés d'un compte donné.
///
/// Exposées pour la déconnexion et pour les bancs : personne ne doit les
/// réécrire à la main ailleurs.
String cleFavorisMatchs(String compteId) => '${_prefixeMatchs}_$compteId';
String cleFavorisLigues(String compteId) => '${_prefixeLigues}_$compteId';

/// Efface les favoris de tous les comptes présents sur l'appareil.
///
/// Appelé à la déconnexion et à la suppression de compte. Les sujets FCM par
/// match sont résiliés au passage : sans cela, un utilisateur déconnecté
/// continuait de recevoir les notifications des matchs qu'il avait suivis.
Future<void> effacerFavorisLocaux({bool resilierSujets = true}) async {
  final p = await SharedPreferences.getInstance();

  if (resilierSujets) {
    for (final cle in p.getKeys().where((k) => k.startsWith(_prefixeMatchs))) {
      for (final id in p.getStringList(cle) ?? const <String>[]) {
        try {
          await FirebaseMessaging.instance.unsubscribeFromTopic('match_$id');
        } catch (_) {
          // Un sujet non résilié vaut mieux qu'une déconnexion qui échoue.
        }
      }
    }
  }

  for (final cle in p
      .getKeys()
      .where((k) => k.startsWith(_prefixeMatchs) || k.startsWith(_prefixeLigues))
      .toList()) {
    await p.remove(cle);
  }
}

class FavorisNotifier extends AsyncNotifier<EtatFavoris> {
  /// L'identifiant du compte connecté, ou `null` s'il n'y en a pas.
  String? get _compteId {
    final a = ref.read(authProvider);
    return a is AuthAuthenticated ? a.user.id : null;
  }

  @override
  Future<EtatFavoris> build() async {
    // Le provider se reconstruit au changement de session : sans cette
    // dépendance, les favoris du compte précédent restaient affichés jusqu'au
    // redémarrage de l'application.
    ref.watch(authProvider);

    final compte = _compteId;
    if (compte == null) return const EtatFavoris();

    final p = await SharedPreferences.getInstance();
    final local = EtatFavoris(
      matchIds: Set.from(p.getStringList(cleFavorisMatchs(compte)) ?? const []),
      ligues:   Set.from(p.getStringList(cleFavorisLigues(compte)) ?? const []),
    );

    try {
      final r = await ref.read(dioProvider).get('/favorites');
      final liste = (r.data as List<dynamic>?) ?? const [];
      // `match_id`, jamais `id` : c'est l'identifiant que l'endpoint de
      // retrait exige, et le seul qui désigne toujours la même chose.
      final distants = liste
          .map((e) => (e as Map<String, dynamic>)['match_id'] as String? ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();

      await p.setStringList(cleFavorisMatchs(compte), distants.toList());
      return local.copyWith(matchIds: distants);
    } catch (_) {
      // Serveur injoignable : la copie locale reste le meilleur état connu.
      return local;
    }
  }

  /// Met ou retire [matchId] des favoris. [matchId] doit être un id de match.
  Future<void> basculerMatch(String matchId) async {
    final compte = _compteId;
    if (compte == null) return;

    final avant = state.valueOrNull ?? const EtatFavoris();
    final ajoute = !avant.matchIds.contains(matchId);
    final apres = Set<String>.from(avant.matchIds);
    ajoute ? apres.add(matchId) : apres.remove(matchId);

    state = AsyncData(avant.copyWith(matchIds: apres));

    final p = await SharedPreferences.getInstance();
    await p.setStringList(cleFavorisMatchs(compte), apres.toList());

    try {
      final dio = ref.read(dioProvider);
      if (ajoute) {
        await dio.post('/favorites/$matchId');
      } else {
        await dio.delete('/favorites/$matchId');
      }
    } catch (_) {
      // Le serveur n'a pas suivi : on revient à l'état d'avant plutôt que
      // d'afficher une étoile que le prochain démarrage effacera.
      state = AsyncData(avant);
      await p.setStringList(cleFavorisMatchs(compte), avant.matchIds.toList());
      return;
    }

    try {
      final sujet = 'match_$matchId';
      if (ajoute) {
        await FirebaseMessaging.instance.subscribeToTopic(sujet);
      } else {
        await FirebaseMessaging.instance.unsubscribeFromTopic(sujet);
      }
    } catch (_) {
      // Les notifications sont un supplément : leur échec ne doit pas défaire
      // un favori que le serveur a accepté.
    }
  }

  /// Met ou retire une ligue des favoris. Purement local.
  Future<void> basculerLigue(String ligue) async {
    final compte = _compteId;
    if (compte == null) return;

    final avant = state.valueOrNull ?? const EtatFavoris();
    final apres = Set<String>.from(avant.ligues);
    apres.contains(ligue) ? apres.remove(ligue) : apres.add(ligue);

    state = AsyncData(avant.copyWith(ligues: apres));
    final p = await SharedPreferences.getInstance();
    await p.setStringList(cleFavorisLigues(compte), apres.toList());
  }
}

final favorisProvider =
    AsyncNotifierProvider<FavorisNotifier, EtatFavoris>(FavorisNotifier.new);

/// La liste complète des matchs favoris, pronostic compris.
///
/// Se recharge dès que [favorisProvider] change : l'écran des favoris suit le
/// bouton étoile sans qu'on ait à l'invalider à la main.
final favorisMatchsProvider =
    FutureProvider.autoDispose<List<MatchEntity>>((ref) async {
  ref.watch(favorisProvider);

  final r = await ref.read(dioProvider).get('/favorites');
  final liste = (r.data as List<dynamic>?) ?? const [];
  return liste
      .map((e) => MatchModel.fromJson(e as Map<String, dynamic>))
      .toList();
});

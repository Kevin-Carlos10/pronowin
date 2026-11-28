import 'dart:async';
import 'dart:convert';
import 'package:pronowin/l10n/app_strings.dart';
import 'package:pronowin/features/parametres/presentation/providers/settings_provider.dart';
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

  /// Équipes suivies (7 novembre 2026), par identifiant API-Football, dans
  /// l'ordre où elles ont été suivies.
  final List<EquipeSuivie> equipes;

  const EtatFavoris({this.matchIds = const {}, this.ligues = const {}, this.equipes = const []});

  bool suitEquipe(int id) => equipes.any((e) => e.id == id);

  EtatFavoris copyWith({Set<String>? matchIds, Set<String>? ligues, List<EquipeSuivie>? equipes}) =>
      EtatFavoris(
        matchIds: matchIds ?? this.matchIds,
        ligues:   ligues   ?? this.ligues,
        equipes:  equipes  ?? this.equipes,
      );
}

/// Une équipe suivie : de quoi l'afficher et ouvrir sa fiche sans réseau.
class EquipeSuivie {
  final int id;
  final String nom;
  final String? logo, competition;
  const EquipeSuivie({required this.id, required this.nom, this.logo, this.competition});

  Map<String, dynamic> toJson() => {'id': id, 'nom': nom, 'logo': logo, 'competition': competition};

  static EquipeSuivie? fromJson(Object? j) {
    if (j is! Map || j['id'] is! num || j['nom'] is! String) return null;
    return EquipeSuivie(id: (j['id'] as num).toInt(), nom: j['nom'] as String,
      logo: j['logo'] as String?, competition: j['competition'] as String?);
  }
}

/// Préfixe des clés locales, sans le compte.
const _prefixeMatchs = 'favoris_matchs';
const _prefixeLigues = 'favoris_ligues';
const _prefixeEquipes = 'favoris_equipes';
const _prefixeSuivisSynchro = 'favoris_suivis_synchro';

/// Les clés d'un compte donné.
///
/// Exposées pour la déconnexion et pour les bancs : personne ne doit les
/// réécrire à la main ailleurs.
String cleFavorisMatchs(String compteId) => '${_prefixeMatchs}_$compteId';
String cleFavorisLigues(String compteId) => '${_prefixeLigues}_$compteId';
String cleFavorisEquipes(String compteId) => '${_prefixeEquipes}_$compteId';

/// Les équipes et ligues suivies sont aussi sur le serveur (15 novembre
/// 2026) : c'est lui qui annonce leurs matchs. Tant que cette clé manque,
/// ce que le téléphone suivait s'ajoute à ce que le serveur connaît ; ensuite,
/// le serveur fait foi — un retrait sur un autre appareil vaut ici aussi.
String cleFavorisSuivisSynchro(String compteId) => '${_prefixeSuivisSynchro}_$compteId';

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
          await FirebaseMessaging.instance.unsubscribeFromTopic('match_${id}_en');
        } catch (_) {
          // Un sujet non résilié vaut mieux qu'une déconnexion qui échoue.
        }
      }
    }
  }

  for (final cle in p
      .getKeys()
      .where((k) => k.startsWith(_prefixeMatchs) || k.startsWith(_prefixeLigues)
          || k.startsWith(_prefixeEquipes) || k.startsWith(_prefixeSuivisSynchro))
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
    ref.watch(settingsProvider.select((s) => s.lang));
    ref.watch(settingsProvider.select((s) => s.notifMatch));

    final compte = _compteId;
    if (compte == null) return const EtatFavoris();

    final p = await SharedPreferences.getInstance();
    for (final id in p.getStringList(cleFavorisMatchs(compte)) ?? <String>[]) {
      await _syncMatchTopic(id, ref.read(settingsProvider).notifMatch);
    }
    final local = EtatFavoris(
      matchIds: Set.from(p.getStringList(cleFavorisMatchs(compte)) ?? const []),
      ligues:   Set.from(p.getStringList(cleFavorisLigues(compte)) ?? const []),
      equipes:  _lireEquipes(p, compte),
    );

    var etat = local;
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
      etat = local.copyWith(matchIds: distants);
    } catch (_) {
      // Serveur injoignable : la copie locale reste le meilleur état connu.
    }
    return _synchroniserSuivis(p, compte, etat);
  }

  /// Le premier passage en cours : le fournisseur se construit deux fois au
  /// démarrage (les réglages se chargent), et deux passages enverraient deux
  /// fois la même liste.
  Future<void>? _premierPassage;

  /// Les équipes et ligues suivies, d'après le serveur (15 novembre 2026).
  /// Voir [cleFavorisSuivisSynchro].
  Future<EtatFavoris> _synchroniserSuivis(SharedPreferences p, String compte, EtatFavoris local) async {
    final premier = p.getBool(cleFavorisSuivisSynchro(compte)) != true;
    if (premier && _premierPassage != null) {
      // Fait, ou manqué : la suite se décide sur l'état qu'il a laissé.
      await _premierPassage;
      return _synchroniserSuivis(p, compte, local);
    }
    // Pris avant la moindre attente : c'est ce qui écarte le second.
    final fini = premier ? Completer<void>() : null;
    if (fini != null) _premierPassage = fini.future;
    try {
      final dio = ref.read(dioProvider);
      final d = (await dio.get('/favorites/suivis')).data as Map<String, dynamic>;
      final ligues = <String>{for (final l in d['ligues'] as List? ?? const []) if (l is String) l};
      final equipes = [for (final e in d['equipes'] as List? ?? const []) ?EquipeSuivie.fromJson(e)];
      var etat = local.copyWith(ligues: ligues, equipes: equipes);
      if (premier) {
        // Premier passage sur ce téléphone : ce qu'il suivait s'ajoute.
        final ids = {for (final e in equipes) e.id};
        final toutesLigues = {...ligues, ...local.ligues};
        final toutesEquipes = [...equipes, for (final e in local.equipes) if (!ids.contains(e.id)) e];
        if (toutesLigues.length != ligues.length || toutesEquipes.length != equipes.length) {
          await dio.put('/favorites/suivis', data: {
            'ligues': toutesLigues.toList(),
            'equipes': [for (final e in toutesEquipes) e.toJson()],
          });
        }
        etat = local.copyWith(ligues: toutesLigues, equipes: toutesEquipes);
        await p.setBool(cleFavorisSuivisSynchro(compte), true);
      }
      await p.setStringList(cleFavorisLigues(compte), etat.ligues.toList());
      await p.setStringList(cleFavorisEquipes(compte), [for (final e in etat.equipes) jsonEncode(e.toJson())]);
      return etat;
    } catch (_) {
      // Serveur injoignable, ou antérieur : la copie locale, comme avant.
      return local;
    } finally {
      if (fini != null) {
        _premierPassage = null;
        fini.complete();
      }
    }
  }

  /// Le serveur suit chaque changement : c'est lui qui annonce les matchs.
  /// Tant que le premier passage n'a pas réussi, rien n'est envoyé — la liste
  /// du téléphone remplacerait celle du serveur au lieu de s'y ajouter ; s'il
  /// échoue, le prochain démarrage refait ce passage.
  Future<void> _envoyerSuivis(String compte, Map<String, Object> corps) async {
    final p = await SharedPreferences.getInstance();
    if (p.getBool(cleFavorisSuivisSynchro(compte)) != true) return;
    try {
      await ref.read(dioProvider).put('/favorites/suivis', data: corps);
    } catch (_) {
      await p.remove(cleFavorisSuivisSynchro(compte));
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

    await _syncMatchTopic(matchId, ajoute && ref.read(settingsProvider).notifMatch);
  }

  Future<void> _syncMatchTopic(String matchId, bool enabled) async {
    try {
      final base = 'match_$matchId';
      final selected = AppStrings.current.locale.languageCode == 'en' ? '${base}_en' : base;
      final other = selected == base ? '${base}_en' : base;
      await FirebaseMessaging.instance.unsubscribeFromTopic(other);
      if (enabled) {
        await FirebaseMessaging.instance.subscribeToTopic(selected);
      } else {
        await FirebaseMessaging.instance.unsubscribeFromTopic(selected);
      }
    } catch (_) { /* Retried on next settings/session refresh. */ }
  }

  static List<EquipeSuivie> _lireEquipes(SharedPreferences p, String compte) {
    try {
      return [
        for (final e in p.getStringList(cleFavorisEquipes(compte)) ?? const <String>[])
          ?EquipeSuivie.fromJson(jsonDecode(e)),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Suit ou ne suit plus une équipe : ses matchs s'affichent dans « Suivis »,
  /// et le serveur annonce leur coup d'envoi, leurs buts et leur résultat
  /// (15 novembre 2026).
  Future<void> basculerEquipe(EquipeSuivie equipe) async {
    final compte = _compteId;
    if (compte == null) return;

    final avant = state.valueOrNull ?? const EtatFavoris();
    final apres = avant.suitEquipe(equipe.id)
        ? [for (final e in avant.equipes) if (e.id != equipe.id) e]
        : [...avant.equipes, equipe];

    state = AsyncData(avant.copyWith(equipes: apres));
    final p = await SharedPreferences.getInstance();
    await p.setStringList(cleFavorisEquipes(compte), [for (final e in apres) jsonEncode(e.toJson())]);
    await _envoyerSuivis(compte, {'equipes': [for (final e in apres) e.toJson()]});
  }

  /// Met ou retire une ligue des favoris ; le serveur annonce le coup
  /// d'envoi et le résultat de ses matchs (15 novembre 2026).
  Future<void> basculerLigue(String ligue) async {
    final compte = _compteId;
    if (compte == null) return;

    final avant = state.valueOrNull ?? const EtatFavoris();
    final apres = Set<String>.from(avant.ligues);
    apres.contains(ligue) ? apres.remove(ligue) : apres.add(ligue);

    state = AsyncData(avant.copyWith(ligues: apres));
    final p = await SharedPreferences.getInstance();
    await p.setStringList(cleFavorisLigues(compte), apres.toList());
    await _envoyerSuivis(compte, {'ligues': apres.toList()});
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

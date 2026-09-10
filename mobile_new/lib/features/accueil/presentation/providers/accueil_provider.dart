import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/cache/cache_service.dart';
import '../../../../core/cache/cache_meta_provider.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../core/network/connectivity_provider.dart';

// ─── Helpers ──────────────────────────────────────────────────────────────────

/// Stratégie stale-while-revalidate générique :
/// 1. Essaie le réseau (rapide si connecté).
/// 2. En cas de succès → sauvegarde en cache + marque synced.
/// 3. En cas d'erreur réseau → sert le cache (même expiré) sans lever d'exception.
/// Retourne null si ni réseau ni cache n'ont de données.
Future<T?> _fetchWithCache<T>({
  required Ref ref,
  required String cacheKey,
  required Future<T> Function() fetchFn,
  required T Function(dynamic) fromJson,
}) async {
  try {
    final data = await fetchFn();
    await CacheService.save(cacheKey, data);
    ref.read(cacheMetaProvider.notifier).markSynced(cacheKey);
    return data;
  } catch (_) {
    return await CacheService.loadStale<T>(cacheKey, fromJson);
  }
}

// ─── Favoris ──────────────────────────────────────────────────────────────────

class FavoritesNotifier extends AsyncNotifier<Set<String>> {
  static const _key = 'favorites_ids';

  @override
  Future<Set<String>> build() async {
    final data = await _fetchWithCache<List<dynamic>>(
      ref:      ref,
      cacheKey: _key,
      fetchFn:  () async {
        final r = await ref.read(dioProvider).get('/favorites');
        return (r.data as List<dynamic>?) ?? [];
      },
      fromJson: (d) => (d as List<dynamic>),
    );
    if (data == null) return {};
    return data
        .map((e) => (e as Map<String, dynamic>)['match_id'] as String)
        .toSet();
  }

  Future<void> toggle(String matchId) async {
    final current = state.valueOrNull ?? {};
    final isFav   = current.contains(matchId);

    state = AsyncData(
      isFav ? (Set<String>.from(current)..remove(matchId))
            : (Set<String>.from(current)..add(matchId)),
    );

    try {
      final dio = ref.read(dioProvider);
      if (isFav) {
        await dio.delete('/favorites/$matchId');
      } else {
        await dio.post('/favorites/$matchId');
      }
      ref.invalidateSelf();
    } catch (_) {
      state = AsyncData(current);
    }
  }
}

final favoritesProvider =
    AsyncNotifierProvider<FavoritesNotifier, Set<String>>(
  FavoritesNotifier.new,
);

final favoritesListProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  const key = 'favorites_list';
  final data = await _fetchWithCache<List<dynamic>>(
    ref:      ref,
    cacheKey: key,
    fetchFn:  () async {
      final r = await ref.read(dioProvider).get('/favorites');
      return (r.data as List<dynamic>?) ?? [];
    },
    fromJson: (d) => (d as List<dynamic>),
  );
  return (data ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
});

// ─── Pronostics du jour ───────────────────────────────────────────────────────

final pronosticsJourProvider =
    FutureProvider.autoDispose<List<dynamic>>((ref) async {
  const key = 'pronostics_today';
  final data = await _fetchWithCache<List<dynamic>>(
    ref:      ref,
    cacheKey: key,
    fetchFn:  () async {
      final r = await ref.read(dioProvider).get('/pronostics', queryParameters: {
        // Fetch généreux (limite max autorisée côté backend) — cette liste
        // alimente aussi les sections "En direct" et "Top prono du jour" qui
        // ont besoin de voir TOUS les pronos publiés du jour pour choisir
        // correctement (pas seulement les 5 affichés dans la liste "Pronostics
        // du jour" elle-même, qui applique son propre .take(5) à l'affichage).
        'date_filter': 'today', 'limit': 50,
      });
      return (r.data['data'] as List<dynamic>?) ?? [];
    },
    fromJson: (d) => (d as List<dynamic>),
  );
  return data ?? [];
});

// ─── Actualités football ──────────────────────────────────────────────────────

final actualitesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  const key = 'actualites';
  final data = await _fetchWithCache<List<dynamic>>(
    ref:      ref,
    cacheKey: key,
    fetchFn:  () async {
      final r = await ref.read(dioProvider).get('/actualites');
      // Une liste vide est une reponse valide, pas un echec : elle veut dire
      // qu'aucune actualite n'est publiee. L'ecran omet alors la section.
      return (r.data as List<dynamic>?) ?? [];
    },
    fromJson: (d) => (d as List<dynamic>),
  );
  // Quatre articles etaient inventes ici — « La FIFA a officialise les
  // groupes », « Real Madrid vs Bayern et Arsenal vs PSG » — dates en relatif
  // (« Aujourd'hui », « Hier »), donc jamais perimes en apparence. C'est ce qui
  // les rendait dangereux : de l'information fabriquee qu'aucun lecteur ne
  // pouvait reconnaitre comme fausse.
  //
  // Et ce n'etait pas un repli d'erreur : ils sortaient aussi quand l'API
  // repondait correctement avec une liste vide, c'est-a-dire tant qu'aucune
  // actualite n'etait publiee. L'etat par defaut d'une installation neuve.
  if (data == null) return const <Map<String, dynamic>>[];
  return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
});


// ─── Prochain match à venir ───────────────────────────────────────────────────

final nextPronosticProvider =
    FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  const key = 'pronostics_week';
  final data = await _fetchWithCache<List<dynamic>>(
    ref:      ref,
    cacheKey: key,
    fetchFn:  () async {
      final r = await ref.read(dioProvider).get('/pronostics', queryParameters: {
        // Idem pronosticsJourProvider ci-dessus : page/per_page sont ignorés
        // par le backend (pagination par curseur), seul `limit` compte.
        'date_filter': 'week', 'limit': 50,
      });
      return (r.data['data'] as List<dynamic>?) ?? [];
    },
    fromJson: (d) => (d as List<dynamic>),
  );
  if (data == null || data.isEmpty) return null;
  final upcoming = data
      .map((e) => e as Map<String, dynamic>)
      .where((p) => p['status'] == 'upcoming')
      .toList();
  if (upcoming.isEmpty) return null;
  upcoming.sort((a, b) {
    final da = DateTime.tryParse(a['match_date'] as String? ?? '') ?? DateTime(2099);
    final db = DateTime.tryParse(b['match_date'] as String? ?? '') ?? DateTime(2099);
    return da.compareTo(db);
  });
  return upcoming.first;
});

// ─── Stats publiques ──────────────────────────────────────────────────────────

final statsJourProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  const key = 'pronostics_stats';
  final empty = {'winRate': 0, 'streak': 0, 'upcoming': 0, 'publishedToday': 0};
  final data = await _fetchWithCache<Map<String, dynamic>>(
    ref:      ref,
    cacheKey: key,
    fetchFn:  () async {
      final r = await ref.read(dioProvider).get('/pronostics/stats');
      return r.data as Map<String, dynamic>;
    },
    fromJson: (d) => Map<String, dynamic>.from(d as Map),
  );
  return data ?? empty;
});

/// Bilan des pronostics publiés sur les 30 derniers jours.
///
/// Sert la bande de preuve de l'accueil : « 30 derniers pronostics · 18 gagnés
/// · +12 % ». C'est l'argument de confiance de l'app, donc l'endpoint est
/// ouvert aux invités — il ne contient aucune donnée personnelle.
final performance30Provider =
    FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  const key = 'pronostics_perf_30';
  return _fetchWithCache<Map<String, dynamic>>(
    ref: ref,
    cacheKey: key,
    fetchFn: () async {
      final r = await ref
          .read(dioProvider)
          .get('/pronostics/performance', queryParameters: {'days': 30});
      return Map<String, dynamic>.from(r.data as Map);
    },
    fromJson: (d) => Map<String, dynamic>.from(d as Map),
  );
});

/// Pronostics d'hier, déjà réglés — pour boucler la journée précédente.
final hierProvider =
    FutureProvider.autoDispose<List<dynamic>>((ref) async {
  const key = 'pronostics_hier';
  final data = await _fetchWithCache<List<dynamic>>(
    ref: ref,
    cacheKey: key,
    fetchFn: () async {
      final r = await ref.read(dioProvider).get('/pronostics',
          queryParameters: {'date_filter': 'yesterday', 'limit': 50});
      return (r.data['data'] as List?) ?? const [];
    },
    fromJson: (d) => List<dynamic>.from(d as List),
  );
  return data ?? const [];
});

// ─── État global du cache (pour la bannière offline) ─────────────────────────

/// Retourne l'heure de la dernière sync réseau des pronos du jour, ou null.
final lastPronosSyncProvider = Provider<DateTime?>((ref) {
  return ref.watch(cacheMetaProvider)['pronostics_today'];
});

/// true si on est hors ligne ET qu'on a des données en cache.
final isServingFromCacheProvider = Provider<bool>((ref) {
  final isOnline  = ref.watch(isOnlineProvider);
  final lastSync  = ref.watch(lastPronosSyncProvider);
  // On est hors ligne et les données ont été chargées avant
  return !isOnline && lastSync != null;
});

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
        'date_filter': 'today', 'page': 1, 'per_page': 5,
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
      final list = (r.data as List<dynamic>?) ?? [];
      return list.isNotEmpty ? list : _staticNews;
    },
    fromJson: (d) => (d as List<dynamic>),
  );
  if (data == null || data.isEmpty) return _staticNews;
  return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
});

const _staticNews = [
  {
    'titre':     'Coupe du Monde 2026 — Les groupes dévoilés',
    'resume':    "La FIFA a officialisé les groupes. Le Brésil, la France et l'Angleterre dans le même chapeau.",
    'date':      "Aujourd'hui",
    'emoji':     '🌍',
    'categorie': 'Coupe du Monde',
    'image_url': 'https://images.unsplash.com/photo-1551958219-acbc17c2f7e4?w=400&q=80',
  },
  {
    'titre':     'Ligue des Champions — Demi-finales confirmées',
    'resume':    'Real Madrid vs Bayern et Arsenal vs PSG. Les affiches qui font rêver l\'Europe.',
    'date':      'Hier',
    'emoji':     '⚽',
    'categorie': 'Champions League',
    'image_url': 'https://images.unsplash.com/photo-1574629810360-7efbbe195018?w=400&q=80',
  },
  {
    'titre':     'Premier League — Course au titre serrée',
    'resume':    'Man City et Arsenal à égalité de points à 4 journées de la fin.',
    'date':      'Il y a 2j',
    'emoji':     '🏴󠁧󠁢󠁥󠁮󠁧󠁿',
    'categorie': 'Premier League',
    'image_url': 'https://images.unsplash.com/photo-1522778119026-d647f0596c20?w=400&q=80',
  },
  {
    'titre':     "Serie A — L'Inter Milan champion ?",
    'resume':    "Avec 8 points d'avance, les Nerazzurri semblent intouchables.",
    'date':      'Il y a 3j',
    'emoji':     '🇮🇹',
    'categorie': 'Serie A',
  },
];

// ─── Prochain match à venir ───────────────────────────────────────────────────

final nextPronosticProvider =
    FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  const key = 'pronostics_week';
  final data = await _fetchWithCache<List<dynamic>>(
    ref:      ref,
    cacheKey: key,
    fetchFn:  () async {
      final r = await ref.read(dioProvider).get('/pronostics', queryParameters: {
        'date_filter': 'week', 'page': 1, 'per_page': 20,
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

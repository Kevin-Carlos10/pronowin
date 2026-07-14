import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../core/cache/cache_service.dart';

final profileProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  const cacheKey = 'profile';
  try {
    final r    = await ref.read(dioProvider).get('/auth/profile');
    final data = r.data as Map<String, dynamic>;
    await CacheService.save(cacheKey, data);
    return data;
  } catch (_) {
    final cached = await CacheService.load<Map<String, dynamic>>(
      cacheKey,
      (d) => d as Map<String, dynamic>,
    );
    if (cached != null) return cached;
    rethrow;
  }
});

// Stats PronoWin (30 derniers jours)
final userStatsProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  const cacheKey = 'profile_stats';
  const empty = {'pronostics_suivis': 0, 'taux_reussite': 0.0, 'serie_gagnante': 0};
  try {
    final r    = await ref.read(dioProvider).get('/profile/stats');
    final data = r.data as Map<String, dynamic>;
    await CacheService.save(cacheKey, data);
    return data;
  } catch (_) {
    return await CacheService.loadStale<Map<String, dynamic>>(
      cacheKey, (d) => d as Map<String, dynamic>) ?? empty;
  }
});

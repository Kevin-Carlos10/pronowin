import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../core/cache/cache_service.dart';
import '../../domain/entities/leaderboard_entity.dart';

// ─── Filtre période ────────────────────────────────────────────────────────────
final leaderboardPeriodProvider =
    StateProvider<LeaderboardPeriod>((ref) => LeaderboardPeriod.monthly);

// ─── Données classement ────────────────────────────────────────────────────────
final leaderboardProvider =
    FutureProvider.autoDispose.family<List<LeaderboardEntry>, LeaderboardPeriod>(
  (ref, period) async {
    final periodParam = switch (period) {
      LeaderboardPeriod.allTime  => 'all_time',
      LeaderboardPeriod.monthly  => 'monthly',
      LeaderboardPeriod.weekly   => 'weekly',
    };
    final cacheKey = 'leaderboard_$periodParam';

    List<LeaderboardEntry> parseEntries(dynamic raw) {
      final list = (raw as List?) ?? [];
      return list.asMap().entries.map((e) {
        final j = e.value as Map<String, dynamic>;
        return LeaderboardEntry(
          rank:             (j['rank']              as num?)?.toInt() ?? (e.key + 1),
          userId:           j['user_id']            as String? ?? '',
          pseudo:           j['pseudo']             as String? ?? 'Inconnu',
          avatarUrl:        j['avatar_url']         as String?,
          totalPredictions: (j['total_predictions'] as num?)?.toInt() ?? 0,
          wonPredictions:   (j['won_predictions']   as num?)?.toInt() ?? 0,
          winRate:          (j['win_rate']          as num?)?.toDouble() ?? 0,
          totalPoints:      (j['total_points']      as num?)?.toInt() ?? 0,
          isPremium:        j['is_premium']         as bool? ?? false,
          badge:            j['badge']              as String?,
        );
      }).toList();
    }

    try {
      final r    = await ref.read(dioProvider).get('/leaderboard',
          queryParameters: {'period': periodParam, 'limit': 50});
      final list = r.data['data'] as List?;
      final entries = parseEntries(list);
      await CacheService.save(cacheKey, list ?? []);
      return entries;
    } catch (_) {
      final cached = await CacheService.load<List<LeaderboardEntry>>(
        cacheKey, (d) => parseEntries(d));
      if (cached != null && cached.isNotEmpty) return cached;

      // Rien en cache : on laisse l'erreur remonter. `ClassementPage` a déjà
      // un état d'erreur avec un bouton « réessayer » — il n'attendait que
      // d'être atteint.
      //
      // Ce que ce `rethrow` remplace tenait en quinze lignes : une liste de
      // parieurs inventés — pseudos, nombres de paris, taux de réussite de 65
      // à 87 % — affichée telle quelle, sans la moindre mention qu'elle était
      // fictive. L'écran ne les distinguait en rien de vrais classés, podium
      // et badges compris.
      //
      // Sur une application de paris, c'est le mensonge le plus coûteux qu'on
      // puisse afficher : il ne trompe pas sur un détail d'interface, il donne
      // une idée fausse de ce qu'on peut espérer gagner. Et il apparaissait
      // précisément au pire moment — premier lancement, mauvaise connexion,
      // cache vide — c'est-à-dire chez l'utilisateur qui n'a encore aucun
      // moyen de recouper.
      rethrow;
    }
  },
);

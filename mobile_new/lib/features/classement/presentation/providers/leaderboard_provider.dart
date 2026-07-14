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
      return _demoEntries();
    }
  },
);

List<LeaderboardEntry> _demoEntries() => [
  const LeaderboardEntry(rank: 1,  userId: 'u1',  pseudo: 'ProMaster',   winRate: 0.87, totalPredictions: 312, wonPredictions: 271, totalPoints: 2840, isPremium: true,  badge: 'legend'),
  const LeaderboardEntry(rank: 2,  userId: 'u2',  pseudo: 'FootballKing', winRate: 0.83, totalPredictions: 287, wonPredictions: 238, totalPoints: 2560, isPremium: true,  badge: 'expert'),
  const LeaderboardEntry(rank: 3,  userId: 'u3',  pseudo: 'Tipster225',  winRate: 0.81, totalPredictions: 204, wonPredictions: 165, totalPoints: 2210, isPremium: true,  badge: 'expert'),
  const LeaderboardEntry(rank: 4,  userId: 'u4',  pseudo: 'BetWizard',   winRate: 0.78, totalPredictions: 189, wonPredictions: 147, totalPoints: 1980, isPremium: true,  badge: null),
  const LeaderboardEntry(rank: 5,  userId: 'u5',  pseudo: 'AfroPronos',  winRate: 0.76, totalPredictions: 167, wonPredictions: 127, totalPoints: 1740, isPremium: false, badge: 'rising'),
  const LeaderboardEntry(rank: 6,  userId: 'u6',  pseudo: 'DioubaCity',  winRate: 0.74, totalPredictions: 143, wonPredictions: 106, totalPoints: 1580, isPremium: true,  badge: null),
  const LeaderboardEntry(rank: 7,  userId: 'u7',  pseudo: 'LaBaule226',  winRate: 0.73, totalPredictions: 198, wonPredictions: 144, totalPoints: 1450, isPremium: false, badge: null),
  const LeaderboardEntry(rank: 8,  userId: 'u8',  pseudo: 'TipsHunter',  winRate: 0.71, totalPredictions: 122, wonPredictions:  87, totalPoints: 1320, isPremium: true,  badge: null),
  const LeaderboardEntry(rank: 9,  userId: 'u9',  pseudo: 'BurkinaTips', winRate: 0.70, totalPredictions: 155, wonPredictions: 108, totalPoints: 1210, isPremium: false, badge: null),
  const LeaderboardEntry(rank: 10, userId: 'u10', pseudo: 'OuagaFoot',   winRate: 0.69, totalPredictions: 134, wonPredictions:  92, totalPoints: 1100, isPremium: false, badge: 'rising'),
  const LeaderboardEntry(rank: 11, userId: 'u11', pseudo: 'Sergei225',   winRate: 0.68, totalPredictions: 111, wonPredictions:  75, totalPoints: 1020, isPremium: false, badge: null),
  const LeaderboardEntry(rank: 12, userId: 'u12', pseudo: 'LagosKing',   winRate: 0.67, totalPredictions:  98, wonPredictions:  66, totalPoints:  940, isPremium: false, badge: null),
  const LeaderboardEntry(rank: 13, userId: 'u13', pseudo: 'AbidjanFC',   winRate: 0.66, totalPredictions:  87, wonPredictions:  57, totalPoints:  880, isPremium: false, badge: null),
  const LeaderboardEntry(rank: 14, userId: 'u14', pseudo: 'DakarBet',    winRate: 0.65, totalPredictions:  76, wonPredictions:  49, totalPoints:  810, isPremium: false, badge: null),
  const LeaderboardEntry(rank: 15, userId: 'u15', pseudo: 'BamakoPro',   winRate: 0.64, totalPredictions:  68, wonPredictions:  43, totalPoints:  760, isPremium: false, badge: null),
];

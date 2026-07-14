import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/dio_client.dart';

class StreakData {
  final int    streakDays;
  final int    xpTotal;
  final bool   todayClaimed;
  final int    nextMilestone;
  final List<int> milestones;

  const StreakData({
    required this.streakDays,
    required this.xpTotal,
    required this.todayClaimed,
    required this.nextMilestone,
    required this.milestones,
  });

  /// XP gagné aujourd'hui (estimé depuis le streak)
  int get xpEarnedToday {
    if (!todayClaimed) return 0;
    if (streakDays >= 30) return 50;
    if (streakDays >= 14) return 30;
    if (streakDays >= 7)  return 20;
    if (streakDays >= 3)  return 15;
    return 10;
  }

  bool get isMilestone => [3, 7, 14, 30].contains(streakDays);

  /// Progression vers le prochain milestone (0.0 → 1.0)
  double progressToNext(int prev) {
    if (nextMilestone <= prev) return 1.0;
    return (streakDays - prev) / (nextMilestone - prev);
  }
}

final streakProvider = FutureProvider.autoDispose<StreakData>((ref) async {
  final dio = ref.read(dioProvider);
  final r   = await dio.get('/auth/streak');
  final d   = r.data as Map<String, dynamic>;
  return StreakData(
    streakDays:    (d['streakDays']    as num).toInt(),
    xpTotal:       (d['xpTotal']       as num).toInt(),
    todayClaimed:  d['todayClaimed']   as bool? ?? false,
    nextMilestone: (d['nextMilestone'] as num).toInt(),
    milestones:    (d['milestones']    as List).map((e) => (e as num).toInt()).toList(),
  );
});

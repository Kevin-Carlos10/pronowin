import 'package:equatable/equatable.dart';

enum LeaderboardPeriod { allTime, monthly, weekly }

class LeaderboardEntry extends Equatable {
  final int    rank;
  final String userId;
  final String pseudo;
  final String? avatarUrl;
  final int    totalPredictions;
  final int    wonPredictions;
  final double winRate;       // 0..1
  final int    totalPoints;
  final bool   isPremium;
  final String? badge;        // "legend", "expert", "rising", null

  const LeaderboardEntry({
    required this.rank,
    required this.userId,
    required this.pseudo,
    this.avatarUrl,
    required this.totalPredictions,
    required this.wonPredictions,
    required this.winRate,
    required this.totalPoints,
    required this.isPremium,
    this.badge,
  });

  int get lostPredictions => totalPredictions - wonPredictions;

  String get winRateLabel => '${(winRate * 100).toStringAsFixed(1)}%';

  @override
  List<Object?> get props => [userId];
}

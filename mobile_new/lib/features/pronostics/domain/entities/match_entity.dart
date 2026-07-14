import 'package:equatable/equatable.dart';

enum PredictionType  { win1, draw, win2, btts, over25, under25, over35, under35 }
enum MatchStatus     { upcoming, live, finished }
enum ConfidenceLevel { low, medium, high, veryHigh }

class MatchEntity extends Equatable {
  final String id;
  final String league;
  final String leagueCountry;
  final String homeTeam;
  final String awayTeam;
  final String? homeTeamLogo;
  final String? awayTeamLogo;
  final DateTime matchDate;
  final MatchStatus status;
  final int? homeScore;
  final int? awayScore;
  final PredictionType predictionType;
  final String predictionLabel;
  final double oddsRecommended;
  final double oddsHome;
  final double oddsDraw;
  final double oddsAway;
  final int confidenceScore;
  final bool isPremium;
  final String? analystNote;
  final int homeFormPoints;
  final int awayFormPoints;
  final double? aiProbability;
  final String? aiExplanation;
  /// false = match en base sans pronostic publié
  final bool hasPronostic;

  const MatchEntity({
    required this.id,
    required this.league,
    required this.leagueCountry,
    required this.homeTeam,
    required this.awayTeam,
    this.homeTeamLogo,
    this.awayTeamLogo,
    required this.matchDate,
    required this.status,
    this.homeScore,
    this.awayScore,
    required this.predictionType,
    required this.predictionLabel,
    required this.oddsRecommended,
    required this.oddsHome,
    required this.oddsDraw,
    required this.oddsAway,
    required this.confidenceScore,
    required this.isPremium,
    this.analystNote,
    required this.homeFormPoints,
    required this.awayFormPoints,
    this.aiProbability,
    this.aiExplanation,
    this.hasPronostic = true,
  });

  ConfidenceLevel get confidence {
    if (confidenceScore >= 5) return ConfidenceLevel.veryHigh;
    if (confidenceScore >= 4) return ConfidenceLevel.high;
    if (confidenceScore >= 3) return ConfidenceLevel.medium;
    return ConfidenceLevel.low;
  }

  bool get isToday {
    final now = DateTime.now();
    return matchDate.year == now.year && matchDate.month == now.month && matchDate.day == now.day;
  }

  bool get isTomorrow {
    final t = DateTime.now().add(const Duration(days: 1));
    return matchDate.year == t.year && matchDate.month == t.month && matchDate.day == t.day;
  }

  /// null si match non terminé, true si pronostic correct, false sinon
  bool? get predictionWon {
    if (status != MatchStatus.finished) return null;
    final h = homeScore ?? 0;
    final a = awayScore ?? 0;
    return switch (predictionType) {
      PredictionType.win1    => h > a,
      PredictionType.draw    => h == a,
      PredictionType.win2    => a > h,
      PredictionType.btts    => h > 0 && a > 0,
      PredictionType.over25  => (h + a) > 2,
      PredictionType.under25 => (h + a) < 3,
      PredictionType.over35  => (h + a) > 3,
      PredictionType.under35 => (h + a) < 4,
    };
  }

  @override
  List<Object?> get props => [id, hasPronostic];
}

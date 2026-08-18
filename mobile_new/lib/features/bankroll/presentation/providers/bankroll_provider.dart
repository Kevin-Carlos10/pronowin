import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/dio_client.dart';
import '../../../pronostics/domain/entities/match_entity.dart' show MatchEntity;

// ─── Entités ──────────────────────────────────────────────────────────────────
class BankrollBet {
  final String  id;
  final String  pronosticId;
  final String  matchId;
  final double  stakedAmount;
  final double  suggestedAmount;
  final double  oddsUsed;
  final double  potentialGain;
  final String? result;    // 'WIN' | 'LOSS' | null
  final double? profit;
  final DateTime createdAt;
  final DateTime? settledAt;
  final String  homeTeam;
  final String  awayTeam;
  final String  league;
  final String  predictionLabel;
  final int     confidenceScore;
  final String  currency;

  const BankrollBet({
    required this.id,
    required this.pronosticId,
    required this.matchId,
    required this.stakedAmount,
    required this.suggestedAmount,
    required this.oddsUsed,
    required this.potentialGain,
    this.result,
    this.profit,
    required this.createdAt,
    this.settledAt,
    required this.homeTeam,
    required this.awayTeam,
    required this.league,
    required this.predictionLabel,
    required this.confidenceScore,
    required this.currency,
  });

  // La devise n'est pas répétée dans le JSON de chaque pari — c'est une
  // propriété du bankroll parent, transmise explicitement par l'appelant.
  factory BankrollBet.fromJson(Map<String, dynamic> j, {required String currency}) => BankrollBet(
    id:              j['id'] as String,
    pronosticId:     j['pronostic_id'] as String,
    matchId:         (j['match'] as Map)['id'] as String? ?? '',
    stakedAmount:    (j['staked_amount'] as num).toDouble(),
    suggestedAmount: (j['suggested_amount'] as num).toDouble(),
    oddsUsed:        (j['odds_used'] as num).toDouble(),
    potentialGain:   (j['potential_gain'] as num).toDouble(),
    result:          j['result'] as String?,
    profit:          (j['profit'] as num?)?.toDouble(),
    createdAt:       DateTime.parse(j['created_at'] as String).toLocal(),
    settledAt:       j['settled_at'] != null
        ? DateTime.tryParse(j['settled_at'] as String) : null,
    homeTeam:        (j['match'] as Map)['home_team'] as String,
    awayTeam:        (j['match'] as Map)['away_team'] as String,
    league:          (j['match'] as Map)['league'] as String,
    predictionLabel: j['prediction_label'] as String,
    confidenceScore: (j['confidence_score'] as num).toInt(),
    currency:        currency,
  );

  /// [predictionLabel] avec "Domicile"/"Extérieur" remplacés par le nom réel
  /// de l'équipe — voir [MatchEntity.applyTeamNames].
  String get displayPredictionLabel =>
      MatchEntity.applyTeamNames(predictionLabel, homeTeam: homeTeam, awayTeam: awayTeam);
}

class BankrollData {
  final String id;
  final double totalBudget;
  final double currentBalance;
  final String currency;
  final List<BankrollBet> bets;

  const BankrollData({
    required this.id,
    required this.totalBudget,
    required this.currentBalance,
    required this.currency,
    required this.bets,
  });

  factory BankrollData.fromJson(Map<String, dynamic> j) => BankrollData(
    id:             j['id'] as String,
    totalBudget:    (j['total_budget'] as num).toDouble(),
    currentBalance: (j['current_balance'] as num).toDouble(),
    currency:       j['currency'] as String,
    bets: (j['bets'] as List)
        .map((b) => BankrollBet.fromJson(b as Map<String, dynamic>, currency: j['currency'] as String))
        .toList(),
  );

  double get progressPct =>
      totalBudget > 0 ? (currentBalance / totalBudget).clamp(0.0, 2.0) : 0.0;

  bool get isProfit => currentBalance >= totalBudget;
}

class BankrollStats {
  final double totalBudget;
  final double currentBalance;
  final String currency;
  final int    totalBets;
  final int    wins;
  final int    losses;
  final double winRate;
  final double totalProfit;
  final double totalStaked;
  final double roi;

  const BankrollStats({
    required this.totalBudget,
    required this.currentBalance,
    required this.currency,
    required this.totalBets,
    required this.wins,
    required this.losses,
    required this.winRate,
    required this.totalProfit,
    required this.totalStaked,
    required this.roi,
  });

  factory BankrollStats.fromJson(Map<String, dynamic> j) => BankrollStats(
    totalBudget:    (j['totalBudget']    as num).toDouble(),
    currentBalance: (j['currentBalance'] as num).toDouble(),
    currency:       j['currency'] as String,
    totalBets:      (j['totalBets']  as num).toInt(),
    wins:           (j['wins']       as num).toInt(),
    losses:         (j['losses']     as num).toInt(),
    winRate:        (j['winRate']    as num).toDouble(),
    totalProfit:    (j['totalProfit'] as num).toDouble(),
    totalStaked:    (j['totalStaked'] as num).toDouble(),
    roi:            (j['roi']         as num).toDouble(),
  );
}

// ─── Providers ────────────────────────────────────────────────────────────────
final bankrollProvider = FutureProvider.autoDispose<BankrollData?>((ref) async {
  final dio = ref.read(dioProvider);
  final r   = await dio.get('/bankroll');
  if (r.data == null) return null;
  return BankrollData.fromJson(r.data as Map<String, dynamic>);
});

final bankrollStatsProvider = FutureProvider.autoDispose<BankrollStats?>((ref) async {
  final dio = ref.read(dioProvider);
  final r   = await dio.get('/bankroll/stats');
  if (r.data == null) return null;
  return BankrollStats.fromJson(r.data as Map<String, dynamic>);
});

// Mise suggérée pour un pronostic donné (confidence score)
final suggestedStakeProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, int>((ref, confidenceScore) async {
  final dio = ref.read(dioProvider);
  final r   = await dio.get('/bankroll/suggest',
      queryParameters: {'confidence': confidenceScore});
  return r.data as Map<String, dynamic>;
});

// Set des matchIds sur lesquels l'user a déjà misé (pour les pastilles sur les cartes)
final betMatchIdsProvider = Provider.autoDispose<Set<String>>((ref) {
  final bankrollAsync = ref.watch(bankrollProvider);
  return bankrollAsync.valueOrNull?.bets
      .map((b) => b.matchId)
      .where((id) => id.isNotEmpty)
      .toSet() ?? {};
});

// Vérifie si l'user a déjà misé sur un pronostic précis
final hasBetOnPronosticProvider = Provider.autoDispose.family<bool, String>((ref, pronosticId) {
  final bankrollAsync = ref.watch(bankrollProvider);
  final bets = bankrollAsync.valueOrNull?.bets ?? [];
  return bets.any((b) => b.pronosticId == pronosticId);
});

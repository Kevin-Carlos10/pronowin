import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/dio_client.dart';
import 'package:pronowin/core/utils/noms_equipes.dart';

class PeriodScore {
  final int? home, away;
  const PeriodScore({this.home, this.away});
  factory PeriodScore.fromJson(Map<String, dynamic> j) =>
      PeriodScore(home: j['home'] as int?, away: j['away'] as int?);
  bool get available => home != null || away != null;
  String get label => '${home ?? '—'} – ${away ?? '—'}';
}

class MatchInfo {
  final String? venue, city, referee, round, phase, homeTeam, awayTeam;
  final int? season, elapsed, extra;
  final DateTime? updatedAt;
  final bool stale;
  final Map<String, PeriodScore> scores;
  const MatchInfo({
    this.venue,
    this.city,
    this.referee,
    this.round,
    this.phase,
    this.homeTeam,
    this.awayTeam,
    this.season,
    this.elapsed,
    this.extra,
    this.updatedAt,
    this.stale = false,
    this.scores = const {},
  });
  factory MatchInfo.fromJson(Map<String, dynamic> j) {
    final venue = j['venue'] as Map<String, dynamic>? ?? {};
    final scores = j['scores'] as Map<String, dynamic>? ?? {};
    return MatchInfo(
      venue: venue['name'] as String?,
      city: venue['city'] as String?,
      referee: j['referee'] as String?,
      round: j['round'] as String?,
      phase: j['phase'] as String?,
      homeTeam: nomEquipeOuNul(j['home_team'] as String?),
      awayTeam: nomEquipeOuNul(j['away_team'] as String?),
      season: j['season'] as int?,
      elapsed: j['elapsed'] as int?,
      extra: j['extra'] as int?,
      updatedAt: DateTime.tryParse(j['updated_at'] as String? ?? ''),
      stale: j['stale'] == true,
      scores: {
        for (final key in ['halftime', 'fulltime', 'extratime', 'penalty'])
          key: PeriodScore.fromJson(scores[key] as Map<String, dynamic>? ?? {}),
      },
    );
  }
}

final matchInfoProvider = FutureProvider.autoDispose.family<MatchInfo?, String>(
  (ref, id) async {
    try {
      final response = await ref
          .read(dioProvider)
          .get('/pronostics/$id/match-info');
      return MatchInfo.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  },
);

import '../../domain/entities/match_entity.dart';

class MatchModel extends MatchEntity {
  const MatchModel({
    required super.id,
    required super.league,
    required super.leagueCountry,
    required super.homeTeam,
    required super.awayTeam,
    super.homeTeamLogo,
    super.awayTeamLogo,
    required super.matchDate,
    required super.status,
    super.homeScore,
    super.awayScore,
    super.hasPronostic = true,
    required super.predictionType,
    required super.predictionLabel,
    super.isLocked,
    required super.oddsRecommended,
    required super.oddsHome,
    required super.oddsDraw,
    required super.oddsAway,
    required super.confidenceScore,
    super.confidencePct,
    required super.isPremium,
    super.analystNote,
    super.analystNoteEn, super.predictionLabelEn,
    required super.homeFormPoints,
    required super.awayFormPoints,
    super.aiProbability,
    super.aiExplanation,
    super.result,
  });

  factory MatchModel.fromJson(Map<String, dynamic> j) => MatchModel(
    id:              j['id'] as String,
    league:          j['league'] as String,
    leagueCountry:   j['league_country'] as String? ?? '',
    homeTeam:        j['home_team'] as String,
    awayTeam:        j['away_team'] as String,
    homeTeamLogo:    j['home_team_logo'] as String?,
    awayTeamLogo:    j['away_team_logo'] as String?,
    // `.toLocal()` est indispensable, pas cosmétique : l'API sérialise en Zulu
    // ("2026-08-11T09:30:00.000Z"), et `DateTime.parse` rend alors un DateTime
    // dont `isUtc` vaut true. Tous ses getters (.hour, .day) et `DateFormat`
    // renvoient donc les composantes UTC. Sans cette conversion, l'app affichait
    // partout l'heure du serveur au lieu de celle du parieur — y compris dans le
    // message de partage envoyé à ses contacts.
    matchDate:       DateTime.parse(j['match_date'] as String).toLocal(),
    status:          _parseStatus(j['status'] as String?),
    homeScore:       j['home_score'] as int?,
    awayScore:       j['away_score'] as int?,
    hasPronostic:    j['has_pronostic'] as bool? ?? true,
    predictionType:  _parsePrediction(j['prediction_type'] as String?),
    predictionLabel: j['prediction_label'] as String? ?? '',
    isLocked: j['locked'] as bool? ?? false,
    oddsRecommended: (j['odds_recommended'] as num?)?.toDouble() ?? 0.0,
    oddsHome:        (j['odds_home'] as num?)?.toDouble() ?? 0.0,
    oddsDraw:        (j['odds_draw'] as num?)?.toDouble() ?? 0.0,
    oddsAway:        (j['odds_away'] as num?)?.toDouble() ?? 0.0,
    confidenceScore: j['confidence_score'] as int? ?? 1,
    confidencePct:   (j['confidence_pct'] as num?)?.toInt(),
    isPremium:       j['is_premium'] as bool? ?? false,
    analystNote:     j['analyst_note'] as String?,
    analystNoteEn: j['analyst_note_en'] as String?, predictionLabelEn: j['prediction_label_en'] as String?,
    homeFormPoints:  j['home_form_points'] as int? ?? 0,
    awayFormPoints:  j['away_form_points'] as int? ?? 0,
    aiProbability:   (j['ai_probability'] as num?)?.toDouble(),
    aiExplanation:   j['ai_explanation'] as String?,
    result:          _parseResult(j['result'] as String?),
  );

  Map<String, dynamic> toJson() => {
    'id':               id,
    'league':           league,
    'league_country':   leagueCountry,
    'home_team':        sourceHomeTeam,
    'away_team':        sourceAwayTeam,
    'home_team_logo':   homeTeamLogo,
    'away_team_logo':   awayTeamLogo,
    'match_date':       matchDate.toIso8601String(),
    'status':           status.name,
    'home_score':       homeScore,
    'away_score':       awayScore,
    'has_pronostic':    hasPronostic,
    'prediction_type':  predictionType.name,
    'prediction_label': sourcePredictionLabel,
    'prediction_label_en': predictionLabelEn,
    'locked': isLocked,
    'odds_recommended': oddsRecommended,
    'odds_home':        oddsHome,
    'odds_draw':        oddsDraw,
    'odds_away':        oddsAway,
    'confidence_score': confidenceScore,
    'confidence_pct':   confidencePct,
    'is_premium':       isPremium,
    'analyst_note':     sourceAnalystNote,
    'analyst_note_en': analystNoteEn,
    'home_form_points': homeFormPoints,
    'away_form_points': awayFormPoints,
    'result':           switch (result) {
      PronosticResult.win  => 'WIN',
      PronosticResult.loss => 'LOSS',
      PronosticResult.push => 'PUSH',
      null                 => null,
    },
  };

  static MatchStatus _parseStatus(String? s) => switch (s) {
    'live'     => MatchStatus.live,
    'finished' => MatchStatus.finished,
    _          => MatchStatus.upcoming,
  };

  static PredictionType _parsePrediction(String? s) => switch (s) {
    'win1'    => PredictionType.win1,
    'draw'    => PredictionType.draw,
    'win2'    => PredictionType.win2,
    'btts'    => PredictionType.btts,
    'over25'  => PredictionType.over25,
    'under25' => PredictionType.under25,
    'over35'  => PredictionType.over35,
    'under35' => PredictionType.under35,
    'other'   => PredictionType.other,
    _         => PredictionType.other,
  };

  static PronosticResult? _parseResult(String? s) => switch (s) {
    'WIN'  => PronosticResult.win,
    'LOSS' => PronosticResult.loss,
    'PUSH' => PronosticResult.push,
    _      => null,
  };
}

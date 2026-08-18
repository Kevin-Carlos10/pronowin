import 'package:equatable/equatable.dart';

enum PredictionType  { win1, draw, win2, btts, over25, under25, over35, under35, other }
enum MatchStatus     { upcoming, live, finished }
enum ConfidenceLevel { low, medium, high, veryHigh }
/// Résultat réglé côté backend (moteur de règlement — cf. pronostics.service.ts).
/// PUSH = marché remboursé (ex. handicap asiatique sur ligne ronde) : ni gain ni perte.
enum PronosticResult { win, loss, push }

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

  /// Le serveur a retiré le pronostic de la réponse (contenu premium hors
  /// abonnement). Distingue « pas encore de pronostic » de « pronostic
  /// existant mais masqué » — sans ça, un abonnement expiré côté serveur
  /// mais encore valide dans l'état local afficherait une carte vide.
  final bool isLocked;
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
  /// Résultat réglé côté backend — source de vérité (moteur de règlement
  /// couvrant tous les marchés, pas seulement les 8 types de base).
  final PronosticResult? result;

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
    this.isLocked = false,
    this.result,
  });

  ConfidenceLevel get confidence {
    if (confidenceScore >= 5) return ConfidenceLevel.veryHigh;
    if (confidenceScore >= 4) return ConfidenceLevel.high;
    if (confidenceScore >= 3) return ConfidenceLevel.medium;
    return ConfidenceLevel.low;
  }

  /// Score de confiance (1-5, fixé par l'admin) exprimé en pourcentage rond,
  /// plus lisible et plus "data" que des étoiles. Plafonné à 95% (jamais 100%) :
  /// aucun résultat sportif n'est certain, un "100%" affiché sonnerait comme
  /// une garantie absolue plutôt qu'une estimation de confiance.
  int get confidencePercent => percentForConfidence(confidenceScore);

  static const Map<int, int> _confidencePercentByScore = {1: 60, 2: 70, 3: 80, 4: 90, 5: 95};

  /// Même conversion que [confidencePercent], utilisable sans instance de
  /// [MatchEntity] (ex: un score lu depuis une Map brute d'API).
  static int percentForConfidence(int score) =>
      _confidencePercentByScore[score.clamp(1, 5)]!;

  /// Libellé de confiance — **source unique**.
  ///
  /// Quatre échelles cohabitaient dans l'app : un score de 4 s'affichait
  /// « Excellent » sur l'accueil, « Bon » sur la liste des pronostics et
  /// « Fort » sur la carte de partage. On garde les cinq paliers, qui sont
  /// les seuls à correspondre au score réellement stocké (1 à 5).
  static const Map<int, String> _confidenceLabelByScore = {
    1: 'Risqué', 2: 'Faible', 3: 'Moyen', 4: 'Bon', 5: 'Excellent',
  };

  static String labelForConfidence(int score) =>
      _confidenceLabelByScore[score.clamp(1, 5)]!;

  String get confidenceLabel => labelForConfidence(confidenceScore);

  /// `matchDate` est censé être local (converti au parsing dans `MatchModel`),
  /// mais on ne peut pas le garantir pour toutes les voies de construction —
  /// et comparer un instant UTC à un `DateTime.now()` local rangeait les matchs
  /// du mauvais côté de minuit. Le `.toLocal()` est idempotent, il ne coûte
  /// rien quand la conversion a déjà eu lieu.
  bool _memeJourQue(DateTime autre) {
    final d = matchDate.toLocal();
    return d.year == autre.year && d.month == autre.month && d.day == autre.day;
  }

  bool get isToday => _memeJourQue(DateTime.now());

  bool get isTomorrow =>
      _memeJourQue(DateTime.now().add(const Duration(days: 1)));

  /// Raccourci booléen pour le résultat — true/false pour WIN/LOSS, null si
  /// non résolu OU remboursé (PUSH, ni gain ni perte). Les widgets qui
  /// doivent distinguer le remboursement du "pas encore résolu" doivent lire
  /// [result] directement plutôt que ce raccourci.
  bool? get predictionWon => switch (result) {
    PronosticResult.win  => true,
    PronosticResult.loss => false,
    PronosticResult.push => null,
    null                 => null,
  };

  static final _domicileRe  = RegExp(r'\bDomicile\b');
  static final _exterieurRe = RegExp(r'\bExtérieur\b');

  /// Remplace les camps génériques "Domicile"/"Extérieur" par le nom réel de
  /// l'équipe dans un libellé de pronostic — filet de sécurité pour les
  /// pronostics publiés avant que le formulaire admin ne compose déjà le
  /// libellé avec le nom de l'équipe (marchés issus de l'accordéon 1xBet,
  /// ex. "Vainqueur du match : Domicile"). Statique et réutilisable par les
  /// widgets qui travaillent sur les réponses API brutes (`Map<String,dynamic>`)
  /// plutôt que sur un MatchEntity (ex. cartes de la page Accueil).
  static String applyTeamNames(String label, {required String homeTeam, required String awayTeam}) =>
      label.replaceAll(_domicileRe, homeTeam).replaceAll(_exterieurRe, awayTeam);

  /// [predictionLabel] avec les camps génériques substitués — voir [applyTeamNames].
  String get displayPredictionLabel =>
      MatchEntity.applyTeamNames(predictionLabel, homeTeam: homeTeam, awayTeam: awayTeam);

  @override
  List<Object?> get props => [id, hasPronostic];
}

import 'package:pronowin/l10n/app_strings.dart';
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
  /// Niveau 1–5, déduit par le serveur de l'indice saisi. Sert aux couleurs
  /// et aux libellés (« Élevée »), et au barème de mise — pas à l'affichage.
  final int confidenceScore;
  /// Indice de confiance saisi par l'analyste, en pourcentage (1–99). Nul si
  /// le serveur ne l'envoie pas encore : voir [pourcentageConfiance].
  final int? confidencePct;
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
    this.confidencePct,
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

  /// Appréciation éditoriale de l'analyste, pas une probabilité de victoire.
  static bool validConfidence(int score) => score >= 1 && score <= 5;

  // ── Indice de confiance en pourcentage ─────────────────────────────────
  //
  // L'analyste saisit un pourcentage (1 à 99) ; c'est lui qu'on affiche. Le
  // niveau 1–5 en est déduit par paliers de 20 points — même règle que le
  // serveur (backend/src/utils/confiance.ts). Un pronostic sans pourcentage
  // (antérieur à la saisie, ou serveur pas encore à jour) prend le milieu de
  // son palier : 1 → 10, 2 → 30, 3 → 50, 4 → 70, 5 → 90.

  /// Le pourcentage à afficher. 0 : pas de confiance publiée.
  int get pourcentageConfiance => confidencePct ?? pourcentageDepuisNiveau(confidenceScore);

  static int pourcentageDepuisNiveau(int score) => validConfidence(score) ? score * 20 - 10 : 0;

  static int niveauDepuisPourcentage(int pct) =>
      pct >= 80 ? 5 : pct >= 60 ? 4 : pct >= 40 ? 3 : pct >= 20 ? 2 : pct >= 1 ? 1 : 0;

  /// Le pourcentage d'un pronostic reçu tel quel de l'API (cartes de
  /// l'accueil, qui lisent les réponses brutes).
  static int pourcentageDepuisApi(Map<dynamic, dynamic> p) =>
      (p['confidence_pct'] as num?)?.toInt() ??
      pourcentageDepuisNiveau((p['confidence_score'] as num?)?.toInt() ?? 0);

  /// « 73 % », ou « Non évaluée ».
  static String affichageConfiance(int pct) =>
      pct >= 1 ? trCurrent("{arg0} %", [pct]) : trCurrent("Non évaluée");


  /// Libellé de confiance — **source unique**.
  ///
  /// Quatre échelles cohabitaient dans l'app : un score de 4 s'affichait
  /// « Excellent » sur l'accueil, « Bon » sur la liste des pronostics et
  /// « Fort » sur la carte de partage. On garde les cinq paliers, qui sont
  /// les seuls à correspondre au score réellement stocké (1 à 5).
  static const Map<int, String> _confidenceLabelByScore = {
    1: 'Très faible', 2: 'Faible', 3: 'Modérée', 4: 'Élevée', 5: 'Très élevée',
  };

  static String labelForConfidence(int score) =>
      trCurrent(_confidenceLabelByScore[score] ?? "Non évaluée");

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

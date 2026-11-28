import 'package:pronowin/l10n/editorial_text.dart';
import 'package:pronowin/l10n/app_strings.dart';
import 'package:equatable/equatable.dart';
import 'package:pronowin/core/utils/noms_equipes.dart';
import 'package:pronowin/l10n/football_labels.dart';

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
  final String _homeTeam;
  String get homeTeam => nomEquipe(_homeTeam);
  final String _awayTeam;
  String get awayTeam => nomEquipe(_awayTeam);
  // Cache/serialization uses provider data, not the current display language.
  String get sourceHomeTeam => _homeTeam;
  String get sourceAwayTeam => _awayTeam;
  final String? homeTeamLogo;
  final String? awayTeamLogo;
  final DateTime matchDate;
  final MatchStatus status;
  final int? homeScore;
  final int? awayScore;
  /// Minute de jeu publiée par la source, pendant le direct seulement.
  ///
  /// Les listes n'affichaient que « En direct » là où Sofascore donne « 67' »
  /// (vidéos du 8 novembre 2026) : sans la minute, impossible de savoir si un
  /// 0-0 en direct est à la 5e ou à la 85e.
  final int? elapsed;
  final PredictionType predictionType;
  final String _predictionLabel;
  final String? predictionLabelEn;
  String get predictionLabel => editorialText(_predictionLabel, predictionLabelEn);
  String get sourcePredictionLabel => _predictionLabel;

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
  final String? _analystNote;
  final String? analystNoteEn;
  String? get analystNote => _analystNote == null && analystNoteEn == null ? null : editorialText(_analystNote ?? '', analystNoteEn);
  String? get sourceAnalystNote => _analystNote;
  final int homeFormPoints;
  final int awayFormPoints;
  final double? aiProbability;
  final String? aiExplanation;
  /// false = match en base sans pronostic publié
  final bool hasPronostic;
  /// Résultat réglé côté backend — source de vérité (moteur de règlement
  /// couvrant tous les marchés, pas seulement les 8 types de base).
  final PronosticResult? result;

  /// Plusieurs pronostics par match (23 novembre 2026) : combien d'autres
  /// pronostics publiés s'ajoutent à celui-ci. La liste n'envoie que le
  /// nombre ; la fiche du match envoie les pronostics eux-mêmes.
  final int nbAutresPronostics;

  /// Les autres pronostics du match, chacun avec son propre verrou VIP
  /// (fiche du match seulement ; vide dans les listes).
  final List<AutrePronostic> autresPronostics;

  const MatchEntity({
    required this.id,
    required this.league,
    required this.leagueCountry,
    required String homeTeam,
    required String awayTeam,
    this.homeTeamLogo,
    this.awayTeamLogo,
    required this.matchDate,
    required this.status,
    this.homeScore,
    this.awayScore,
    this.elapsed,
    required this.predictionType,
    required String predictionLabel,
    this.predictionLabelEn,
    required this.oddsRecommended,
    required this.oddsHome,
    required this.oddsDraw,
    required this.oddsAway,
    required this.confidenceScore,
    this.confidencePct,
    required this.isPremium,
    String? analystNote,
    this.analystNoteEn,
    required this.homeFormPoints,
    required this.awayFormPoints,
    this.aiProbability,
    this.aiExplanation,
    this.hasPronostic = true,
    this.isLocked = false,
    this.result,
    this.nbAutresPronostics = 0,
    this.autresPronostics = const [],
  }) : _homeTeam = homeTeam, _awayTeam = awayTeam, _predictionLabel = predictionLabel, _analystNote = analystNote;

  /// La même rencontre, sans aucune cote : la version iPhone n'en affiche
  /// pas (voir `sansPariProvider`). Chaque écran masque déjà une cote nulle ;
  /// lui confier cette copie suffit, sans retoucher chaque affichage.
  MatchEntity sansCotes() => MatchEntity(
    id: id, league: league, leagueCountry: leagueCountry,
    homeTeam: _homeTeam, awayTeam: _awayTeam,
    homeTeamLogo: homeTeamLogo, awayTeamLogo: awayTeamLogo,
    matchDate: matchDate, status: status, homeScore: homeScore, awayScore: awayScore,
    elapsed: elapsed,
    predictionType: predictionType, predictionLabel: _predictionLabel,
    predictionLabelEn: predictionLabelEn,
    oddsRecommended: 0, oddsHome: 0, oddsDraw: 0, oddsAway: 0,
    confidenceScore: confidenceScore, confidencePct: confidencePct, isPremium: isPremium,
    analystNote: _analystNote, analystNoteEn: analystNoteEn,
    homeFormPoints: homeFormPoints, awayFormPoints: awayFormPoints,
    aiProbability: aiProbability, aiExplanation: aiExplanation,
    hasPronostic: hasPronostic, isLocked: isLocked, result: result,
    nbAutresPronostics: nbAutresPronostics,
    autresPronostics: [for (final a in autresPronostics) a.sansCote()],
  );

  /// Le même match, portant [a] à la place de son pronostic principal : pour
  /// miser sur un autre pronostic ou le partager en image avec les écrans du
  /// principal (24 novembre 2026). Son identifiant est celui de [a] — c'est
  /// lui que la bankroll enregistre.
  MatchEntity avecPronostic(AutrePronostic a) => MatchEntity(
    id: a.id, league: league, leagueCountry: leagueCountry,
    homeTeam: _homeTeam, awayTeam: _awayTeam,
    homeTeamLogo: homeTeamLogo, awayTeamLogo: awayTeamLogo,
    matchDate: matchDate, status: status, homeScore: homeScore, awayScore: awayScore,
    elapsed: elapsed,
    predictionType: PredictionType.other, predictionLabel: a._predictionLabel,
    predictionLabelEn: a.predictionLabelEn,
    oddsRecommended: a.oddsRecommended, oddsHome: oddsHome, oddsDraw: oddsDraw, oddsAway: oddsAway,
    confidenceScore: a.confidenceScore, confidencePct: a.confidencePct, isPremium: a.isPremium,
    analystNote: a._analystNote, analystNoteEn: a.analystNoteEn,
    homeFormPoints: homeFormPoints, awayFormPoints: awayFormPoints,
    hasPronostic: true, isLocked: a.isLocked, result: a.result,
  );

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
  ///
  /// Le nom anglais d'une sélection, recopié dans le libellé par le formulaire
  /// du panneau (« Norway gagne »), y est aussi traduit — celui des deux
  /// équipes du match seulement, pour ne jamais toucher un nom de joueur.
  static String applyTeamNames(String label, {required String homeTeam, required String awayTeam}) =>
      traduireEquipesDansLibelle(
        FootballLabels.prediction(label, home: homeTeam, away: awayTeam).text
            .replaceAll(_domicileRe, homeTeam).replaceAll(_exterieurRe, awayTeam),
        [homeTeam, awayTeam]);

  /// [predictionLabel] avec les camps génériques substitués — voir [applyTeamNames].
  String get displayPredictionLabel =>
      MatchEntity.applyTeamNames(predictionLabel, homeTeam: homeTeam, awayTeam: awayTeam);

  @override
  List<Object?> get props => [id, hasPronostic];
}

/// Un autre pronostic du même match (plusieurs par match, 23 novembre 2026).
///
/// Le serveur le filtre comme le principal : un pronostic VIP arrive sans son
/// choix, sa cote ni son analyse pour qui n'est pas abonné (`isLocked`) ; son
/// résultat, lui, reste visible.
class AutrePronostic {
  final String id;
  final bool isPremium;
  final bool isLocked;
  final String _predictionLabel;
  final String? predictionLabelEn;
  String get predictionLabel => editorialText(_predictionLabel, predictionLabelEn);
  final double oddsRecommended;
  final int confidenceScore;
  final int? confidencePct;
  final String? _analystNote;
  final String? analystNoteEn;
  String? get analystNote => _analystNote == null && analystNoteEn == null ? null : editorialText(_analystNote ?? '', analystNoteEn);
  final PronosticResult? result;

  const AutrePronostic({
    required this.id,
    required this.isPremium,
    this.isLocked = false,
    required String predictionLabel,
    this.predictionLabelEn,
    this.oddsRecommended = 0,
    this.confidenceScore = 0,
    this.confidencePct,
    String? analystNote,
    this.analystNoteEn,
    this.result,
  }) : _predictionLabel = predictionLabel, _analystNote = analystNote;

  /// Le pourcentage à afficher, comme [MatchEntity.pourcentageConfiance].
  int get pourcentageConfiance => confidencePct ?? MatchEntity.pourcentageDepuisNiveau(confidenceScore);

  /// [predictionLabel] avec les noms des équipes du match.
  String libelle(MatchEntity match) =>
      MatchEntity.applyTeamNames(predictionLabel, homeTeam: match.homeTeam, awayTeam: match.awayTeam);

  /// Sans cote : la version iPhone n'en affiche pas (`sansPariProvider`).
  AutrePronostic sansCote() => AutrePronostic(
    id: id, isPremium: isPremium, isLocked: isLocked,
    predictionLabel: _predictionLabel, predictionLabelEn: predictionLabelEn,
    confidenceScore: confidenceScore, confidencePct: confidencePct,
    analystNote: _analystNote, analystNoteEn: analystNoteEn, result: result,
  );

  factory AutrePronostic.fromJson(Map<String, dynamic> j) => AutrePronostic(
    id:                j['id'] as String,
    isPremium:         j['is_premium'] as bool? ?? false,
    isLocked:          j['locked'] as bool? ?? false,
    predictionLabel:   j['prediction_label'] as String? ?? '',
    predictionLabelEn: j['prediction_label_en'] as String?,
    oddsRecommended:   (j['odds_recommended'] as num?)?.toDouble() ?? 0,
    confidenceScore:   (j['confidence_score'] as num?)?.toInt() ?? 0,
    confidencePct:     (j['confidence_pct'] as num?)?.toInt(),
    analystNote:       j['analyst_note'] as String?,
    analystNoteEn:     j['analyst_note_en'] as String?,
    result: switch (j['result']) {
      'WIN'  => PronosticResult.win,
      'LOSS' => PronosticResult.loss,
      'PUSH' => PronosticResult.push,
      _      => null,
    },
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'is_premium': isPremium,
    'locked': isLocked,
    'prediction_label': _predictionLabel,
    'prediction_label_en': predictionLabelEn,
    'odds_recommended': oddsRecommended,
    'confidence_score': confidenceScore,
    'confidence_pct': confidencePct,
    'analyst_note': _analystNote,
    'analyst_note_en': analystNoteEn,
    'result': switch (result) {
      PronosticResult.win  => 'WIN',
      PronosticResult.loss => 'LOSS',
      PronosticResult.push => 'PUSH',
      null                 => null,
    },
  };
}

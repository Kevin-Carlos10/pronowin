import 'package:pronowin/l10n/editorial_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../shared/utils/resume_paris.dart';
import '../../../pronostics/domain/entities/match_entity.dart' show MatchEntity;
import 'package:pronowin/core/utils/noms_equipes.dart';

// ─── Entités ──────────────────────────────────────────────────────────────────

/// La mise sur l'inverse qu'un abonné a enregistrée (« J'ai couvert »,
/// 27 novembre 2026). Elle gagne quand la sélection couverte perd.
class CouvertureEnregistree {
  final String id;
  final String selectionFr;
  final String selectionEn;
  /// gain_egal | mise_remboursee | libre
  final String strategie;
  final double mise;
  final double cote;
  final String? result;
  final double? profit;

  const CouvertureEnregistree({
    required this.id, required this.selectionFr, required this.selectionEn, required this.strategie,
    required this.mise, required this.cote, this.result, this.profit,
  });

  String selection(bool anglais) => anglais ? selectionEn : selectionFr;

  static CouvertureEnregistree? depuis(Object? j) {
    if (j is! Map) return null;
    return CouvertureEnregistree(
      id:          j['id'] as String? ?? '',
      selectionFr: j['selection_fr'] as String? ?? '',
      selectionEn: j['selection_en'] as String? ?? j['selection_fr'] as String? ?? '',
      strategie:   j['strategie'] as String? ?? 'libre',
      mise:        (j['mise'] as num?)?.toDouble() ?? 0,
      cote:        (j['cote'] as num?)?.toDouble() ?? 0,
      result:      j['result'] as String?,
      profit:      (j['profit'] as num?)?.toDouble(),
    );
  }
}

/// Une sélection d'un combiné : un pronostic PronoWin, ou une sélection libre.
class SelectionCombine {
  final String id;
  final String? pronosticId;
  final bool libre;
  final String? libreMatch;
  final String? libreSelection;
  final double cote;
  final int note;
  /// 'WIN' | 'LOSS' | 'PUSH' | null ; une sélection annulée vaut 'PUSH'.
  final String? result;
  final bool annulee;
  final String? _predictionLabel;
  final String? predictionLabelEn;
  final String? matchId;
  final String? homeTeam;
  final String? awayTeam;
  final DateTime? matchDate;
  final String? matchStatus;
  final int? homeScore;
  final int? awayScore;

  const SelectionCombine({
    required this.id, this.pronosticId, this.libre = false, this.libreMatch, this.libreSelection,
    required this.cote, this.note = 1, this.result, this.annulee = false, String? predictionLabel,
    this.predictionLabelEn, this.matchId, this.homeTeam, this.awayTeam, this.matchDate, this.matchStatus,
    this.homeScore, this.awayScore,
  }) : _predictionLabel = predictionLabel;

  /// « Arsenal – Chelsea », ou le match tel que l'abonné l'a écrit.
  String get rencontre => libre
      ? (libreMatch ?? '')
      : '${homeTeam ?? ''} – ${awayTeam ?? ''}';

  /// La sélection, avec les vrais noms d'équipes.
  String get selection => libre
      ? (libreSelection ?? '')
      : MatchEntity.applyTeamNames(editorialText(_predictionLabel ?? '', predictionLabelEn),
          homeTeam: homeTeam ?? '', awayTeam: awayTeam ?? '');

  factory SelectionCombine.fromJson(Map<String, dynamic> j) {
    final m = j['match'] is Map ? (j['match'] as Map).cast<String, dynamic>() : null;
    return SelectionCombine(
      id:              j['id'] as String,
      pronosticId:     j['pronostic_id'] as String?,
      libre:           j['libre'] == true,
      libreMatch:      j['libre_match'] as String?,
      libreSelection:  j['libre_selection'] as String?,
      cote:            (j['cote'] as num).toDouble(),
      note:            (j['note'] as num?)?.toInt() ?? 1,
      result:          j['result'] as String?,
      annulee:         j['annulee'] == true,
      predictionLabel: j['prediction_label'] as String?,
      predictionLabelEn: j['prediction_label_en'] as String?,
      matchId:         m?['id'] as String?,
      homeTeam:        m == null ? null : nomEquipe(m['home_team'] as String? ?? ''),
      awayTeam:        m == null ? null : nomEquipe(m['away_team'] as String? ?? ''),
      matchDate:       DateTime.tryParse(m?['match_date'] as String? ?? '')?.toLocal(),
      matchStatus:     m?['status'] as String?,
      homeScore:       (m?['home_score'] as num?)?.toInt(),
      awayScore:       (m?['away_score'] as num?)?.toInt(),
    );
  }
}

/// Un coupon combiné de la bankroll (27 novembre 2026).
class BankrollCombine {
  final String id;
  final double stakedAmount;
  final double oddsUsed;
  final double potentialGain;
  final int noteRetenue;
  final String? result;
  final double? profit;
  final DateTime createdAt;
  final List<SelectionCombine> selections;
  final CouvertureEnregistree? couvertureEnregistree;
  final String currency;

  const BankrollCombine({
    required this.id, required this.stakedAmount, required this.oddsUsed, required this.potentialGain,
    this.noteRetenue = 1, this.result, this.profit, required this.createdAt, required this.selections,
    this.couvertureEnregistree, required this.currency,
  });

  /// Les sélections encore à jouer.
  int get restantes => selections.where((l) => l.result == null).length;

  /// Le résultat net, couverture comprise, une fois tout réglé.
  double? get resultatNet {
    if (profit == null) return null;
    final h = couvertureEnregistree;
    if (h == null) return profit;
    return h.profit == null ? null : profit! + h.profit!;
  }

  factory BankrollCombine.fromJson(Map<String, dynamic> j, {required String currency}) => BankrollCombine(
    id:            j['id'] as String,
    stakedAmount:  (j['staked_amount'] as num).toDouble(),
    oddsUsed:      (j['odds_used'] as num).toDouble(),
    potentialGain: (j['potential_gain'] as num).toDouble(),
    noteRetenue:   (j['note_retenue'] as num?)?.toInt() ?? 1,
    result:        j['result'] as String?,
    profit:        (j['profit'] as num?)?.toDouble(),
    createdAt:     DateTime.tryParse(j['created_at'] as String? ?? '')?.toLocal() ?? DateTime.now(),
    selections:    ((j['selections'] as List?) ?? const [])
        .map((l) => SelectionCombine.fromJson((l as Map).cast<String, dynamic>())).toList(),
    couvertureEnregistree: CouvertureEnregistree.depuis(j['couverture_enregistree']),
    currency:      currency,
  );
}

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
  /// Coup d'envoi du match — pas la date du pari. Nul côté serveur ancien.
  final DateTime? matchDate;
  final String? homeTeamLogo;
  final String? awayTeamLogo;
  /// 'upcoming' | 'live' | 'finished', comme partout ; nul côté serveur ancien.
  final String? matchStatus;
  final int?    homeScore;
  final int?    awayScore;
  final String _predictionLabel;
  final String? predictionLabelEn;
  String get predictionLabel => editorialText(_predictionLabel, predictionLabelEn);
  final int     confidenceScore;
  /// Indice saisi par l'analyste ; nul côté serveur ancien.
  final int?    confidencePct;
  final String  currency;
  /// La mise réelle a été confirmée ou corrigée au résultat (M1).
  final bool    miseConfirmee;
  /// Le serveur demande de confirmer la mise réelle : pari réglé depuis peu,
  /// sans réponse encore.
  final bool    aConfirmer;
  /// La mise sur l'inverse, si l'abonné l'a enregistrée (27 novembre 2026).
  final CouvertureEnregistree? couvertureEnregistree;

  /// Le résultat net, couverture comprise, une fois tout réglé.
  double? get resultatNet {
    if (profit == null) return null;
    final h = couvertureEnregistree;
    if (h == null) return profit;
    return h.profit == null ? null : profit! + h.profit!;
  }

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
    this.matchDate,
    this.homeTeamLogo,
    this.awayTeamLogo,
    this.matchStatus,
    this.homeScore,
    this.awayScore,
    required String predictionLabel,
    this.predictionLabelEn,
    required this.confidenceScore,
    this.confidencePct,
    required this.currency,
    this.miseConfirmee = false,
    this.aConfirmer = false,
    this.couvertureEnregistree,
  }) : _predictionLabel = predictionLabel;

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
    homeTeam:        nomEquipe((j['match'] as Map)['home_team'] as String),
    awayTeam:        nomEquipe((j['match'] as Map)['away_team'] as String),
    league:          (j['match'] as Map)['league'] as String,
    matchDate:       DateTime.tryParse((j['match'] as Map)['match_date'] as String? ?? '')?.toLocal(),
    homeTeamLogo:    (j['match'] as Map)['home_team_logo'] as String?,
    awayTeamLogo:    (j['match'] as Map)['away_team_logo'] as String?,
    matchStatus:     (j['match'] as Map)['status'] as String?,
    homeScore:       ((j['match'] as Map)['home_score'] as num?)?.toInt(),
    awayScore:       ((j['match'] as Map)['away_score'] as num?)?.toInt(),
    predictionLabel: j['prediction_label'] as String,
    predictionLabelEn: j['prediction_label_en'] as String?,
    confidenceScore: (j['confidence_score'] as num).toInt(),
    confidencePct:   (j['confidence_pct'] as num?)?.toInt(),
    currency:        currency,
    // Absents d'un serveur plus ancien : rien à demander.
    miseConfirmee:   j['mise_confirmee'] == true,
    aConfirmer:      j['a_confirmer'] == true,
    couvertureEnregistree: CouvertureEnregistree.depuis(j['couverture_enregistree']),
  );

  /// [predictionLabel] avec "Domicile"/"Extérieur" remplacés par le nom réel
  /// de l'équipe — voir [MatchEntity.applyTeamNames].
  int get pourcentageConfiance =>
      confidencePct ?? MatchEntity.pourcentageDepuisNiveau(confidenceScore);

  String get displayPredictionLabel =>
      MatchEntity.applyTeamNames(predictionLabel, homeTeam: homeTeam, awayTeam: awayTeam);
}

class BankrollData {
  final String id;
  final double totalBudget;
  final double currentBalance;
  final String currency;
  final List<BankrollBet> bets;
  /// Les coupons combinés (27 novembre 2026) ; vide côté serveur ancien.
  final List<BankrollCombine> combines;

  /// Le bilan de **tous** les paris, compté par le serveur.
  ///
  /// [bets] est plafonnée : l'écran calculait pourtant ses compteurs, son taux
  /// de réussite et sa courbe à partir de cette liste, et les présentait comme
  /// le bilan complet. Au cinquante-et-unième pari, les chiffres devenaient
  /// faux sans que rien ne l'indique.
  ///
  /// `null` quand le serveur ne l'envoie pas encore : l'écran retombe alors sur
  /// son calcul local, c'est-à-dire l'ancien comportement. Un décalage de
  /// version ne doit pas vider la page.
  final ResumeParis? resume;

  /// Combien de paris [bets] contient réellement — pour pouvoir dire
  /// « 50 des 128 » au lieu de laisser croire qu'on les montre tous.
  final int parisAffiches;

  const BankrollData({
    required this.id,
    required this.totalBudget,
    required this.currentBalance,
    required this.currency,
    required this.bets,
    this.combines = const [],
    this.resume,
    this.parisAffiches = 0,
  });

  factory BankrollData.fromJson(Map<String, dynamic> j) => BankrollData(
    id:             j['id'] as String,
    totalBudget:    (j['total_budget'] as num).toDouble(),
    currentBalance: (j['current_balance'] as num).toDouble(),
    currency:       j['currency'] as String,
    resume: j['resume'] is Map
        ? ResumeParis.depuisApi((j['resume'] as Map).cast<String, dynamic>())
        : null,
    parisAffiches: (j['paris_affiches'] as num?)?.toInt()
        ?? (j['bets'] as List).length,
    bets: (j['bets'] as List)
        .map((b) => BankrollBet.fromJson(b as Map<String, dynamic>, currency: j['currency'] as String))
        .toList(),
    combines: ((j['combines'] as List?) ?? const [])
        .map((c) => BankrollCombine.fromJson((c as Map).cast<String, dynamic>(), currency: j['currency'] as String))
        .toList(),
  );

  /// L'historique montré est-il partiel ?
  bool get historiqueTronque =>
      resume != null && resume!.total > parisAffiches;

  double get progressPct =>
      totalBudget > 0 ? (currentBalance / totalBudget).clamp(0.0, 2.0) : 0.0;

  /// Résultat net réalisé : le seul montant qui dit si l'on gagne.
  ///
  /// `solde − budget` n'en est pas un : la mise quitte le solde dès que le
  /// pari est posé, si bien qu'un pari en cours s'y lisait comme une perte.
  /// (C'était aussi le sens de l'ancien `isProfit`, retiré.)
  double get resultatNet =>
      resume?.profitNet ?? bets.fold<double>(0, (n, b) => n + (b.profit ?? 0));

  /// Ce qui est engagé sur des paris non tranchés, déjà sorti du solde.
  double get engage =>
      resume?.misesEnCours ??
      bets.where((b) => b.result == null).fold<double>(0, (n, b) => n + b.stakedAmount);
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

// Mise obligatoire calculée avec la note actuelle du pronostic côté serveur.
final suggestedStakeProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, pronosticId) async {
  final dio = ref.read(dioProvider);
  final r   = await dio.get('/bankroll/suggest',
      queryParameters: {'pronostic_id': pronosticId});
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

/// Un combiné de la bankroll, d'après son identifiant.
final combineProvider = Provider.autoDispose.family<BankrollCombine?, String>((ref, id) {
  final combines = ref.watch(bankrollProvider).valueOrNull?.combines ?? const <BankrollCombine>[];
  for (final c in combines) {
    if (c.id == id) return c;
  }
  return null;
});

// Vérifie si l'user a déjà misé sur un pronostic précis
final hasBetOnPronosticProvider = Provider.autoDispose.family<bool, String>((ref, pronosticId) {
  final bankrollAsync = ref.watch(bankrollProvider);
  final bets = bankrollAsync.valueOrNull?.bets ?? [];
  return bets.any((b) => b.pronosticId == pronosticId);
});

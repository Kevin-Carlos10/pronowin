import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/dio_client.dart';
import 'package:pronowin/core/utils/noms_equipes.dart';
import '../../domain/series_match.dart';

// ─── Toutes les cotes du match ───────────────────────────────────────────────
//
// L'onglet « Cotes » n'affichait que le 1X2 ; Sofascore et 1xBet montrent
// tous les marchés. Les valeurs restent celles du fournisseur (« Over 2.5 »,
// « Home/Draw ») : l'écran les traduit par le catalogue partagé, le même qui
// nomme les pronostics — une cote et un pronostic sur le même marché portent
// ainsi le même libellé.

class CoteMarche {
  final String valeur;
  final double cote;
  const CoteMarche(this.valeur, this.cote);
}

class MarcheCote {
  final String nom;
  final List<CoteMarche> cotes;
  const MarcheCote(this.nom, this.cotes);

  factory MarcheCote.fromJson(Map<String, dynamic> j) => MarcheCote(
    j['name'] as String? ?? '',
    [
      for (final v in (j['values'] as List? ?? const []))
        if ((v as Map)['odd'] is num && (v['odd'] as num) > 1)
          CoteMarche('${v['value']}', (v['odd'] as num).toDouble()),
    ],
  );
}

/// Liste vide : pas de cotes pour ce match (commencé, autre fournisseur, ou
/// aucun bookmaker ne le couvre). Une panne passagère reste une erreur.
final cotesMarchesProvider = FutureProvider.autoDispose
    .family<List<MarcheCote>, String>((ref, id) async {
  try {
    final r = await ref.read(dioProvider).get('/pronostics/$id/cotes');
    return [
      for (final m in ((r.data as Map)['markets'] as List? ?? const []))
        MarcheCote.fromJson(m as Map<String, dynamic>),
    ].where((m) => m.nom.isNotEmpty && m.cotes.isNotEmpty).toList();
  } on DioException catch (e) {
    if (e.response?.statusCode == 404) return const [];
    rethrow;
  }
});

// ─── Forme récente ───────────────────────────────────────────────────────────

enum IssueMatch { victoire, nul, defaite }

/// La forme du classement (« WWDLW ») en issues, de la plus ancienne à la
/// plus récente. Le fournisseur écrit le dernier match en premier — vérifié
/// le 8 octobre 2026 : « LWWWW » pour Arsenal, battu à Brighton la veille.
List<IssueMatch> formeChronologique(String? forme) => [
  for (final c in (forme ?? '').toUpperCase().split('').reversed)
    if (c == 'W') IssueMatch.victoire
    else if (c == 'D') IssueMatch.nul
    else if (c == 'L') IssueMatch.defaite,
];

class MatchRecent {
  final DateTime? date;
  final String? competition;
  final String adversaire;
  final String? adversaireLogo;
  final bool domicile;
  final int butsPour, butsContre;
  final IssueMatch issue;
  const MatchRecent({
    this.date, this.competition, required this.adversaire, this.adversaireLogo,
    required this.domicile, required this.butsPour, required this.butsContre,
    required this.issue,
  });

  factory MatchRecent.fromJson(Map<String, dynamic> j) => MatchRecent(
    date: DateTime.tryParse(j['date'] as String? ?? '')?.toLocal(),
    competition: j['competition'] as String?,
    adversaire: nomEquipe(j['adversaire'] as String? ?? ''),
    adversaireLogo: j['adversaireLogo'] as String?,
    domicile: j['domicile'] == true,
    butsPour: (j['butsPour'] as num?)?.toInt() ?? 0,
    butsContre: (j['butsContre'] as num?)?.toInt() ?? 0,
    issue: switch (j['issue']) {
      'V' => IssueMatch.victoire,
      'D' => IssueMatch.defaite,
      _   => IssueMatch.nul,
    },
  );
}

/// Les cinq derniers matchs terminés de chaque équipe, du plus récent au plus
/// ancien.
class FormeRecente {
  final List<MatchRecent> domicile, exterieur;
  /// Les séries de chaque équipe, sur ses dix derniers matchs (null : serveur
  /// antérieur au 7 novembre 2026).
  final SeriesEquipe? seriesDomicile, seriesExterieur;
  const FormeRecente(this.domicile, this.exterieur, {this.seriesDomicile, this.seriesExterieur});
  bool get vide => domicile.isEmpty && exterieur.isEmpty;
}

/// `null` : rien à montrer — la fiche garde alors l'ancienne jauge de forme.
final formeRecenteProvider = FutureProvider.autoDispose
    .family<FormeRecente?, String>((ref, id) async {
  try {
    final r = await ref.read(dioProvider).get('/pronostics/$id/forme-recente');
    final d = r.data as Map<String, dynamic>;
    List<MatchRecent> lire(String cle) => [
      for (final m in (d[cle] as List? ?? const []))
        MatchRecent.fromJson(m as Map<String, dynamic>),
    ];
    final series = d['series'] is Map ? d['series'] as Map : const {};
    return FormeRecente(lire('home'), lire('away'),
        seriesDomicile: SeriesEquipe.fromJson(series['home']),
        seriesExterieur: SeriesEquipe.fromJson(series['away']));
  } on DioException {
    return null;
  }
});

/// Positions des deux équipes après chaque journée (7 novembre 2026, le
/// « Tracker de classement » de Sofascore).
class EvolutionClassement {
  final int saison, equipes;
  final List<({int journee, int? domicile, int? exterieur})> journees;
  const EvolutionClassement({required this.saison, required this.equipes, required this.journees});
}

/// `null` : coupe, match hors championnat ou serveur injoignable — la carte
/// n'apparaît pas.
final evolutionClassementProvider = FutureProvider.autoDispose
    .family<EvolutionClassement?, String>((ref, id) async {
  try {
    final r = await ref.read(dioProvider).get('/pronostics/$id/evolution-classement');
    final d = r.data as Map<String, dynamic>;
    final journees = [
      for (final j in (d['journees'] as List? ?? const []))
        if (j is Map && j['journee'] is num)
          (journee: (j['journee'] as num).toInt(),
           domicile: (j['domicile'] as num?)?.toInt(),
           exterieur: (j['exterieur'] as num?)?.toInt()),
    ];
    final equipes = (d['equipes'] as num?)?.toInt() ?? 0;
    if (journees.isEmpty || equipes < 2) return null;
    return EvolutionClassement(saison: (d['saison'] as num?)?.toInt() ?? 0, equipes: equipes, journees: journees);
  } on DioException {
    return null;
  }
});

/// L'avant-match et le résumé du match (26 octobre 2026), au format des
/// actualités : `{avant_match, resume}`, chacun ou null. Null si le serveur
/// ne répond pas — la fiche n'en montre alors aucun.
final articlesDuMatchProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>?, String>((ref, id) async {
  try {
    final r = await ref.read(dioProvider).get('/pronostics/$id/articles');
    return Map<String, dynamic>.from(r.data as Map);
  } on DioException {
    return null;
  }
});

/// « Qui va gagner ? » : la répartition des votes des fans (26 octobre 2026).
class VotesMatch {
  /// Ouvert jusqu'au coup d'envoi.
  final bool ouvert;
  final int total, dom, nul, ext;
  /// Pourcentages entiers ; leur somme fait 100 dès qu'il y a un vote.
  final int pDom, pNul, pExt;
  /// « 1 », « N », « 2 », ou null : pas de vote, ou invité.
  final String? monVote;
  const VotesMatch({required this.ouvert, required this.total, required this.dom, required this.nul,
    required this.ext, required this.pDom, required this.pNul, required this.pExt, this.monVote});

  factory VotesMatch.fromJson(Map<String, dynamic> j) {
    final p = j['pourcentages'] as Map<String, dynamic>? ?? const {};
    int n(Object? v) => (v as num?)?.toInt() ?? 0;
    return VotesMatch(
      ouvert: j['ouvert'] == true, total: n(j['total']), dom: n(j['dom']), nul: n(j['nul']), ext: n(j['ext']),
      pDom: n(p['dom']), pNul: n(p['nul']), pExt: n(p['ext']), monVote: j['mon_vote'] as String?);
  }
}

final votesMatchProvider = FutureProvider.autoDispose
    .family<VotesMatch?, String>((ref, id) async {
  try {
    final r = await ref.read(dioProvider).get('/pronostics/$id/votes');
    return VotesMatch.fromJson(Map<String, dynamic>.from(r.data as Map));
  } on DioException {
    return null;
  }
});

/// Voter « 1 », « N » ou « 2 » : rend la nouvelle répartition. Lève
/// [DioException] — 409 si le match a commencé.
final voterMatchProvider = Provider<Future<VotesMatch> Function(String id, String choix)>((ref) =>
  (id, choix) async {
    final r = await ref.read(dioProvider).post('/pronostics/$id/vote', data: {'choix': choix});
    return VotesMatch.fromJson(Map<String, dynamic>.from(r.data as Map));
  });

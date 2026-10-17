import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/dio_client.dart';
import 'package:pronowin/core/utils/noms_equipes.dart';

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
  const FormeRecente(this.domicile, this.exterieur);
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
    return FormeRecente(lire('home'), lire('away'));
  } on DioException {
    return null;
  }
});

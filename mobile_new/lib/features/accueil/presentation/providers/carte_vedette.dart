import '../../../pronostics/domain/entities/match_entity.dart';

/// Le match mis en avant en haut de l'accueil, et pourquoi.
///
/// ── Pourquoi une seule carte ─────────────────────────────────────────────
///
/// L'accueil avait deux grandes cartes : « Prochain match » (le pronostic de
/// la semaine qui commence le plus tôt, avec son compte à rebours) et « Top
/// prono du jour » (le plus confiant du jour). Elles désignaient souvent la
/// même rencontre — affichée deux fois à un écran d'intervalle, puis une
/// troisième fois dans le carrousel « Pronostics du jour ».
///
/// Il n'en reste qu'une, qui garde le compte à rebours. Elle montre le
/// meilleur pronostic du jour (décision du 1er octobre 2026), et ses badges
/// disent pourquoi elle le montre : TOP DU JOUR, PROCHAIN MATCH, ou les deux.
class Vedette {
  final Map<String, dynamic> prono;
  final bool estTopDuJour;
  final bool estProchainMatch;
  const Vedette(this.prono, {required this.estTopDuJour, required this.estProchainMatch});
}

/// Choisit la carte vedette.
///
///   · Le pronostic du jour à l'indice de confiance le plus haut, parmi ceux
///     qui n'ont pas commencé ; à égalité, celui qui commence le plus tôt.
///   · Aucun aujourd'hui : le prochain match de la semaine, comme avant.
///
/// Un match commencé n'est jamais retenu : il a sa section « En direct », et
/// un compte à rebours n'a plus rien à compter.
Vedette? choisirVedette({
  required List<dynamic> duJour,
  Map<String, dynamic>? prochain,
  DateTime? maintenant,
}) {
  final now = maintenant ?? DateTime.now();

  DateTime? debut(Map<String, dynamic> p) =>
      DateTime.tryParse(p['match_date'] as String? ?? '')?.toLocal();

  bool aVenir(Map<String, dynamic> p) {
    final statut = p['status'] as String? ?? '';
    if (statut == 'finished' || statut == 'live') return false;
    final d = debut(p);
    return d != null && d.isAfter(now);
  }

  final candidats = duJour
      .whereType<Map<String, dynamic>>()
      .where(aVenir)
      .toList()
    ..sort((a, b) {
      final parConfiance = MatchEntity.pourcentageDepuisApi(b)
          .compareTo(MatchEntity.pourcentageDepuisApi(a));
      if (parConfiance != 0) return parConfiance;
      return debut(a)!.compareTo(debut(b)!);
    });

  final prochainValide = prochain != null && aVenir(prochain) ? prochain : null;

  if (candidats.isNotEmpty) {
    final top = candidats.first;
    return Vedette(top,
        estTopDuJour: true,
        estProchainMatch: prochainValide != null && prochainValide['id'] == top['id']);
  }
  if (prochainValide != null) {
    return Vedette(prochainValide, estTopDuJour: false, estProchainMatch: true);
  }
  return null;
}

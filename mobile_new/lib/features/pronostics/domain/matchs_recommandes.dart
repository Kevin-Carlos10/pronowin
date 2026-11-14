import 'entities/match_entity.dart';

/// Les matchs à proposer quand on n'en suit encore aucun (8 novembre 2026).
///
/// Repris de 1xBet : son onglet Favoris vide dit « Votre liste de jeux
/// favoris est vide » et montre aussitôt des « Recommandés ». L'onglet Suivis
/// de PronoWin ne proposait rien — or suivre un match est ce qui déclenche
/// les alertes de but.
///
/// Ordre : le direct d'abord (pronostiqué en tête), puis les prochains
/// coups d'envoi pronostiqués, puis les autres. Jamais un match terminé : il
/// n'enverra plus rien.
List<MatchEntity> matchsRecommandes(List<MatchEntity> matchs, {int max = 5}) {
  int rang(MatchEntity m) => switch ((m.status, m.hasPronostic)) {
    (MatchStatus.live, true) => 0,
    (MatchStatus.live, false) => 1,
    (MatchStatus.upcoming, true) => 2,
    _ => 3,
  };
  final candidats = matchs.where((m) => m.status != MatchStatus.finished).toList()
    ..sort((a, b) {
      final r = rang(a).compareTo(rang(b));
      return r != 0 ? r : a.matchDate.compareTo(b.matchDate);
    });
  final vus = <String>{};
  return [for (final m in candidats) if (vus.add(m.id)) m].take(max).toList();
}

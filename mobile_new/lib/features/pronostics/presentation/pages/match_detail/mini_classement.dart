part of '../match_detail_page.dart';

/// Les deux équipes au classement, dans « Détails » (8 novembre 2026), comme
/// la carte « Classements » de Sofascore : rang, matchs joués, différence de
/// buts, points — et un bouton vers le classement complet et sa courbe.
///
/// Il fallait ouvrir l'onglet Classements et chercher les deux lignes parmi
/// vingt. Rien sans classement (coupe, amical) : la carte ne laisse pas de
/// trou.
class _MiniClassement extends ConsumerWidget {
  final MatchEntity match;
  /// Ouvre l'onglet Classements.
  final VoidCallback? onVoirTout;
  const _MiniClassement({required this.match, this.onVoirTout});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lignes = ref.watch(standingsProvider(match.id)).valueOrNull;
    if (lignes == null || lignes.isEmpty) return const SizedBox.shrink();
    bool duMatch(StandingRow r) => r.isMatchTeam ?? (_StandingsCard.memeEquipe(r.teamName, match.homeTeam)
        || _StandingsCard.memeEquipe(r.teamName, match.awayTeam));
    // Le groupe des deux équipes (une poule de Ligue des champions, pas
    // toutes les poules).
    final premiere = lignes.where(duMatch).firstOrNull;
    if (premiere == null) return const SizedBox.shrink();
    final equipes = lignes.where((r) => r.groupId == premiere.groupId && duMatch(r)).toList()
      ..sort((a, b) => a.rank.compareTo(b.rank));
    if (equipes.isEmpty) return const SizedBox.shrink();

    TextStyle entete() => TextStyle(color: context.cl.textM, fontSize: 11, fontWeight: FontWeight.w600);
    Widget nombre(String v, {bool gras = false, Color? couleur}) => SizedBox(
      width: 38,
      child: Text(v, textAlign: TextAlign.center,
        style: TextStyle(color: couleur ?? context.cl.textS, fontSize: 13,
          fontWeight: gras ? FontWeight.w800 : FontWeight.w600,
          fontFeatures: const [FontFeature.tabularFigures()])));

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        key: const Key('mini-classement'),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        decoration: BoxDecoration(
          color: context.cl.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.cl.border, width: 0.8)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(tr(context, "Classement"),
              style: TextStyle(color: context.cl.textP, fontSize: 15, fontWeight: FontWeight.w800))),
            if (onVoirTout != null)
              TextButton.icon(
                key: const Key('mini-classement-voir-tout'),
                onPressed: onVoirTout,
                style: TextButton.styleFrom(
                  foregroundColor: context.cl.accent,
                  minimumSize: const Size(0, 34),
                  padding: const EdgeInsets.symmetric(horizontal: 8)),
                icon: const Icon(Icons.show_chart_rounded, size: 17),
                label: Text(tr(context, "Graphique"), style: const TextStyle(fontWeight: FontWeight.w700))),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            SizedBox(width: 28, child: Text('#', style: entete())),
            Expanded(child: Text(tr(context, "Équipe"), style: entete())),
            SizedBox(width: 38, child: Text(tr(context, "J"), textAlign: TextAlign.center, style: entete())),
            SizedBox(width: 38, child: Text(tr(context, "Diff"), textAlign: TextAlign.center, style: entete())),
            SizedBox(width: 38, child: Text(tr(context, "Pts"), textAlign: TextAlign.center, style: entete())),
          ]),
          for (final r in equipes)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                SizedBox(width: 28, child: Text('${r.rank}',
                  style: TextStyle(color: context.cl.textP, fontSize: 13, fontWeight: FontWeight.w700))),
                TeamLogoWidget(url: r.teamLogo, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(r.teamName, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: context.cl.textP, fontSize: 14, fontWeight: FontWeight.w600))),
                nombre('${r.played}'),
                nombre(r.goalsDiff > 0 ? '+${r.goalsDiff}' : '${r.goalsDiff}'),
                nombre('${r.points}', gras: true, couleur: context.cl.accent),
              ]),
            ),
        ]),
      ),
    );
  }
}

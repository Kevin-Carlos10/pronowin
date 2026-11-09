// Séries — 7 novembre 2026.
part of '../match_detail_page.dart';

@visibleForTesting
Widget seriesSeules(MatchEntity match) => _Series(match: match);

/// « Séries », comme Sofascore : pour chaque équipe, ce que disent ses dix
/// derniers matchs (« Victoires de suite 3 », « Plus de 2,5 buts 7/10 »), puis
/// ce que disent leurs face-à-face. Seuls les faits qui sortent de l'ordinaire
/// sont montrés (`series_match.dart`) ; sans aucun, la carte n'apparaît pas.
///
/// Avant le match seulement, comme la forme récente : après, ces séries ne
/// décrivent plus l'avant-match.
class _Series extends ConsumerWidget {
  final MatchEntity match;
  const _Series({required this.match});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (match.status == MatchStatus.finished) return const SizedBox.shrink();
    final forme = ref.watch(formeRecenteProvider(match.id)).valueOrNull;
    final h2h = ref.watch(h2hProvider(match.id)).valueOrNull;

    final dom = forme?.seriesDomicile == null ? const <FaitSerie>[] : faitsNotables(forme!.seriesDomicile!);
    final ext = forme?.seriesExterieur == null ? const <FaitSerie>[] : faitsNotables(forme!.seriesExterieur!);
    // Du plus récent au plus ancien, comme le serveur les envoie.
    final confrontations = [
      for (final m in h2h?.matches ?? const <H2HMatchResult>[])
        (domicile: m.homeTeam, exterieur: m.awayTeam, butsDom: m.homeScore, butsExt: m.awayScore),
    ];
    final faceAFace = h2h == null ? const <FaitSerie>[]
        : faitsFaceAFace(confrontations, equipeA: h2h.homeTeam, equipeB: h2h.awayTeam);
    final invaincuDom = h2h == null ? 0 : sansDefaiteFaceA(confrontations, h2h.homeTeam);
    final invaincuExt = h2h == null ? 0 : sansDefaiteFaceA(confrontations, h2h.awayTeam);

    // (logo, équipe, fait) ; sans équipe : un fait des deux équipes ensemble.
    final domicile = (match.homeTeamLogo ?? '', match.homeTeam);
    final exterieur = (match.awayTeamLogo ?? '', match.awayTeam);
    final lignes = <((String, String)?, FaitSerie)>[
      for (final f in dom) (domicile, f),
      for (final f in ext) (exterieur, f),
    ];
    final lignesH2h = <((String, String)?, FaitSerie)>[
      if (invaincuDom >= 3) (domicile, FaitSerie('Sans défaite', '$invaincuDom')),
      if (invaincuExt >= 3) (exterieur, FaitSerie('Sans défaite', '$invaincuExt')),
      for (final f in faceAFace) (null, f),
    ];
    if (lignes.isEmpty && lignesH2h.isEmpty) return const SizedBox.shrink();

    Widget ligne(((String, String)?, FaitSerie) l) {
      final (equipe, fait) = l;
      final logo = equipe?.$1;
      final libelle = tr(context, fait.libelle);
      return Semantics(
        label: equipe == null ? '$libelle : ${fait.valeur}' : '${equipe.$2} — $libelle : ${fait.valeur}',
        child: ExcludeSemantics(child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            SizedBox(width: 22, child: equipe == null
              ? Icon(Icons.compare_arrows_rounded, size: 18, color: context.cl.textS)
              : TeamLogoWidget(url: logo!.isEmpty ? null : logo, size: 20)),
            const SizedBox(width: 12),
            Expanded(child: Text(libelle,
              style: TextStyle(color: context.cl.textP, fontSize: 14, fontWeight: FontWeight.w500))),
            const SizedBox(width: 10),
            Text(fait.valeur,
              style: TextStyle(color: context.cl.textP, fontSize: 14, fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()])),
          ]),
        )),
      );
    }

    Widget sousTitre(String texte) => Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 2),
      child: Semantics(header: true, child: Text(texte,
        style: TextStyle(color: context.cl.textS, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.3))),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        key: const Key('series'),
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
        decoration: BoxDecoration(
          color: context.cl.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: context.cl.borderSoft, width: 0.8),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Semantics(header: true, child: Text(tr(context, "Séries"),
            style: TextStyle(color: context.cl.textP, fontSize: 16, fontWeight: FontWeight.w700))),
          if (lignes.isNotEmpty) ...[
            sousTitre(tr(context, "Derniers matchs")),
            for (final l in lignes) ligne(l),
          ],
          if (lignesH2h.isNotEmpty) ...[
            if (lignes.isNotEmpty) Divider(height: 18, color: context.cl.borderSoft),
            sousTitre(tr(context, "Face-à-face")),
            for (final l in lignesH2h) ligne(l),
          ],
        ]),
      ),
    );
  }
}

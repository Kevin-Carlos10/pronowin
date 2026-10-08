// Classement du championnat — extrait de match_detail_page.dart.
//
// `part` et non un fichier autonome : toutes ces classes sont privées à
// la bibliothèque (préfixe `_`) et le resteront. Un import classique aurait
// imposé de les rendre publiques, donc visibles depuis n'importe où.
part of '../match_detail_page.dart';

class _StandingsCard extends ConsumerWidget {
  final String matchId;
  final String homeTeam;
  final String awayTeam;
  const _StandingsCard({
    required this.matchId, required this.homeTeam, required this.awayTeam});

  /// Rapprochement souple des noms d'équipe : l'API-Football nomme la même
  /// équipe « Bayern München » dans un classement et « Bayern Munich » dans un
  /// match. On compare sans accents ni casse, et par inclusion dans les deux
  /// sens pour absorber les suffixes (« FC », « SK », « Spor Kulübü »).
  static bool memeEquipe(String a, String b) {
    String norme(String v) {
      const accents = 'àáâãäåçèéêëìíîïñòóôõöùúûüýÿ';
      const simples = 'aaaaaaceeeeiiiinooooouuuuyy';
      final buf = StringBuffer();
      for (final c in v.toLowerCase().runes) {
        final ch = String.fromCharCode(c);
        final i  = accents.indexOf(ch);
        if (i >= 0) {
          buf.write(simples[i]);
        } else if (RegExp(r'[a-z0-9 ]').hasMatch(ch)) {
          buf.write(ch);
        }
      }
      return buf.toString().trim();
    }

    final na = norme(a), nb = norme(b);
    if (na.isEmpty || nb.isEmpty) return false;
    return na == nb || na.contains(nb) || nb.contains(na);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final standingsAsync = ref.watch(standingsProvider(matchId));
    final status = _statusOf(standingsAsync.error);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cl.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.cl.borderSoft, width: 0.8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: context.cl.info.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.leaderboard_rounded, color: context.cl.info, size: 16),
          ),
          const SizedBox(width: 10),
          Text(tr(context, "Classement"),
            style: TextStyle(
              color: context.cl.textP,
              fontSize: 13,
              fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 12),
        status == 401
          ?  _CardLoginPrompt(message: tr(context, "Connecte-toi pour voir le classement."))
          : standingsAsync.hasValue && standingsAsync.valueOrNull!.isNotEmpty
            ? _GroupedStandings(rows: standingsAsync.valueOrNull!, homeTeam: homeTeam,
                awayTeam: awayTeam, failed: standingsAsync.hasError)
            : standingsAsync.when(
                loading: () => _H2HLoading(),
                error: (_, _) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr(context, status == 404
                    ? "Le fournisseur ne propose pas de classement pour cette compétition."
                    : "Le classement est momentanément indisponible."),
                    style: TextStyle(color: context.cl.textS)),
                  if (status != 404) TextButton(
                    onPressed: () => ref.invalidate(standingsProvider(matchId)),
                    child: Text(tr(context, "Réessayer"))),
                ]),
                data: (_) => Text(tr(context, "Le classement n'est pas encore publié pour cette saison."),
                  style: TextStyle(color: context.cl.textS)),
              ),
      ]),
    );
  }
}


/// Les quatre lectures d'un classement que propose Sofascore : le général, le
/// classement des seuls matchs à domicile, celui des matchs à l'extérieur, et
/// la forme des cinq dernières journées. Pour un pronostic, « 3ᵉ à domicile,
/// 14ᵉ à l'extérieur » en dit plus qu'un rang général.
enum _VueClassement { general, domicile, exterieur, forme }

/// Group selection stays independent of rankings (several groups can have rank 1).
class _GroupedStandings extends StatefulWidget {
  final List<StandingRow> rows;
  final String homeTeam, awayTeam;
  final bool failed;
  const _GroupedStandings({required this.rows, required this.homeTeam,
    required this.awayTeam, this.failed = false});
  @override
  State<_GroupedStandings> createState() => _GroupedStandingsState();
}

class _GroupedStandingsState extends State<_GroupedStandings> {
  String? _selected;
  _VueClassement _vue = _VueClassement.general;

  String _titreVue(BuildContext context, _VueClassement v) => switch (v) {
    _VueClassement.general   => tr(context, "Général"),
    _VueClassement.domicile  => tr(context, "Domicile"),
    _VueClassement.exterieur => tr(context, "Extérieur"),
    _VueClassement.forme     => tr(context, "Forme"),
  };

  @override
  void didUpdateWidget(covariant _GroupedStandings oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.homeTeam != widget.homeTeam || oldWidget.awayTeam != widget.awayTeam) _selected = null;
  }
  @override
  Widget build(BuildContext context) {
    final groups = <String, List<StandingRow>>{};
    for (final row in widget.rows) { (groups[row.groupId] ??= []).add(row); }
    bool concerned(StandingRow r) => r.isMatchTeam ??
      (_StandingsCard.memeEquipe(r.teamName, widget.homeTeam) ||
       _StandingsCard.memeEquipe(r.teamName, widget.awayTeam));
    final preferred = widget.rows.where(concerned).firstOrNull?.groupId ?? groups.keys.first;
    final chosen = groups.containsKey(_selected) ? _selected! : preferred;
    final groupe = groups[chosen]!;
    // Une vue n'est proposée que si chaque ligne a de quoi la remplir : un
    // serveur antérieur n'envoie pas les bilans, un début de saison pas la
    // forme.
    final vues = [
      _VueClassement.general,
      if (groupe.every((r) => r.home != null && r.away != null)) ...[
        _VueClassement.domicile, _VueClassement.exterieur],
      if (groupe.any((r) => r.form?.isNotEmpty == true)) _VueClassement.forme,
    ];
    final vue = vues.contains(_vue) ? _vue : _VueClassement.general;
    final rows = switch (vue) {
      _VueClassement.domicile  => classementSurTerrain(groupe, domicile: true) ?? groupe,
      _VueClassement.exterieur => classementSurTerrain(groupe, domicile: false) ?? groupe,
      _                        => groupe,
    };
    String label(String id) {
      final name = groups[id]!.first.groupName;
      if (name == null || name.trim().isEmpty) {
        return tr(context, "Groupe {arg0}", [groups.keys.toList().indexOf(id) + 1]);
      }
      return FootballLabels.round(name, language: AppStrings.of(context).locale.languageCode);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (rows.first.season != null) Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(tr(context, "Saison {arg0}", [rows.first.season]),
          style: TextStyle(color: context.cl.textS, fontSize: 12))),
      if (groups.length > 1) ...[
        Text(tr(context, "Groupe"), style: TextStyle(color: context.cl.textS)),
        DropdownButton<String>(
          key: const Key('standings-group'),
          isExpanded: true, itemHeight: null, value: chosen,
          dropdownColor: context.cl.surface,
          items: [for (final id in groups.keys) DropdownMenuItem(value: id,
            child: Padding(padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(label(id), style: TextStyle(color: context.cl.textP))))],
          onChanged: (id) => setState(() => _selected = id)),
        const SizedBox(height: 8),
      ] else if (rows.first.groupName != null) Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(label(chosen), style: TextStyle(color: context.cl.textS))),
      if (!widget.rows.any(concerned)) Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(tr(context, "Classement de la compétition : les équipes de ce match n'y figurent pas."),
          style: TextStyle(color: context.cl.textS, fontSize: 12))),
      if (rows.first.updatedAt != null || widget.failed || rows.first.stale) ...[
        _FraicheurDonnees(updatedAt: rows.first.updatedAt, stale: widget.failed || rows.first.stale),
        const SizedBox(height: 12),
      ],
      if (vues.length > 1) ...[
        // Retour à la ligne plutôt que défilement : les choix restent tous
        // visibles, même avec le texte agrandi.
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final v in vues)
            ChoiceChip(
              key: Key('classement-${v.name}'),
              label: Text(_titreVue(context, v)),
              selected: v == vue,
              onSelected: (_) => setState(() => _vue = v),
              labelStyle: TextStyle(
                fontSize: 11.5,
                fontWeight: v == vue ? FontWeight.w700 : FontWeight.w500,
                color: v == vue ? context.cl.textP : context.cl.textS),
              selectedColor: context.cl.info.withValues(alpha: 0.16),
              side: BorderSide(color: v == vue
                  ? context.cl.info.withValues(alpha: 0.5)
                  : context.cl.borderSoft),
              showCheckmark: false,
              visualDensity: VisualDensity.compact,
            ),
        ]),
        const SizedBox(height: 12),
      ],
      LayoutBuilder(builder: (context, constraints) {
        final minWidth = MediaQuery.textScalerOf(context).scale(310);
        return SingleChildScrollView(scrollDirection: Axis.horizontal,
          child: SizedBox(width: constraints.maxWidth < minWidth ? minWidth : constraints.maxWidth,
            child: _StandingsTable(rows: rows, homeTeam: widget.homeTeam, awayTeam: widget.awayTeam,
              forme: vue == _VueClassement.forme)));
      }),
    ]);
  }
}

/// Couleur d'une zone de qualification ou de relegation.
///
/// Elle depend de la **nature** renvoyee par le serveur, jamais du libelle :
/// deux championnats nomment differemment la meme zone, et une couleur ne doit
/// pas dependre d'une chaine de caracteres.
Color? _couleurZone(String? nature) => switch (nature) {
  'c1'         => const Color(0xFF22C55E),  // Ligue des champions
  'c3'         => const Color(0xFF3B82F6),  // Ligue Europa
  'c4'         => const Color(0xFF06B6D4),  // Ligue Conference
  'promotion'  => const Color(0xFF22C55E),
  'barrage'    => const Color(0xFFF59E0B),
  'relegation' => const Color(0xFFEF4444),
  _            => null,
};

/// Tableau de classement, regroupe par zone.
///
/// Trois manques comblés d'un coup :
///
///  1. **Les zones de qualification.** « 7e avec 3 points » ne dit rien tant
///     qu'on ignore si cette place mene en Europe ou frole la descente — et
///     c'est ce qui change la nature d'un match. La donnee existait chez le
///     fournisseur et n'etait pas lue.
///  2. **Les logos**, deja recuperes par le serveur et jamais affiches. Un nom
///     se lit, un ecusson se reconnait.
///  3. **Sept colonnes sur un ecran de telephone.** J/V/N/D/+-/Pts serraient le
///     nom des equipes au point de le tronquer. Les victoires, nuls et defaites
///     se deduisent des points ; on garde ce qui se lit d'un coup d'oeil.
class _StandingsTable extends StatelessWidget {
  final List<StandingRow> rows;
  final String homeTeam;
  final String awayTeam;

  /// Vue « Forme » : les cinq dernières issues à la place des matchs joués et
  /// de la différence de buts.
  final bool forme;
  const _StandingsTable({
    required this.rows, required this.homeTeam, required this.awayTeam,
    this.forme = false});

  /// Cinq pastilles de 15 et leurs écarts.
  static const largeurForme = 92.0;

  @override
  Widget build(BuildContext context) {
    final lignes = <Widget>[];
    String? zonePrecedente;

    for (final r in rows) {
      // En-tete de zone, insere au premier changement.
      if (r.zone != null && r.zone != zonePrecedente) {
        final couleur = _couleurZone(r.zoneNature);
        lignes.add(Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 4, left: 2),
          child: Row(children: [
            Container(width: 3, height: 12,
              decoration: BoxDecoration(
                color: couleur ?? context.cl.border,
                borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 7),
            Expanded(child: Text(tr(context, r.zone!),
              style: TextStyle(
                color: couleur ?? context.cl.textM,
                fontSize: 10, fontWeight: FontWeight.w700,
                letterSpacing: 0.2))),
          ]),
        ));
      }
      zonePrecedente = r.zone;
      lignes.add(_LigneClassement(
        row: r, homeTeam: homeTeam, awayTeam: awayTeam, forme: forme));
    }

    return Column(children: [
      Row(children: [
        SizedBox(width: MediaQuery.textScalerOf(context).scale(22)),
        Expanded(child: Text(tr(context, "Équipe"),
          style: TextStyle(color: context.cl.textM, fontSize: 10, fontWeight: FontWeight.w600))),
        if (forme)
          SizedBox(width: largeurForme, child: Text(tr(context, "Forme"), textAlign: TextAlign.center,
            style: TextStyle(color: context.cl.textM, fontSize: 10, fontWeight: FontWeight.w600)))
        else ...[
          _StandingsHeaderCell('J'),
          _StandingsHeaderCell('+/-'),
        ],
        _StandingsHeaderCell('Pts'),
      ]),
      const SizedBox(height: 6),
      Divider(height: 1, color: context.cl.border),
      ...lignes,
    ]);
  }
}

/// Une ligne du classement.
class _LigneClassement extends StatelessWidget {
  final StandingRow row;
  final String homeTeam, awayTeam;
  final bool forme;
  const _LigneClassement({
    required this.row, required this.homeTeam, required this.awayTeam,
    this.forme = false});

  @override
  Widget build(BuildContext context) {
    // Les deux equipes du match sont surlignees : sans repere, il fallait
    // parcourir trente-six lignes pour retrouver celles qu'on est venu voir.
    final concernee = row.isMatchTeam ?? (_StandingsCard.memeEquipe(row.teamName, homeTeam) ||
                      _StandingsCard.memeEquipe(row.teamName, awayTeam));
    final couleurZone = _couleurZone(row.zoneNature);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 6),
      margin: const EdgeInsets.symmetric(vertical: 1),
      decoration: BoxDecoration(
        color: concernee ? AppColors.primary.withValues(alpha: 0.10) : null,
        borderRadius: BorderRadius.circular(7),
        border: concernee
            ? Border.all(color: AppColors.primary.withValues(alpha: 0.30), width: 0.8)
            : null,
      ),
      child: Row(children: [
        // Le rang porte la couleur de sa zone : le reperage marche aussi en
        // faisant defiler, une fois l'en-tete sorti de l'ecran.
        SizedBox(width: MediaQuery.textScalerOf(context).scale(22), child: Text('${row.rank}',
          style: TextStyle(
            color: concernee
                ? context.cl.accent
                : (couleurZone ?? context.cl.textM),
            fontSize: 11, fontWeight: FontWeight.w700))),
        // Ecusson : recupere par le serveur depuis toujours, jamais affiche.
        if (row.teamLogo != null && row.teamLogo!.isNotEmpty) ...[
          SizedBox(width: 16, height: 16,
            // Un logo absent ne doit pas decaler la colonne : on garde la
            // place et on n'affiche rien.
            child: ImageDistante(
              url:     row.teamLogo,
              largeur: 16, hauteur: 16,
              fit:     BoxFit.contain,
              repli:   const SizedBox.shrink())),
          const SizedBox(width: 7),
        ] else
          const SizedBox(width: 23),
        Expanded(child: Text(row.teamName,
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: concernee ? context.cl.textP : context.cl.textS,
            fontSize: 11.5,
            fontWeight: concernee ? FontWeight.w700 : FontWeight.w400))),
        if (forme)
          SizedBox(width: _StandingsTable.largeurForme, child: Center(child: _RangeeForme(
            formeChronologique(row.form).reversed.take(5).toList().reversed.toList(),
            taille: 15)))
        else ...[
          _StandingsCell('${row.played}'),
          _StandingsCell(row.goalsDiff > 0 ? '+${row.goalsDiff}' : '${row.goalsDiff}'),
        ],
        SizedBox(width: MediaQuery.textScalerOf(context).scale(28), child: Text('${row.points}', textAlign: TextAlign.center,
          style: TextStyle(color: context.cl.textP, fontSize: 11.5, fontWeight: FontWeight.w700))),
      ]),
    );
  }
}

class _StandingsHeaderCell extends StatelessWidget {
  final String label;
  const _StandingsHeaderCell(this.label);
  @override
  Widget build(BuildContext context) => SizedBox(width: MediaQuery.textScalerOf(context).scale(24),
    child: Text(label, textAlign: TextAlign.center,
      style: TextStyle(color: context.cl.textM, fontSize: 10, fontWeight: FontWeight.w600)));
}

class _StandingsCell extends StatelessWidget {
  final String value;
  const _StandingsCell(this.value);
  @override
  Widget build(BuildContext context) => SizedBox(width: MediaQuery.textScalerOf(context).scale(24),
    child: Text(value, textAlign: TextAlign.center,
      style: TextStyle(color: context.cl.textS, fontSize: 11)));
}

// ─── H2H ─────────────────────────────────────────────────────────────────────

/// Les palmarès individuels de la compétition, sous le classement : buteurs,
/// passeurs, cartons jaunes et rouges.
///
/// Contextuel plutôt qu'une page à part : l'utilisateur regarde déjà cette
/// compétition, et un écran de plus dans la navigation coûterait plus qu'il
/// ne rapporte. Seuls les buteurs étaient affichés, alors que l'API publie les
/// quatre au même prix — et les cartons servent directement les pronostics
/// « nombre de cartons ».
class _MeilleursButeurs extends ConsumerStatefulWidget {
  final String leagueCode;
  const _MeilleursButeurs({required this.leagueCode});

  @override
  ConsumerState<_MeilleursButeurs> createState() => _MeilleursButeursState();
}

class _MeilleursButeursState extends ConsumerState<_MeilleursButeurs> {
  Palmares _palmares = Palmares.buteurs;

  static String _titre(BuildContext context, Palmares p) => switch (p) {
    Palmares.buteurs  => tr(context, "Buteurs"),
    Palmares.passeurs => tr(context, "Passeurs"),
    Palmares.jaunes   => tr(context, "Cartons jaunes"),
    Palmares.rouges   => tr(context, "Cartons rouges"),
  };

  static int _valeur(TopScorer j, Palmares p) => switch (p) {
    Palmares.buteurs  => j.goals,
    Palmares.passeurs => j.assists,
    Palmares.jaunes   => j.yellowCards,
    Palmares.rouges   => j.redCards,
  };

  static String _lecture(BuildContext context, TopScorer j, Palmares p) => switch (p) {
    Palmares.buteurs  => tr(context, "{arg0}. {arg1}, {arg2}, {arg3} buts en {arg4} matchs", [j.rank, j.name, j.team, j.goals, j.appearances]),
    Palmares.passeurs => tr(context, "{arg0}. {arg1}, {arg2}, {arg3} passes décisives en {arg4} matchs", [j.rank, j.name, j.team, j.assists, j.appearances]),
    Palmares.jaunes   => tr(context, "{arg0}. {arg1}, {arg2}, {arg3} cartons jaunes en {arg4} matchs", [j.rank, j.name, j.team, j.yellowCards, j.appearances]),
    Palmares.rouges   => tr(context, "{arg0}. {arg1}, {arg2}, {arg3} cartons rouges en {arg4} matchs", [j.rank, j.name, j.team, j.redCards, j.appearances]),
  };

  Color _couleur(BuildContext context, Palmares p) => switch (p) {
    Palmares.buteurs  => context.cl.error,
    Palmares.passeurs => context.cl.info,
    Palmares.jaunes   => context.cl.warning,
    Palmares.rouges   => context.cl.error,
  };

  @override
  Widget build(BuildContext context) {
    final code = widget.leagueCode;
    if (code.isEmpty || code.startsWith('AF_')) return const SizedBox.shrink();

    // La carte n'existe que si la compétition publie au moins ses buteurs :
    // une compétition sans palmarès n'a pas de raison d'afficher des onglets.
    final buteurs = ref.watch(topScorersProvider((code: code, palmares: Palmares.buteurs)));
    if ((buteurs.valueOrNull ?? const <TopScorer>[]).isEmpty) return const SizedBox.shrink();

    final liste = ref.watch(topScorersProvider((code: code, palmares: _palmares)));
    final couleur = _couleur(context, _palmares);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cl.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.cl.borderSoft, width: 0.8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: context.cl.error.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10)),
            child: Icon(Icons.emoji_events_rounded,
                color: context.cl.error, size: 16)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(tr(context, "Meilleurs joueurs de la compétition"),
              style: TextStyle(
                color: context.cl.textP, fontSize: 13, fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 12),
        // Retour à la ligne plutôt que défilement : les quatre choix restent
        // visibles, même avec le texte agrandi.
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final p in Palmares.values)
            ChoiceChip(
              key: Key('palmares-${p.name}'),
              label: Text(_titre(context, p)),
              selected: p == _palmares,
              onSelected: (_) => setState(() => _palmares = p),
              labelStyle: TextStyle(
                fontSize: 11.5,
                fontWeight: p == _palmares ? FontWeight.w700 : FontWeight.w500,
                color: p == _palmares ? context.cl.textP : context.cl.textS),
              selectedColor: _couleur(context, p).withValues(alpha: 0.16),
              side: BorderSide(color: p == _palmares
                  ? _couleur(context, p).withValues(alpha: 0.5)
                  : context.cl.borderSoft),
              showCheckmark: false,
              visualDensity: VisualDensity.compact,
            ),
        ]),
        const SizedBox(height: 14),
        ...liste.when(
          loading: () => [const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(child: SizedBox(width: 20, height: 20,
              child: CircularProgressIndicator(strokeWidth: 2))))],
          error: (_, _) => [Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(tr(context, "Ce classement est momentanément indisponible."),
              style: TextStyle(color: context.cl.textM, fontSize: 12)))],
          data: (joueurs) {
            // Un carton rouge reste rare : une liste de zéros n'apprend rien.
            final utiles = joueurs.where((j) => _valeur(j, _palmares) > 0).take(10).toList();
            if (utiles.isEmpty) {
              return [Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(tr(context, "Pas encore de données pour ce classement cette saison."),
                  style: TextStyle(color: context.cl.textM, fontSize: 12)))];
            }
            return [
              for (final j in utiles)
                Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: LienJoueur(id: j.id, nom: j.name, photo: j.photo,
                  child: Semantics(
                    label: _lecture(context, j, _palmares),
                    excludeSemantics: true,
                    child: Row(children: [
                      SizedBox(width: 18,
                        child: Text('${j.rank}',
                          style: TextStyle(
                            color: j.rank <= 3 ? couleur : context.cl.textM,
                            fontSize: 11, fontWeight: FontWeight.w700))),
                      _PhotoJoueur(url: j.photo, taille: 26),
                      const SizedBox(width: 9),
                      Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(j.name,
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: context.cl.textP, fontSize: 12,
                              fontWeight: FontWeight.w600)),
                          Text(j.team,
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: context.cl.textM, fontSize: 10)),
                        ])),
                      const SizedBox(width: 8),
                      Text(tr(context, "{arg0} m.", [j.appearances]),
                        style: TextStyle(color: context.cl.textM, fontSize: 10.5)),
                      const SizedBox(width: 8),
                      Container(
                        constraints: const BoxConstraints(minWidth: 30),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: couleur.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(7)),
                        child: Text('${_valeur(j, _palmares)}',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: couleur, fontSize: 12,
                            fontWeight: FontWeight.w700))),
                    ]),
                  )),
                ),
            ];
          },
        ),
      ]),
    );
  }
}

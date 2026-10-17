// Compositions et terrain — extrait de match_detail_page.dart.
//
// `part` et non un fichier autonome : toutes ces classes sont privées à
// la bibliothèque (préfixe `_`) et le resteront. Un import classique aurait
// imposé de les rendre publiques, donc visibles depuis n'importe où.
part of '../match_detail_page.dart';

class _LineupsCard extends ConsumerWidget {
  /// Le match entier, et non son seul identifiant : le terrain porte
  /// desormais l'ecusson et le nom de chaque equipe, que la reponse
  /// `/lineups` ne contient pas.
  final MatchEntity match;
  const _LineupsCard({required this.match});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lineupsAsync = ref.watch(lineupsProvider(match.id));
    final status = _statusOf(lineupsAsync.error);
    // Notes et événements par joueur, une fois le match commencé (style
    // Sofascore, 17 octobre 2026). Une absence de notes n'empêche rien.
    final commence = match.status != MatchStatus.upcoming;
    final notes = commence
        ? ref.watch(playerRatingsProvider(match.id)).valueOrNull ?? const <PlayerRating>[]
        : const <PlayerRating>[];
    final evenements = commence
        ? ref.watch(matchStatsProvider(match.id)).valueOrNull?.events ?? const <MatchEvent>[]
        : const <MatchEvent>[];
    final infos = infosJoueurs(notes: notes, evenements: evenements);

    // Vraie erreur réseau/serveur (pas juste un invité non connecté) → pas de
    // carte plutôt qu'un message alarmant.
    if (lineupsAsync.hasError && status != 401) return const SizedBox.shrink();

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
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.groups_rounded, color: AppColors.primary, size: 16),
          ),
          const SizedBox(width: 10),
          Text(tr(context, "Compositions"),
            style: TextStyle(
              color: context.cl.textP,
              fontSize: 13,
              fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 14),
        status == 401
          ?  _CardLoginPrompt(message: tr(context, "Connecte-toi pour voir les compositions."))
          : lineupsAsync.when(
              loading: () => _H2HLoading(),
              error: (_, _) => const SizedBox.shrink(),
              data: (lineups) => !lineups.available
                ? _LineupsPending()
                : _LineupsContent(lineups: lineups, match: match, infos: infos,
                    noteDomicile: noteEquipe(notes, 'home'),
                    noteExterieur: noteEquipe(notes, 'away')),
            ),
      ]),
    );
  }
}

class _LineupsPending extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(Icons.schedule_rounded, color: context.cl.textM, size: 16),
    const SizedBox(width: 8),
    Expanded(
      child: Text(tr(context, "Compositions pas encore annoncées — publiées ~1h avant le coup d'envoi."),
        style: TextStyle(color: context.cl.textM, fontSize: 12))),
  ]);
}

class _LineupsContent extends StatelessWidget {
  final LineupsData lineups;
  final MatchEntity match;
  final Map<int, InfosJoueur> infos;
  final double? noteDomicile, noteExterieur;
  const _LineupsContent({required this.lineups, required this.match,
    this.infos = const {}, this.noteDomicile, this.noteExterieur});

  /// Le terrain n'a de sens que si l'API a placé les joueurs (champ `grid`).
  /// Certaines compétitions mineures ne le renseignent pas — on retombe alors
  /// sur la liste en pastilles, qui reste lisible sans coordonnées.
  bool _placeable(TeamLineup? t) =>
    t != null && t.startXI.isNotEmpty && t.startXI.every((p) => p.gridRow != null);

  @override
  Widget build(BuildContext context) {
    final home = lineups.home, away = lineups.away;

    if (_placeable(home) || _placeable(away)) {
      return Column(children: [
        _PitchView(home: home, away: away, match: match, infos: infos,
          noteDomicile: noteDomicile, noteExterieur: noteExterieur),
        const SizedBox(height: 14),
        if (home != null && home.substitutes.isNotEmpty) ...[
          _Remplacants(equipe: home, nom: match.homeTeam, logo: match.homeTeamLogo, infos: infos),
          const SizedBox(height: 12),
        ],
        if (away != null && away.substitutes.isNotEmpty) ...[
          _Remplacants(equipe: away, nom: match.awayTeam, logo: match.awayTeamLogo, infos: infos),
          const SizedBox(height: 14),
        ],
        // La formation figure desormais dans l'en-tete de chaque terrain ; ne
        // reste ici que l'entraineur, avec sa photo — fournie par l'API a cote
        // de son nom, et jamais lue jusqu'ici.
        _CarteEntraineurs(home: home, away: away),
      ]);
    }

    return Column(children: [
      if (home != null) _TeamLineupBlock(team: home, color: context.cl.success),
      if (home != null && away != null) const SizedBox(height: 16),
      if (away != null) _TeamLineupBlock(team: away, color: context.cl.error),
    ]);
  }
}

/// Terrain vu du dessus : l'équipe à domicile occupe la moitié haute (gardien
/// tout en haut), l'équipe visiteuse la moitié basse en miroir.
class _PitchView extends StatelessWidget {
  final TeamLineup? home;
  final TeamLineup? away;
  final MatchEntity match;
  final Map<int, InfosJoueur> infos;
  final double? noteDomicile, noteExterieur;
  const _PitchView({this.home, this.away, required this.match,
    this.infos = const {}, this.noteDomicile, this.noteExterieur});

  /// Regroupe les titulaires par ligne (1 = gardien) en respectant l'ordre de
  /// colonne renvoye par l'API.
  static List<List<LineupPlayer>> rangees(TeamLineup t) {
    final byRow = <int, List<LineupPlayer>>{};
    for (final p in t.startXI) {
      final r = p.gridRow;
      if (r != null) (byRow[r] ??= []).add(p);
    }
    final keys = byRow.keys.toList()..sort();
    return [
      for (final k in keys)
        byRow[k]!..sort((a, b) => (a.gridCol ?? 0).compareTo(b.gridCol ?? 0)),
    ];
  }

  @override
  Widget build(BuildContext context) => Column(children: [
    if (home != null)
      _TerrainEquipe(
        equipe: home!, nom: match.homeTeam, logo: match.homeTeamLogo,
        couleur: _domicileSurTerrain, infos: infos, note: noteDomicile),
    if (home != null && away != null) const SizedBox(height: 14),
    // L'equipe exterieure est en miroir : gardien en bas, attaquants en haut,
    // et son en-tete sous le terrain plutot qu'au-dessus.
    //
    // J'avais supprime ce renversement en donnant un terrain a chacune, en
    // croyant qu'il ne servait qu'a faire tenir deux equipes sur une surface.
    // Il porte en fait autre chose : mises bout a bout, les deux moities se
    // font face comme un terrain deplie, et chaque equipe attaque vers
    // l'adversaire. Lire les deux dans le meme sens supprime cette lecture.
    if (away != null)
      _TerrainEquipe(
        equipe: away!, nom: match.awayTeam, logo: match.awayTeamLogo,
        couleur: _exterieurSurTerrain, miroir: true, infos: infos, note: noteExterieur),
  ]);
}

/// Terrain d'une seule equipe, avec son en-tete.
///
/// Les deux equipes partageaient auparavant **un seul terrain**, l'une en
/// miroir de l'autre. Le commentaire du code admettait deja le prix de ce
/// choix : a onze joueurs par moitie, les photos tombaient a dix-huit pixels
/// et les noms se compressaient dans un `FittedBox`.
///
/// Un terrain par equipe rend a chaque ligne toute la hauteur qu'il lui faut.
/// L'ecusson et la formation en en-tete disent immediatement qui joue comment
/// — ils venaient du match, pas de la reponse `/lineups`, et manquaient donc.
class _TerrainEquipe extends StatelessWidget {
  final TeamLineup equipe;
  final String nom;
  final String? logo;
  final Color couleur;
  /// Renverse lignes et colonnes, et fait passer l'en-tete sous le terrain.
  final bool miroir;
  final Map<int, InfosJoueur> infos;
  /// Note moyenne de l'équipe, à côté de son nom (Sofascore).
  final double? note;
  const _TerrainEquipe({
    required this.equipe, required this.nom, this.logo, required this.couleur,
    this.miroir = false, this.infos = const {}, this.note});

  static const _grass     = Color(0xFF14532D);
  static const _grassAlt  = Color(0xFF166534);
  static const _lineColor = Color(0x59FFFFFF);

  @override
  Widget build(BuildContext context) {
    var rows = _PitchView.rangees(equipe);
    if (rows.isEmpty) return const SizedBox.shrink();
    if (miroir) {
      rows = [for (final r in rows.reversed) r.reversed.toList()];
    }

    final entete = Padding(
        padding: EdgeInsets.only(left: 2, bottom: miroir ? 0 : 8, top: miroir ? 8 : 0),
        child: Row(children: [
          if (logo != null && logo!.isNotEmpty) ...[
            SizedBox(width: 18, height: 18,
              child: ImageDistante(
                url:     logo,
                largeur: 18, hauteur: 18,
                fit:     BoxFit.contain,
                repli:   const SizedBox.shrink())),
            const SizedBox(width: 8),
          ],
          Flexible(child: Text(nom,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: context.cl.textP, fontSize: 13, fontWeight: FontWeight.w700))),
          if (note != null) ...[
            const SizedBox(width: 8),
            PastilleNote(note!, taille: 11),
          ],
          if (equipe.formation != null) ...[
            const SizedBox(width: 10),
            Text(equipe.formation!,
              style: TextStyle(
                color: couleur, fontSize: 12.5, fontWeight: FontWeight.w700,
                letterSpacing: 0.4)),
          ],
        ]),
      );

    final terrain = AspectRatio(
        // Proche du carre : chaque equipe dispose de la hauteur qui etait
        // auparavant partagee entre les deux. Les photos y tiennent sans
        // compression.
        aspectRatio: 0.92,
        child: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [_grass, _grassAlt, _grass],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Stack(children: [
            Positioned.fill(child: CustomPaint(painter: _PitchLinesPainter())),
            // Gardien en haut, attaquants en bas : le sens de lecture naturel
            // quand une equipe occupe tout le terrain.
            _HalfPitch(rows: rows, color: couleur, infos: infos),
          ]),
        ),
      );

    return Column(crossAxisAlignment: CrossAxisAlignment.start,
      children: miroir ? [terrain, entete] : [entete, terrain]);
  }
}

class _HalfPitch extends StatelessWidget {
  final List<List<LineupPlayer>> rows;
  final Color color;
  final Map<int, InfosJoueur> infos;
  const _HalfPitch({required this.rows, required this.color, this.infos = const {}});

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();

    // Le nombre de lignes dépend de la formation (4 pour un 4-4-2, 5 pour un
    // 4-2-3-1…) : on répartit d'abord la hauteur disponible, puis on en déduit
    // la taille des photos. Avec une taille fixe, les formations les plus
    // profondes débordaient du terrain.
    return LayoutBuilder(builder: (context, constraints) {
      final rowHeight = constraints.maxHeight / rows.length;
      // ~20px sont pris par le nom sous la photo et l'espacement.
      //
      // Le plafond est passe de 34 a 52 px : il datait du terrain partage, ou
      // onze joueurs tenaient dans une demi-hauteur. Avec un terrain par
      // equipe, le brider a 34 aurait laisse la place inutilisee.
      final avatar = (rowHeight - 20).clamp(18.0, 52.0);

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(children: [
          for (final row in rows)
            SizedBox(
              height: rowHeight,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final p in row)
                    _PitchPlayer(player: p, color: color, size: avatar,
                      infos: p.id == null ? null : infos[p.id]),
                ],
              ),
            ),
        ]),
      );
    });
  }
}

/// Couleurs d'équipe **sur le terrain** uniquement.
///
/// Hors du terrain (listes, entraîneurs), le vert et le rouge de la charte
/// fonctionnent : le fond est sombre. Sur l'herbe, le vert de `AppColors.success`
/// se confondait avec le gazon. Blanc et bleu nuit tranchent dans les deux sens.
const Color _domicileSurTerrain  = Color(0xFFF2F4F8);
const Color _exterieurSurTerrain = Color(0xFF5C7CFA);

class _PitchPlayer extends StatelessWidget {
  final LineupPlayer player;
  final Color color;
  final double size;
  /// Note, buts, cartons, sortie (style Sofascore).
  final InfosJoueur? infos;
  const _PitchPlayer({required this.player, required this.color, required this.size, this.infos});

  /// Couleur du texte du numéro, choisie d'après la luminance de la pastille.
  /// L'équipe à domicile portait `AppColors.success` — du vert, sur un terrain
  /// vert : la pastille disparaissait dans le fond.
  Color get _surPastille =>
      color.computeLuminance() > 0.55 ? const Color(0xFF0D1220) : Colors.white;

  @override
  Widget build(BuildContext context) => Flexible(
    // Dernier filet : si la ligne est vraiment trop basse (petit écran, 5
    // lignes), l'ensemble photo+nom est réduit au lieu de déborder.
    child: LienJoueur(id: player.id, nom: player.name, photo: player.photoUrl,
      rayon: BorderRadius.circular(40),
      child: FittedBox(
      fit: BoxFit.scaleDown,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Stack(clipBehavior: Clip.none, children: [
          Container(
            width: size, height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black26,
              border: Border.all(color: color, width: 2),
              boxShadow: const [BoxShadow(
                color: Colors.black45, blurRadius: 3, offset: Offset(0, 1))],
            ),
            child: ClipOval(
              child: player.photoUrl == null
                ? Icon(Icons.person_rounded, color: Colors.white70, size: size * 0.55)
                // Le CDN peut renvoyer un 404 pour un joueur sans photo :
                // on retombe sur l'icône générique plutôt que sur une erreur.
                : ImageDistante(
                    url:     player.photoUrl,
                    largeur: size, hauteur: size,
                    repli:   Icon(Icons.person_rounded,
                                  color: Colors.white70, size: size * 0.55),
                  ),
            ),
          ),
          // Note en bas à gauche, événements en haut à droite, capitaine en
          // haut à gauche : la disposition de Sofascore.
          if (infos?.note != null)
            Positioned(left: -6, bottom: -4,
              child: PastilleNote(infos!.note!, taille: 8)),
          if (infos != null && infos!.aDesEvenements)
            Positioned(right: -7, top: -5, child: _BadgesJoueur(infos: infos!)),
          if (infos?.capitaine == true)
            Positioned(left: -4, top: -4, child: Container(
              width: 13, height: 13,
              decoration: const BoxDecoration(color: Color(0xFFF5C518), shape: BoxShape.circle),
              alignment: Alignment.center,
              child: const Text('C', style: TextStyle(color: Color(0xFF0D1220),
                fontSize: 8, fontWeight: FontWeight.w900)))),
          if (player.number != null)
            Positioned(
              bottom: -3, right: -3,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('${player.number}',
                  style: TextStyle(
                    color: _surPastille, fontSize: 8.5, fontWeight: FontWeight.w700)),
              ),
            ),
        ]),
        const SizedBox(height: 4),
        Text(player.shortName,
          maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white, fontSize: 8.5, fontWeight: FontWeight.w600,
            shadows: [Shadow(color: Colors.black87, blurRadius: 3)])),
      ]),
    )),
  );
}

/// Événements d'un joueur sur sa photo : buts, but contre son camp, cartons,
/// sortie — comme Sofascore.
class _BadgesJoueur extends StatelessWidget {
  final InfosJoueur infos;
  const _BadgesJoueur({required this.infos});

  static const _jaune = Color(0xFFF5C518);
  static const _rouge = Color(0xFFE53935);

  Widget _rond(Widget enfant, {Color fond = Colors.white}) => Container(
    width: 13, height: 13,
    decoration: BoxDecoration(color: fond, shape: BoxShape.circle,
      boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 2)]),
    alignment: Alignment.center,
    child: enfant);

  Widget _carton(Color c) => Container(width: 7, height: 10,
    decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(1.5),
      boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 2)]));

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    for (var i = 0; i < infos.buts.clamp(0, 3); i++)
      _rond(const Icon(Icons.sports_soccer_rounded, size: 11, color: Color(0xFF0D1220))),
    for (var i = 0; i < infos.butsContreSonCamp.clamp(0, 2); i++)
      _rond(const Icon(Icons.sports_soccer_rounded, size: 11, color: _rouge)),
    if (infos.rouges > 0) _carton(_rouge)
    else if (infos.jaunes > 0) _carton(_jaune),
    if (infos.sortie != null)
      _rond(const Icon(Icons.arrow_downward_rounded, size: 10, color: Colors.white), fond: _rouge),
  ]);
}

/// Remplaçants d'une équipe : ceux entrés en jeu d'abord, avec leur minute,
/// le joueur remplacé et leur note ; puis ceux restés sur le banc.
class _Remplacants extends StatelessWidget {
  final TeamLineup equipe;
  final String nom;
  final String? logo;
  final Map<int, InfosJoueur> infos;
  const _Remplacants({required this.equipe, required this.nom, this.logo, this.infos = const {}});

  @override
  Widget build(BuildContext context) {
    InfosJoueur? de(LineupPlayer p) => p.id == null ? null : infos[p.id];
    final entres = [for (final p in equipe.substitutes) if (de(p)?.entree != null) p]
      ..sort((a, b) => de(a)!.entree!.compareTo(de(b)!.entree!));
    final banc = [for (final p in equipe.substitutes) if (de(p)?.entree == null) p];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      decoration: BoxDecoration(
        color: context.cl.surfaceDeep,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.cl.borderSoft, width: 0.6)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (logo != null && logo!.isNotEmpty) ...[
            SizedBox(width: 16, height: 16, child: ImageDistante(url: logo, largeur: 16, hauteur: 16,
              fit: BoxFit.contain, repli: const SizedBox.shrink())),
            const SizedBox(width: 8),
          ],
          Expanded(child: Text(tr(context, "Remplaçants · {arg0}", [nom]),
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(color: context.cl.textP, fontSize: 12.5, fontWeight: FontWeight.w700))),
        ]),
        const SizedBox(height: 6),
        for (final p in [...entres, ...banc]) _LigneRemplacant(joueur: p, infos: de(p)),
      ]),
    );
  }
}

class _LigneRemplacant extends StatelessWidget {
  final LineupPlayer joueur;
  final InfosJoueur? infos;
  const _LigneRemplacant({required this.joueur, this.infos});

  @override
  Widget build(BuildContext context) {
    final entre = infos?.entree != null;
    final sousTitre = !entre
        ? tr(context, "Sur le banc")
        : infos!.remplace != null
            ? tr(context, "Entré à la {arg0}e · remplace {arg1}", [infos!.entree, infos!.remplace])
            : tr(context, "Entré à la {arg0}e", [infos!.entree]);
    return LienJoueur(id: joueur.id, nom: joueur.name, photo: joueur.photoUrl,
      rayon: BorderRadius.circular(8),
      child: Opacity(
        // Un joueur resté sur le banc reste lisible, mais en retrait.
        opacity: entre ? 1 : 0.6,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            Container(
              width: 30, height: 30,
              decoration: BoxDecoration(color: context.cl.surface, shape: BoxShape.circle),
              clipBehavior: Clip.antiAlias,
              child: joueur.photoUrl == null
                ? Icon(Icons.person_rounded, color: context.cl.textM, size: 16)
                : ImageDistante(url: joueur.photoUrl, largeur: 30, hauteur: 30,
                    repli: Icon(Icons.person_rounded, color: context.cl.textM, size: 16)),
            ),
            const SizedBox(width: 10),
            if (joueur.number != null)
              SizedBox(width: 22, child: Text('${joueur.number}',
                style: TextStyle(color: context.cl.textM, fontSize: 11.5, fontWeight: FontWeight.w700))),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(joueur.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: context.cl.textP, fontSize: 12.5, fontWeight: FontWeight.w600)),
              Row(children: [
                if (entre) ...[
                  Icon(Icons.arrow_upward_rounded, size: 11, color: context.cl.success),
                  const SizedBox(width: 3),
                ],
                Flexible(child: Text(sousTitre, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: context.cl.textM, fontSize: 10.5))),
              ]),
            ])),
            if (infos != null && infos!.aDesEvenements) ...[
              const SizedBox(width: 6),
              _BadgesJoueur(infos: infos!),
            ],
            if (infos?.note != null) ...[
              const SizedBox(width: 8),
              PastilleNote(infos!.note!, taille: 10.5),
            ],
          ]),
        ),
      ),
    );
  }
}

/// Lignes du terrain (touches, rond central, surfaces) tracées par-dessus la
/// pelouse — purement décoratif, aucune donnée.
class _PitchLinesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _TerrainEquipe._lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    final r = Rect.fromLTWH(6, 6, size.width - 12, size.height - 12);
    canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(8)), paint);

    // Ligne médiane + rond central
    canvas.drawLine(
      Offset(r.left, size.height / 2), Offset(r.right, size.height / 2), paint);
    canvas.drawCircle(Offset(size.width / 2, size.height / 2), size.width * 0.13, paint);

    // Surfaces de réparation, haut et bas
    final boxW = size.width * 0.46, boxH = size.height * 0.13;
    for (final top in [r.top, r.bottom - boxH]) {
      canvas.drawRect(
        Rect.fromLTWH((size.width - boxW) / 2, top, boxW, boxH), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Formation + entraîneur, sous le terrain.
class _TeamCoachRow extends StatelessWidget {
  final TeamLineup team;
  final Color color;
  const _TeamCoachRow({required this.team, required this.color});

  @override
  Widget build(BuildContext context) => Row(children: [
    if (team.formation != null) ...[
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6)),
        child: Text(team.formation!,
          style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
      ),
      const SizedBox(width: 8),
    ],
    if (team.coach != null)
      Expanded(
        child: Text(tr(context, "Entraîneur : {arg0}", [team.coach]),
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(color: context.cl.textM, fontSize: 11))),
  ]);
}

/// Entraineurs des deux equipes, cote a cote.
///
/// Le nom etait affiche en legende sous le terrain ; la photo accompagnait ce
/// nom dans la meme reponse de l'API et n'etait pas lue. Un visage se
/// reconnait plus vite qu'un patronyme, surtout etranger.
class _CarteEntraineurs extends StatelessWidget {
  final TeamLineup? home;
  final TeamLineup? away;
  const _CarteEntraineurs({this.home, this.away});

  @override
  Widget build(BuildContext context) {
    final aDomicile   = home?.coach != null;
    final aExterieur  = away?.coach != null;
    if (!aDomicile && !aExterieur) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: context.cl.surfaceDeep,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.cl.borderSoft, width: 0.6),
      ),
      child: Column(children: [
        Text(tr(context, "Entraîneurs"),
          style: TextStyle(
            color: context.cl.textM, fontSize: 10,
            fontWeight: FontWeight.w700, letterSpacing: 0.6)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _UnEntraineur(equipe: home)),
          Expanded(child: _UnEntraineur(equipe: away)),
        ]),
      ]),
    );
  }
}

class _UnEntraineur extends StatelessWidget {
  final TeamLineup? equipe;
  const _UnEntraineur({this.equipe});

  @override
  Widget build(BuildContext context) {
    final nom = equipe?.coach;
    if (nom == null) return const SizedBox.shrink();
    final photo = equipe?.coachPhoto;

    return Column(children: [
      Container(
        width: 46, height: 46,
        decoration: BoxDecoration(
          color: context.cl.surface,
          shape: BoxShape.circle,
          border: Border.all(color: context.cl.borderSoft, width: 0.8)),
        clipBehavior: Clip.antiAlias,
        child: photo == null || photo.isEmpty
          ? Icon(Icons.person_rounded, color: context.cl.textM, size: 22)
          // Une photo absente ne doit pas laisser un trou : on retombe sur la
          // silhouette, de meme taille.
          : ImageDistante(
              url:     photo,
              largeur: 52, hauteur: 52,
              repli:   Icon(Icons.person_rounded,
                            color: context.cl.textM, size: 22)),
      ),
      const SizedBox(height: 7),
      Text(nom,
        maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: context.cl.textS, fontSize: 11.5, height: 1.25,
          fontWeight: FontWeight.w600)),
    ]);
  }
}

/// Repli quand l'API ne fournit pas les coordonnées `grid` : liste en pastilles.
class _TeamLineupBlock extends StatelessWidget {
  final TeamLineup team;
  final Color color;
  const _TeamLineupBlock({required this.team, required this.color});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _TeamCoachRow(team: team, color: color),
      const SizedBox(height: 8),
      Wrap(
        spacing: 6, runSpacing: 6,
        children: team.startXI.map((p) => _PlayerChip(player: p, color: color)).toList(),
      ),
    ],
  );
}

class _PlayerChip extends StatelessWidget {
  final LineupPlayer player;
  final Color color;
  const _PlayerChip({required this.player, required this.color});

  @override
  Widget build(BuildContext context) => LienJoueur(
    id: player.id, nom: player.name, photo: player.photoUrl, rayon: BorderRadius.circular(8),
    child: Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: context.cl.surfaceD,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: context.cl.border, width: 0.5)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      if (player.number != null) ...[
        Text('${player.number}',
          style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
        const SizedBox(width: 4),
      ],
      Text(player.name,
        style: TextStyle(color: context.cl.textS, fontSize: 11)),
    ]),
  ));
}

// ─── BLESSURES / SUSPENSIONS ────────────────────────────────────────────────────

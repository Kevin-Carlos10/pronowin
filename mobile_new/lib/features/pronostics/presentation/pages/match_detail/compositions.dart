// Compositions et terrain — extrait de match_detail_page.dart.
//
// `part` et non un fichier autonome : toutes ces classes sont privées à
// la bibliothèque (préfixe `_`) et le resteront. Un import classique aurait
// imposé de les rendre publiques, donc visibles depuis n'importe où.
part of '../match_detail_page.dart';

class _LineupsCard extends ConsumerWidget {
  final String matchId;
  const _LineupsCard({required this.matchId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lineupsAsync = ref.watch(lineupsProvider(matchId));
    final status = _statusOf(lineupsAsync.error);

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
          Text('Compositions',
            style: TextStyle(
              color: context.cl.textP,
              fontSize: 13,
              fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 14),
        status == 401
          ? const _CardLoginPrompt(message: 'Connecte-toi pour voir les compositions.')
          : lineupsAsync.when(
              loading: () => _H2HLoading(),
              error: (_, __) => const SizedBox.shrink(),
              data: (lineups) => !lineups.available
                ? _LineupsPending()
                : _LineupsContent(lineups: lineups),
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
      child: Text('Compositions pas encore annoncées — publiées ~1h avant le coup d\'envoi.',
        style: TextStyle(color: context.cl.textM, fontSize: 12))),
  ]);
}

class _LineupsContent extends StatelessWidget {
  final LineupsData lineups;
  const _LineupsContent({required this.lineups});

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
        _PitchView(home: home, away: away),
        const SizedBox(height: 14),
        // Légende du terrain : mêmes couleurs que les pastilles au-dessus.
        // Avec le vert/rouge de la charte, rien ne reliait une moitié de
        // terrain à son équipe.
        if (home != null) _TeamCoachRow(team: home, color: _domicileSurTerrain),
        if (home != null && away != null) const SizedBox(height: 6),
        if (away != null) _TeamCoachRow(team: away, color: _exterieurSurTerrain),
      ]);
    }

    return Column(children: [
      if (home != null) _TeamLineupBlock(team: home, color: AppColors.success),
      if (home != null && away != null) const SizedBox(height: 16),
      if (away != null) _TeamLineupBlock(team: away, color: AppColors.error),
    ]);
  }
}

/// Terrain vu du dessus : l'équipe à domicile occupe la moitié haute (gardien
/// tout en haut), l'équipe visiteuse la moitié basse en miroir.
class _PitchView extends StatelessWidget {
  final TeamLineup? home;
  final TeamLineup? away;
  const _PitchView({this.home, this.away});

  static const _grass     = Color(0xFF14532D);
  static const _grassAlt  = Color(0xFF166534);
  static const _lineColor = Color(0x59FFFFFF);

  /// Regroupe les titulaires par ligne (1 = gardien) en respectant l'ordre de
  /// colonne renvoyé par l'API.
  static List<List<LineupPlayer>> _rows(TeamLineup t) {
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
  Widget build(BuildContext context) => AspectRatio(
    // Assez haut pour qu'un 4-2-3-1 (5 lignes par moitié) garde des photos
    // lisibles sans que _HalfPitch ait à les rétrécir — mais pas au point
    // d'exiger deux écrans de défilement pour voir l'équipe adverse : à 0.62
    // le terrain dépassait 2 000 px de haut sur un grand téléphone.
    // _PitchPlayer met déjà les joueurs dans un FittedBox, la compression
    // résiduelle reste lisible.
    aspectRatio: 0.78,
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
        Column(children: [
          Expanded(
            child: home == null
              ? const SizedBox.shrink()
              : _HalfPitch(rows: _rows(home!), color: _domicileSurTerrain),
          ),
          Expanded(
            child: away == null
              ? const SizedBox.shrink()
              // Miroir complet : lignes inversées (le gardien visiteur passe en
              // bas) et colonnes inversées, pour que les deux équipes se fassent
              // face comme sur un vrai terrain.
              : _HalfPitch(
                  rows: [
                    for (final r in _rows(away!).reversed) r.reversed.toList(),
                  ],
                  color: _exterieurSurTerrain),
          ),
        ]),
      ]),
    ),
  );
}

class _HalfPitch extends StatelessWidget {
  final List<List<LineupPlayer>> rows;
  final Color color;
  const _HalfPitch({required this.rows, required this.color});

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
      final avatar = (rowHeight - 20).clamp(18.0, 34.0);

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
                    _PitchPlayer(player: p, color: color, size: avatar),
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
  const _PitchPlayer({required this.player, required this.color, required this.size});

  /// Couleur du texte du numéro, choisie d'après la luminance de la pastille.
  /// L'équipe à domicile portait `AppColors.success` — du vert, sur un terrain
  /// vert : la pastille disparaissait dans le fond.
  Color get _surPastille =>
      color.computeLuminance() > 0.55 ? const Color(0xFF0D1220) : Colors.white;

  @override
  Widget build(BuildContext context) => Flexible(
    // Dernier filet : si la ligne est vraiment trop basse (petit écran, 5
    // lignes), l'ensemble photo+nom est réduit au lieu de déborder.
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
                : Image.network(
                    player.photoUrl!,
                    fit: BoxFit.cover,
                    // Le CDN peut renvoyer un 404 pour un joueur sans photo :
                    // on retombe sur l'icône générique plutôt que sur une erreur.
                    errorBuilder: (_, e, s) =>
                      Icon(Icons.person_rounded, color: Colors.white70, size: size * 0.55),
                  ),
            ),
          ),
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
                    color: _surPastille, fontSize: 8.5, fontWeight: FontWeight.w900)),
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
    ),
  );
}

/// Lignes du terrain (touches, rond central, surfaces) tracées par-dessus la
/// pelouse — purement décoratif, aucune donnée.
class _PitchLinesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _PitchView._lineColor
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
          style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800)),
      ),
      const SizedBox(width: 8),
    ],
    if (team.coach != null)
      Expanded(
        child: Text('Entraîneur : ${team.coach}',
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(color: context.cl.textM, fontSize: 11))),
  ]);
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
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: context.cl.surfaceD,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: context.cl.border, width: 0.5)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      if (player.number != null) ...[
        Text('${player.number}',
          style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800)),
        const SizedBox(width: 4),
      ],
      Text(player.name,
        style: TextStyle(color: context.cl.textS, fontSize: 11)),
    ]),
  );
}

// ─── BLESSURES / SUSPENSIONS ────────────────────────────────────────────────────

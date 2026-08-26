// Blessures et suspensions — extrait de match_detail_page.dart.
//
// `part` et non un fichier autonome : toutes ces classes sont privées à
// la bibliothèque (préfixe `_`) et le resteront. Un import classique aurait
// imposé de les rendre publiques, donc visibles depuis n'importe où.
part of '../match_detail_page.dart';

class _InjuriesCard extends ConsumerWidget {
  final String matchId;
  final String homeTeam;
  final String awayTeam;
  final String? homeLogo;
  final String? awayLogo;
  const _InjuriesCard({
    required this.matchId,
    this.homeTeam = '',
    this.awayTeam = '',
    this.homeLogo,
    this.awayLogo,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final injuriesAsync = ref.watch(injuriesProvider(matchId));
    final status = _statusOf(injuriesAsync.error);

    // Vraie erreur, ou pas de blessés → pas de carte (rien à signaler)
    if (injuriesAsync.hasError && status != 401) return const SizedBox.shrink();
    if (status == null && injuriesAsync.valueOrNull?.isEmpty == true) return const SizedBox.shrink();

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
              color: AppColors.warning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.medical_services_rounded, color: AppColors.warning, size: 16),
          ),
          const SizedBox(width: 10),
          Text('Absences',
            style: TextStyle(
              color: context.cl.textP,
              fontSize: 13,
              fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 12),
        status == 401
          ? const _CardLoginPrompt(message: 'Connecte-toi pour voir les absences.')
          : injuriesAsync.when(
              loading: () => _H2HLoading(),
              error: (_, _) => const SizedBox.shrink(),
              data: (list) {
                final home = list.where((p) => p.isHome).toList();
                final away = list.where((p) => !p.isHome).toList();
                return Column(children: [
                  if (home.isNotEmpty)
                    _InjuryTeamBlock(
                      team: homeTeam, logo: homeLogo,
                      players: home, color: AppColors.success),
                  if (home.isNotEmpty && away.isNotEmpty) const SizedBox(height: 18),
                  if (away.isNotEmpty)
                    _InjuryTeamBlock(
                      team: awayTeam, logo: awayLogo,
                      players: away, color: AppColors.error),
                ]);
              },
            ),
      ]),
    );
  }
}

/// Absences d'une équipe, regroupées sous son nom et son logo — plus lisible
/// que l'ancienne liste à plat où chaque ligne portait une pastille DOM/EXT.
class _InjuryTeamBlock extends StatelessWidget {
  final String team;
  final String? logo;
  final List<InjuredPlayer> players;
  final Color color;
  const _InjuryTeamBlock({
    required this.team,
    required this.players,
    required this.color,
    this.logo,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(children: [
        _TeamLogo(url: logo ?? '', size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(team.isEmpty ? 'Équipe' : team,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color, fontSize: 12, fontWeight: FontWeight.w700))),
        Text('${players.length}',
          style: TextStyle(
            color: context.cl.textM, fontSize: 11, fontWeight: FontWeight.w700)),
      ]),
      const SizedBox(height: 10),
      ...players.map((p) => _InjuryRow(player: p)),
    ],
  );
}

class _InjuryRow extends StatelessWidget {
  final InjuredPlayer player;
  const _InjuryRow({required this.player});

  /// Le motif arrive **deja traduit** du serveur.
  ///
  /// Une table vivait ici et sa regle etait juste — un motif inconnu restait
  /// affiche plutot que masque. Mais elle avait des trous, et rien ne les
  /// signalait : elle contenait `hamstring` quand l API envoie
  /// `Hamstring Injury`, si bien que deux motifs apparaissaient en anglais
  /// dans une liste par ailleurs francaise.
  ///
  /// La traduction se fait desormais a la frontiere du fournisseur, comme
  /// celle des recommandations et des marches — et un motif non reconnu s y
  /// journalise au lieu de finir a l ecran.

  @override
  Widget build(BuildContext context) {
    final isRed = player.reason.toLowerCase().contains('rouge');
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(children: [
        // Photo du joueur : fournie par l API dans la meme reponse et jamais
        // lue. Un visage se reconnait plus vite qu un patronyme abrege —
        // « R. Asencio » ne dit pas grand-chose.
        if (player.photo != null && player.photo!.isNotEmpty) ...[
          SizedBox(width: 26, height: 26,
            child: ClipOval(child: ImageDistante(
              url:     player.photo,
              largeur: 26, hauteur: 26,
              repli:   Icon(Icons.person_rounded,
                            color: context.cl.textM, size: 15)))),
          const SizedBox(width: 9),
        ],
        SizedBox(
          width: 18,
          child: Center(
            child: player.suspension
              ? Container(
                  width: 10, height: 13,
                  decoration: BoxDecoration(
                    color: isRed ? AppColors.error : AppColors.warning,
                    borderRadius: BorderRadius.circular(2)),
                )
              : Icon(Icons.healing_rounded, color: context.cl.textM, size: 14),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(player.name,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(color: context.cl.textP, fontSize: 12.5))),
        const SizedBox(width: 10),
        Flexible(
          child: Text(player.reason,
            textAlign: TextAlign.right,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(color: context.cl.textM, fontSize: 11)),
        ),
      ]),
    );
  }
}

// ─── CLASSEMENT ──────────────────────────────────────────────────────────────

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
              error: (_, __) => const SizedBox.shrink(),
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

  /// API-Football renvoie les motifs en anglais et en vrac. On traduit les
  /// valeurs courantes ; tout motif inconnu est affiché tel quel plutôt que
  /// masqué, pour ne pas perdre d'information.
  static const _reasons = {
    'yellow cards':    'Suspendu (cartons jaunes)',
    'yellow card':     'Suspendu (carton jaune)',
    'red card':        'Suspendu (carton rouge)',
    'suspended':       'Suspendu',
    'inactive':        'Indisponible',
    'injury':          'Blessé',
    'knee injury':     'Blessure au genou',
    'ankle injury':    'Blessure à la cheville',
    'thigh injury':    'Blessure à la cuisse',
    'hamstring':       'Ischio-jambiers',
    'muscle injury':   'Blessure musculaire',
    'calf injury':     'Blessure au mollet',
    'groin injury':    'Blessure à l\'aine',
    'back injury':     'Blessure au dos',
    'shoulder injury': 'Blessure à l\'épaule',
    'foot injury':     'Blessure au pied',
    'illness':         'Maladie',
    'personal reasons':'Raisons personnelles',
    'national team':   'Sélection nationale',
    'coach decision':  'Choix de l\'entraîneur',
    'rest':            'Au repos',
    'broken leg':      'Jambe cassée',
  };

  /// true pour une suspension (carton), false pour une indisponibilité
  /// physique — l'icône change en conséquence.
  bool get _isSuspension {
    final r = player.reason.toLowerCase();
    return r.contains('card') || r.contains('suspend');
  }

  String get _label {
    final raw = player.reason.trim().isNotEmpty ? player.reason.trim() : player.type;
    return _reasons[raw.toLowerCase()] ?? raw;
  }

  @override
  Widget build(BuildContext context) {
    final isRed = player.reason.toLowerCase().contains('red');
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(children: [
        SizedBox(
          width: 18,
          child: Center(
            child: _isSuspension
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
          child: Text(_label,
            textAlign: TextAlign.right,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(color: context.cl.textM, fontSize: 11)),
        ),
      ]),
    );
  }
}

// ─── CLASSEMENT ──────────────────────────────────────────────────────────────

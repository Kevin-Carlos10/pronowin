// Statistiques et faits marquants — extrait de match_detail_page.dart.
//
// `part` et non un fichier autonome : toutes ces classes sont privées à
// la bibliothèque (préfixe `_`) et le resteront. Un import classique aurait
// imposé de les rendre publiques, donc visibles depuis n'importe où.
part of '../match_detail_page.dart';

class _MatchStatsCard extends ConsumerWidget {
  final String matchId;
  const _MatchStatsCard({required this.matchId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(matchStatsProvider(matchId));

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
              color: AppColors.info.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.bar_chart_rounded, color: AppColors.info, size: 16),
          ),
          const SizedBox(width: 10),
          Text('Statistiques du match',
            style: TextStyle(
              color: context.cl.textP,
              fontSize: 13,
              fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 14),
        statsAsync.when(
          loading: () => _StatsLoading(),
          error: (_, __) => _StatsUnavailable(),
          data: (data) => data == null
            ? _StatsUnavailable()
            : _StatsList(stats: data.stats,
                homeTeam: data.homeTeam, awayTeam: data.awayTeam),
        ),
      ]),
    );
  }
}

/// Faits marquants du match (buts, cartons) — affichés dans l'onglet Détails,
/// séparément des statistiques chiffrées qui ont leur propre onglet.
/// Masquée quand il n'y a aucun événement notable à montrer.
class _MatchEventsCard extends ConsumerWidget {
  final String matchId;
  final MatchEntity match;
  const _MatchEventsCard({required this.matchId, required this.match});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(matchStatsProvider(matchId));
    final data = statsAsync.valueOrNull;
    if (data == null || !_EventsList.hasNotable(data.events)) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cl.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.cl.borderSoft, width: 0.8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _CardHeader(
          icon: Icons.timeline_rounded,
          color: AppColors.info,
          title: 'Faits marquants'),
        const SizedBox(height: 14),
        // En-tête et filet reprennent exactement la structure d'une ligne
        // d'événement (colonne minute + 2 colonnes + colonne icône) : leur
        // alignement est ainsi garanti par construction plutôt que par un
        // calcul de marges qui dériverait au moindre changement.
        Row(children: [
          const SizedBox(width: _EventsList.minuteWidth),
          Expanded(
            child: Center(child: _TeamLogo(url: match.homeTeamLogo ?? '', size: 20))),
          const SizedBox(width: _EventsList.iconWidth),
          Expanded(
            child: Center(child: _TeamLogo(url: match.awayTeamLogo ?? '', size: 20))),
        ]),
        const SizedBox(height: 12),
        Stack(children: [
          Positioned.fill(
            child: Row(children: [
              const SizedBox(width: _EventsList.minuteWidth),
              const Expanded(child: SizedBox()),
              SizedBox(
                width: _EventsList.iconWidth,
                child: Center(
                  child: Container(width: 1, color: context.cl.borderSoft))),
              const Expanded(child: SizedBox()),
            ]),
          ),
          _EventsList(events: data.events,
            homeTeam: data.homeTeam, awayTeam: data.awayTeam),
        ]),
      ]),
    );
  }
}

/// En-tête commun à toutes les cartes d'information : même taille d'icône,
/// même typographie. Évite que chaque carte dérive de son côté.
class _CardHeader extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  const _CardHeader({required this.icon, required this.color, required this.title});

  @override
  Widget build(BuildContext context) => Row(children: [
    Container(
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: color, size: 16),
    ),
    const SizedBox(width: 10),
    Expanded(
      child: Text(title,
        maxLines: 1, overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: context.cl.textP,
          fontSize: 13.5,
          fontWeight: FontWeight.w700)),
    ),
  ]);
}

class _EventsList extends StatelessWidget {
  final List<MatchEvent> events;
  final String homeTeam, awayTeam;
  const _EventsList({required this.events, required this.homeTeam, required this.awayTeam});

  /// Géométrie de la ligne, partagée avec l'en-tête et le filet central de
  /// [_MatchEventsCard] : l'axe des deux camps est décalé par la colonne des
  /// minutes, le centrer « au milieu de la carte » le désaligne.
  static const double minuteWidth = 38;
  static const double iconWidth   = 24;

  /// Seuls les buts et les cartons sont affichés — les remplacements et autres
  /// événements alourdiraient la liste sans intérêt.
  static bool _isNotable(MatchEvent e) => e.type == 'Goal' || e.type == 'Card';

  /// Permet au parent de décider s'il doit afficher la carte, en appliquant
  /// exactement le même filtre que le rendu.
  static bool hasNotable(List<MatchEvent> events) => events.any(_isNotable);

  static Widget _eventIcon(MatchEvent e) {
    if (e.type == 'Goal') {
      if (e.detail == 'Own Goal') {
        return Stack(clipBehavior: Clip.none, children: [
          Icon(Icons.sports_soccer_rounded, color: AppColors.error, size: 16),
          Positioned(right: -4, bottom: -2,
            child: Icon(Icons.arrow_back_rounded, color: AppColors.error, size: 8)),
        ]);
      }
      if (e.detail == 'Penalty') {
        return Stack(clipBehavior: Clip.none, children: [
          Icon(Icons.sports_soccer_rounded, color: AppColors.success, size: 16),
          Positioned(right: -4, bottom: -2,
            child: Icon(Icons.gps_fixed_rounded, color: AppColors.warning, size: 8)),
        ]);
      }
      if (e.detail == 'Missed Penalty') {
        return Icon(Icons.sports_soccer_rounded,
          color: AppColors.error.withValues(alpha: 0.5), size: 16);
      }
      return Icon(Icons.sports_soccer_rounded, color: AppColors.success, size: 16);
    }
    if (e.type == 'Card') {
      final isRed = e.detail.contains('Red');
      return Container(
        width: 11, height: 15,
        decoration: BoxDecoration(
          color: isRed ? AppColors.error : AppColors.warning,
          borderRadius: BorderRadius.circular(2),
        ),
      );
    }
    if (e.type == 'subst') {
      return Icon(Icons.swap_horiz_rounded, color: AppColors.info, size: 16);
    }
    return const Icon(Icons.sports_soccer_rounded, color: Colors.grey, size: 16);
  }

  @override
  Widget build(BuildContext context) {
    final notable = events.where(_isNotable).toList();

    if (notable.isEmpty) {
      return Text('Aucun événement notable.',
        style: TextStyle(color: context.cl.textM, fontSize: 12));
    }

    return Column(
      children: notable.map((e) {
        final isHome = e.team == homeTeam;
        final minStr = e.extra != null ? "${e.minute}+${e.extra}'" : "${e.minute}'";

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            // Minute
            SizedBox(width: minuteWidth,
              child: Text(minStr,
                style: TextStyle(
                  color: AppColors.info, fontSize: 11,
                  fontWeight: FontWeight.w700))),
            // Gauche (domicile)
            Expanded(child: isHome
              ? _EventItem(event: e, align: TextAlign.right)
              : const SizedBox()),
            // Icône centrale — largeur fixe : les icônes n'ont pas toutes la
            // même taille (16px pour un but, 11px pour un carton) et sans
            // colonne fixe l'axe central se déplaçait d'une ligne à l'autre.
            SizedBox(
              width: iconWidth,
              child: Center(child: _eventIcon(e)),
            ),
            // Droite (extérieur)
            Expanded(child: !isHome
              ? _EventItem(event: e, align: TextAlign.left)
              : const SizedBox()),
          ]),
        );
      }).toList(),
    );
  }
}

class _EventItem extends StatelessWidget {
  final MatchEvent event;
  final TextAlign align;
  const _EventItem({required this.event, required this.align});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: align == TextAlign.right
      ? CrossAxisAlignment.end : CrossAxisAlignment.start,
    children: [
      Text(event.player,
        textAlign: align,
        style: TextStyle(color: context.cl.textP, fontSize: 12,
          fontWeight: FontWeight.w600),
        maxLines: 1, overflow: TextOverflow.ellipsis),
      if (event.assist != null && event.assist!.isNotEmpty)
        Text('↳ ${event.assist}',
          textAlign: align,
          style: TextStyle(color: context.cl.textM, fontSize: 10),
          maxLines: 1, overflow: TextOverflow.ellipsis),
    ],
  );
}

class _StatsList extends StatelessWidget {
  final List<MatchStat> stats;
  final String homeTeam, awayTeam;
  const _StatsList({required this.stats, required this.homeTeam, required this.awayTeam});

  static const _wantedStats = [
    'Ball Possession',
    'Total Shots',
    'Shots on Goal',
    'Shots off Goal',
    'Blocked Shots',
    'Corner Kicks',
    'Fouls',
    'Yellow Cards',
    'Red Cards',
    'Offsides',
    'Total passes',
    'Passes accurate',
    'Goalkeeper Saves',
  ];

  static const _frenchLabels = {
    'Ball Possession':   'Possession',
    'Total Shots':       'Tirs (total)',
    'Shots on Goal':     'Tirs cadrés',
    'Shots off Goal':    'Tirs hors cadre',
    'Blocked Shots':     'Tirs bloqués',
    'Corner Kicks':      'Corners',
    'Fouls':             'Fautes',
    'Yellow Cards':      'Cartons jaunes',
    'Red Cards':         'Cartons rouges',
    'Offsides':          'Hors-jeu',
    'Total passes':      'Passes (total)',
    'Passes accurate':   'Passes réussies',
    'Goalkeeper Saves':  'Arrêts du gardien',
  };

  @override
  Widget build(BuildContext context) {
    final filtered = stats
      .where((s) => _wantedStats.contains(s.label))
      .toList()
      ..sort((a, b) =>
        _wantedStats.indexOf(a.label).compareTo(_wantedStats.indexOf(b.label)));

    if (filtered.isEmpty) {
      return Text('Statistiques indisponibles.',
        style: TextStyle(color: context.cl.textM, fontSize: 12));
    }

    // La possession sert d'en-tête visuel : c'est la seule stat qui se lit
    // naturellement comme un partage à 100 %, les autres sont des compteurs.
    final possession = filtered
      .where((s) => s.label == 'Ball Possession').firstOrNull;
    final others = filtered.where((s) => s.label != 'Ball Possession');

    return Column(children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(children: [
          Expanded(child: Text(homeTeam,
            style: TextStyle(color: AppColors.primary, fontSize: 11,
              fontWeight: FontWeight.w700),
            maxLines: 1, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 12),
          Expanded(child: Text(awayTeam,
            style: TextStyle(color: AppColors.warning, fontSize: 11,
              fontWeight: FontWeight.w700),
            textAlign: TextAlign.right,
            maxLines: 1, overflow: TextOverflow.ellipsis)),
        ]),
      ),
      if (possession != null) ...[
        Text('Possession de balle',
          style: TextStyle(color: context.cl.textS, fontSize: 11.5)),
        const SizedBox(height: 8),
        _PossessionBar(home: possession.home, away: possession.away),
        const SizedBox(height: 14),
      ],
      ...others.map((s) => _StatRow(
        label: _frenchLabels[s.label] ?? s.label,
        home: s.home, away: s.away,
        lowerIsBetter: _lowerIsBetter.contains(s.label),
      )),
    ]);
  }

  /// Stats où le plus petit chiffre est le meilleur — la pastille doit alors
  /// mettre en avant l'équipe qui en a le moins.
  static const _lowerIsBetter = {
    'Fouls', 'Yellow Cards', 'Red Cards', 'Offsides',
  };
}

/// Barre de possession pleine largeur, chaque camp portant son pourcentage.
class _PossessionBar extends StatelessWidget {
  final dynamic home, away;
  const _PossessionBar({this.home, this.away});

  @override
  Widget build(BuildContext context) {
    final h = _statValue(home), a = _statValue(away);
    final total = h + a;
    final hRatio = total > 0 ? h / total : 0.5;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.5, end: hRatio),
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeOutCubic,
      builder: (context, val, child) => ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          height: 30,
          child: Row(children: [
            Expanded(
              flex: (val * 1000).round().clamp(1, 999),
              child: Container(
                color: AppColors.primary,
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('${home ?? 0}',
                    style: const TextStyle(
                      color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800)),
                ),
              ),
            ),
            Expanded(
              flex: ((1 - val) * 1000).round().clamp(1, 999),
              child: Container(
                color: AppColors.warning,
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('${away ?? 0}',
                    style: const TextStyle(
                      color: Colors.black, fontSize: 13, fontWeight: FontWeight.w800)),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Une ligne « valeur — libellé — valeur ». Seule l'équipe en tête reçoit une
/// pastille colorée : le regard trouve le vainqueur de la stat sans avoir à
/// comparer deux nombres.
class _StatRow extends StatelessWidget {
  final String label;
  final dynamic home, away;
  final bool lowerIsBetter;
  const _StatRow({
    required this.label,
    this.home,
    this.away,
    this.lowerIsBetter = false,
  });

  @override
  Widget build(BuildContext context) {
    final h = _statValue(home), a = _statValue(away);
    final homeLeads = h != a && (lowerIsBetter ? h < a : h > a);
    final awayLeads = h != a && (lowerIsBetter ? a < h : a > h);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        SizedBox(
          width: 54,
          child: Align(
            alignment: Alignment.centerLeft,
            child: _value(context, home, AppColors.primary, homeLeads, Colors.white),
          ),
        ),
        Expanded(
          child: Text(label,
            textAlign: TextAlign.center,
            style: TextStyle(color: context.cl.textS, fontSize: 11.5, height: 1.3)),
        ),
        SizedBox(
          width: 54,
          child: Align(
            alignment: Alignment.centerRight,
            child: _value(context, away, AppColors.warning, awayLeads, Colors.black),
          ),
        ),
      ]),
    );
  }

  Widget _value(BuildContext context, dynamic v, Color color, bool leads, Color onColor) {
    final text = Text('${v ?? 0}',
      style: TextStyle(
        color: leads ? onColor : context.cl.textP,
        fontSize: 12.5,
        fontWeight: FontWeight.w700));

    if (!leads) return text;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(11)),
      child: text,
    );
  }
}

/// Les valeurs d'API-Football arrivent en `int`, ou en `String` pour les
/// pourcentages ("76%"), ou `null` quand la stat n'est pas fournie.
double _statValue(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString().replaceAll('%', '').trim()) ?? 0;
}

class _StatsLoading extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Column(
    children: List.generate(4, (_) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        height: 20,
        decoration: BoxDecoration(
          color: context.cl.surfaceD,
          borderRadius: BorderRadius.circular(6)),
      ).animate(onPlay: (c) {
        if (!context.animationsReduites) c.repeat();
      }).shimmer(duration: 1400.ms, color: context.cl.borderSoft),
    )),
  );
}

class _StatsUnavailable extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      Icon(Icons.info_outline_rounded, color: context.cl.textM, size: 15),
      const SizedBox(width: 8),
      Expanded(child: Text(
        'Statistiques indisponibles pour ce match.',
        style: TextStyle(color: context.cl.textM, fontSize: 12))),
    ]),
  );
}

// ─────────────────────────────────────────────────────────────────────────────

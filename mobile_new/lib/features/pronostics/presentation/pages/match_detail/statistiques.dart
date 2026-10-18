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
              color: context.cl.info.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.bar_chart_rounded, color: context.cl.info, size: 16),
          ),
          const SizedBox(width: 10),
          Text(tr(context, "Statistiques du match"),
            style: TextStyle(
              color: context.cl.textP,
              fontSize: 13,
              fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 14),
        if (statsAsync.valueOrNull != null) ...[
          _FraicheurDonnees(updatedAt: statsAsync.valueOrNull!.updatedAt,
            stale: statsAsync.hasError || statsAsync.valueOrNull!.stale),
          const SizedBox(height: 12),
          if (statsAsync.valueOrNull!.stats.isEmpty)
            Text(tr(context, statsAsync.valueOrNull!.statsStatus == 'unsupported'
              ? "Les statistiques ne sont pas couvertes pour cette compétition."
              : statsAsync.valueOrNull!.statsStatus == 'unavailable'
                ? "Statistiques momentanément indisponibles."
                : "Les statistiques ne sont pas encore publiées pour ce match."),
              style: TextStyle(color: context.cl.textS))
          else _StatsParPeriode(data: statsAsync.valueOrNull!),
        ] else statsAsync.when(
          loading: () => _StatsLoading(),
          error: (_, _) => Column(children: [
            _StatsUnavailable(),
            TextButton(onPressed: () => ref.invalidate(matchStatsProvider(matchId)),
              child: Text(tr(context, "Réessayer"))),
          ]),
          data: (data) => data == null
            ? _StatsUnavailable()
            : _StatsList(stats: data.stats,
                homeTeam: data.homeTeam, awayTeam: data.awayTeam),
        ),
      ]),
    );
  }
}

/// Faits marquants du match — buts, cartons, remplacements, VAR — en fil au
/// style Sofascore (`fil_evenements.dart`), dans l'onglet Détails, séparément
/// des statistiques chiffrées qui ont leur propre onglet.
class _MatchEventsCard extends ConsumerWidget {
  final String matchId;
  final MatchEntity match;
  const _MatchEventsCard({required this.matchId, required this.match});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(matchStatsProvider(matchId));
    final data = statsAsync.valueOrNull;
    final enDirect = match.status == MatchStatus.live;
    final info = ref.watch(matchInfoProvider(matchId)).valueOrNull;
    final live = enDirect ? ref.watch(liveScoreProvider(matchId)).valueOrNull : null;
    // Score actuel (direct) ou final, hors tirs au but : les scores au fil des
    // buts doivent y aboutir pour être affichés.
    final score = (dom: live?.homeScore ?? match.homeScore, ext: live?.awayScore ?? match.awayScore);
    if (data == null) {
      return Padding(padding: const EdgeInsets.all(16),
        child: Text(tr(context, statsAsync.hasError
          ? "Événements momentanément indisponibles."
          : statsAsync.isLoading ? "Chargement des événements…" : "Événements non fournis pour ce match."),
          style: TextStyle(color: context.cl.textS)));
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
          color: context.cl.info,
          title: tr(context, "Faits marquants")),
        const SizedBox(height: 14),
        _FraicheurDonnees(updatedAt: data.updatedAt,
          stale: statsAsync.hasError || data.stale),
        const SizedBox(height: 12),
        if (data.events.isEmpty && (data.eventsStatus == 'unsupported' || data.eventsStatus == 'unavailable'))
          Text(tr(context, data.eventsStatus == 'unsupported'
            ? "Les événements ne sont pas couverts pour cette compétition."
            : "Événements momentanément indisponibles."), style: TextStyle(color: context.cl.textS))
        else if (!data.events.any((e) => const {'Goal', 'Card', 'subst', 'Var'}.contains(e.type)))
          Text(tr(context, "Aucun événement reçu pour le moment."),
            style: TextStyle(color: context.cl.textM, fontSize: 12))
        else
          FilEvenements(lignes: construireFil(
            data.events,
            domicile: data.homeTeam,
            termine: match.status == MatchStatus.finished,
            periodeAtteinte: _periodeAtteinte(info?.phase),
            scoreFinal: score.dom != null && score.ext != null
                ? (dom: score.dom!, ext: score.ext!) : null,
          )),
      ]),
    );
  }

  /// Période la plus avancée d'après la phase publiée (1 à 4).
  static int _periodeAtteinte(String? phase) => switch (phase?.toUpperCase()) {
    '2H' || 'FT' => 2,
    'BT' || 'ET' || 'AET' => 3,
    'P' || 'PEN' => 4,
    _ => 1,
  };
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

/// Statistiques du match, avec « Tout / 1re MT / 2e MT » comme Sofascore
/// quand le serveur fournit des mi-temps cohérentes avec le total.
class _StatsParPeriode extends StatefulWidget {
  final MatchStatsData data;
  const _StatsParPeriode({required this.data});

  @override
  State<_StatsParPeriode> createState() => _StatsParPeriodeState();
}

class _StatsParPeriodeState extends State<_StatsParPeriode> {
  int _periode = 0; // 0 = tout, 1 = 1re mi-temps, 2 = 2e mi-temps

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final m1 = d.statsPremiereMiTemps, m2 = d.statsSecondeMiTemps;
    final parMiTemps = m1 != null && m2 != null && m1.isNotEmpty && m2.isNotEmpty;
    final periode = parMiTemps ? _periode : 0;
    final stats = switch (periode) { 1 => m1!, 2 => m2!, _ => d.stats };
    return Column(children: [
      if (parMiTemps) ...[
        Container(
          key: const Key('stats-periodes'),
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: context.cl.surfaceDeep,
            borderRadius: BorderRadius.circular(22)),
          child: Row(children: [
            for (final (i, libelle) in [(0, tr(context, "Tout")), (1, tr(context, "1re MT")), (2, tr(context, "2e MT"))])
              Expanded(child: Semantics(
                selected: periode == i, button: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _periode = i);
                  },
                  child: AnimatedContainer(
                    duration: context.duree(const Duration(milliseconds: 180)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: periode == i ? context.cl.textP : Colors.transparent,
                      borderRadius: BorderRadius.circular(19)),
                    alignment: Alignment.center,
                    child: Text(libelle, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: periode == i ? context.cl.bg : context.cl.textS,
                        fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
                ),
              )),
          ]),
        ),
        const SizedBox(height: 14),
      ],
      _StatsList(stats: stats, homeTeam: d.homeTeam, awayTeam: d.awayTeam),
    ]);
  }
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
      return Text(tr(context, "Statistiques indisponibles."),
        style: TextStyle(color: context.cl.textM, fontSize: 12));
    }

    // La possession sert d'en-tête visuel : c'est la seule stat qui se lit
    // naturellement comme un partage à 100 %, les autres sont des compteurs.
    final possession = filtered
      .where((s) => s.label == 'Ball Possession' && s.home != null && s.away != null).firstOrNull;
    final others = filtered.where((s) => s != possession);

    return Column(children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(children: [
          Expanded(child: Text(homeTeam,
            style: TextStyle(color: context.cl.accent, fontSize: 11,
              fontWeight: FontWeight.w700),
            maxLines: 1, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 12),
          Expanded(child: Text(awayTeam,
            style: TextStyle(color: context.cl.warning, fontSize: 11,
              fontWeight: FontWeight.w700),
            textAlign: TextAlign.right,
            maxLines: 1, overflow: TextOverflow.ellipsis)),
        ]),
      ),
      if (possession != null) ...[
        Text(tr(context, "Possession de balle"),
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
                color: AppColors.primaryBouton,
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('${home ?? 0}',
                    style: const TextStyle(
                      color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
                ),
              ),
            ),
            Expanded(
              flex: ((1 - val) * 1000).round().clamp(1, 999),
              child: Container(
                color: context.cl.warning,
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('${away ?? 0}',
                    style: const TextStyle(
                      color: Colors.black, fontSize: 13, fontWeight: FontWeight.w700)),
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
    final homeLeads = home != null && away != null && h != a && (lowerIsBetter ? h < a : h > a);
    final awayLeads = home != null && away != null && h != a && (lowerIsBetter ? a < h : a > h);

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
          child: Text(tr(context, label),
            textAlign: TextAlign.center,
            style: TextStyle(color: context.cl.textS, fontSize: 11.5, height: 1.3)),
        ),
        SizedBox(
          width: 54,
          child: Align(
            alignment: Alignment.centerRight,
            child: _value(context, away, context.cl.warning, awayLeads, Colors.black),
          ),
        ),
      ]),
    );
  }

  Widget _value(BuildContext context, dynamic v, Color color, bool leads, Color onColor) {
    final text = Text('${v ?? '—'}',
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
        tr(context, "Statistiques indisponibles pour ce match."),
        style: TextStyle(color: context.cl.textM, fontSize: 12))),
    ]),
  );
}

// ─────────────────────────────────────────────────────────────────────────────

/// Avertit quand le relevé du fournisseur est interrompu — et seulement alors.
///
/// La fiche affichait aussi « Actualisé à 21:04 » sous chaque bloc : l'heure
/// d'un relevé n'est pas une information sur le match, et Sofascore n'en
/// montre aucune (demande du 18 octobre 2026). Une donnée périmée, elle, doit
/// se signaler.
class _FraicheurDonnees extends StatelessWidget {
  final DateTime? updatedAt;
  final bool stale;
  const _FraicheurDonnees({this.updatedAt, required this.stale});
  @override
  Widget build(BuildContext context) {
    if (!stale) return const SizedBox.shrink();
    return Text(tr(context, "Actualisation interrompue · dernières données reçues"),
      style: TextStyle(color: context.cl.warning, fontSize: 11));
  }
}

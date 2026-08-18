// Confrontations directes — extrait de match_detail_page.dart.
//
// `part` et non un fichier autonome : toutes ces classes sont privées à
// la bibliothèque (préfixe `_`) et le resteront. Un import classique aurait
// imposé de les rendre publiques, donc visibles depuis n'importe où.
part of '../match_detail_page.dart';

class _H2HCard extends ConsumerWidget {
  final String matchId;
  /// Logos du match courant — les confrontations passées opposent les mêmes
  /// deux équipes, on les réutilise donc pour illustrer chaque ligne.
  final String? homeLogo;
  final String? awayLogo;
  const _H2HCard({required this.matchId, this.homeLogo, this.awayLogo});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final h2hAsync = ref.watch(h2hProvider(matchId));
    final status = _statusOf(h2hAsync.error);

    // Pas de données, ou vraie erreur → on n'affiche rien
    if (status == null && h2hAsync.valueOrNull?.matches.isEmpty == true) return const SizedBox.shrink();
    if (h2hAsync.hasError && status != 401) return const SizedBox.shrink();

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
            child: Icon(Icons.history_rounded, color: AppColors.primary, size: 16),
          ),
          const SizedBox(width: 10),
          Text('Confrontations directes',
            style: TextStyle(
              color: context.cl.textP,
              fontSize: 13,
              fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 14),
        status == 401
          ? const _CardLoginPrompt(message: 'Connecte-toi pour voir les confrontations directes.')
          : h2hAsync.when(
              loading: () => _H2HLoading(),
              error: (_, __) => const SizedBox.shrink(),
              data: (h2h) => _H2HContent(
                h2h: h2h, homeLogo: homeLogo, awayLogo: awayLogo),
            ),
      ]),
    );
  }
}

class _H2HContent extends StatelessWidget {
  final H2HData h2h;
  final String? homeLogo;
  final String? awayLogo;
  const _H2HContent({required this.h2h, this.homeLogo, this.awayLogo});

  @override
  Widget build(BuildContext context) {
    final total = h2h.homeWins + h2h.awayWins + h2h.draws;
    final homeRatio = total > 0 ? h2h.homeWins / total : 0.0;
    final drawRatio = total > 0 ? h2h.draws     / total : 0.0;
    final awayRatio = total > 0 ? h2h.awayWins  / total : 0.0;

    return Column(children: [
      // Barre de résumé
      Row(children: [
        // Home wins
        Expanded(
          child: Column(children: [
            TweenAnimationBuilder<int>(
              tween: IntTween(begin: 0, end: h2h.homeWins),
              duration: const Duration(milliseconds: 800),
              builder: (_, v, __) => Text('$v',
                style: TextStyle(
                  color: AppColors.success,
                  fontSize: 24, fontWeight: FontWeight.w900)),
            ),
            Text(h2h.homeTeam,
              textAlign: TextAlign.center,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: context.cl.textS, fontSize: 10)),
          ]),
        ),
        // Draws
        Column(children: [
          TweenAnimationBuilder<int>(
            tween: IntTween(begin: 0, end: h2h.draws),
            duration: const Duration(milliseconds: 800),
            builder: (_, v, __) => Text('$v',
              style: TextStyle(
                color: context.cl.textM,
                fontSize: 24, fontWeight: FontWeight.w900)),
          ),
          Text('Nuls',
            style: TextStyle(color: context.cl.textM, fontSize: 10)),
        ]),
        // Away wins
        Expanded(
          child: Column(children: [
            TweenAnimationBuilder<int>(
              tween: IntTween(begin: 0, end: h2h.awayWins),
              duration: const Duration(milliseconds: 800),
              builder: (_, v, __) => Text('$v',
                style: TextStyle(
                  color: AppColors.error,
                  fontSize: 24, fontWeight: FontWeight.w900)),
            ),
            Text(h2h.awayTeam,
              textAlign: TextAlign.center,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: context.cl.textS, fontSize: 10)),
          ]),
        ),
      ]),
      const SizedBox(height: 12),
      // Barre proportionnelle
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 900),
          curve: Curves.easeOutCubic,
          builder: (_, t, __) => Row(children: [
            if (homeRatio > 0) Expanded(
              flex: (homeRatio * 100).round(),
              child: Container(
                height: 8,
                color: AppColors.success.withValues(alpha: 0.7 + 0.3 * t)),
            ),
            if (drawRatio > 0) Expanded(
              flex: (drawRatio * 100).round(),
              child: Container(height: 8, color: context.cl.borderSoft),
            ),
            if (awayRatio > 0) Expanded(
              flex: (awayRatio * 100).round(),
              child: Container(
                height: 8,
                color: AppColors.error.withValues(alpha: 0.7 + 0.3 * t)),
            ),
          ]),
        ),
      ),
      const SizedBox(height: 6),
      // Liste des derniers matchs
      ...() {
        final shown = h2h.matches.take(6).toList();
        return [
          for (var i = 0; i < shown.length; i++)
            _H2HRow(
              match: shown[i],
              h2h: h2h,
              homeLogo: homeLogo,
              awayLogo: awayLogo,
              showDivider: i < shown.length - 1,
            ),
        ];
      }(),
    ]);
  }
}

class _H2HRow extends StatelessWidget {
  final H2HMatchResult match;
  final H2HData        h2h;
  final String? homeLogo;
  final String? awayLogo;
  final bool showDivider;
  const _H2HRow({
    required this.match,
    required this.h2h,
    this.homeLogo,
    this.awayLogo,
    this.showDivider = true,
  });

  /// L'hôte change d'une confrontation à l'autre : on rattache le logo au nom
  /// de l'équipe, jamais à sa position dans la ligne.
  String? _logoFor(String team) => team == h2h.homeTeam ? homeLogo : awayLogo;

  /// Le vainqueur est déduit du score de la ligne, et non du champ `winner` de
  /// l'API : celui-ci est exprimé par rapport au domicile du *match courant*
  /// (cf. api_football.service.ts), donc le lire comme l'hôte de cette
  /// rencontre-là inverse la couleur dès que l'hôte a changé.
  ///
  /// La couleur suit ensuite l'équipe (vert = équipe à domicile du match
  /// courant, rouge = son adversaire), pour rester cohérente avec la barre de
  /// synthèse au-dessus quel que soit le terrain de la rencontre.
  Color? _colorFor(String team) {
    if (match.homeScore == match.awayScore) return null;
    final winner = match.homeScore > match.awayScore
      ? match.homeTeam
      : match.awayTeam;
    if (team != winner) return null;
    return team == h2h.homeTeam ? AppColors.success : AppColors.error;
  }

  Widget _teamSide(BuildContext context, String team, {required bool alignEnd}) {
    final color = _colorFor(team);
    final logo  = _TeamLogo(url: _logoFor(team) ?? '', size: 18);
    final name  = Flexible(
      child: Text(team,
        textAlign: alignEnd ? TextAlign.right : TextAlign.left,
        maxLines: 1, overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color ?? context.cl.textS,
          fontSize: 12,
          fontWeight: color != null ? FontWeight.w700 : FontWeight.w400)),
    );

    return Expanded(
      child: Row(
        mainAxisAlignment: alignEnd ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: alignEnd
          ? [name, const SizedBox(width: 7), logo]
          : [logo, const SizedBox(width: 7), name],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Column(children: [
    Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Column(children: [
        Row(children: [
          Text(DateFormat('EEE d MMM y', 'fr_FR').format(match.date),
            style: TextStyle(color: context.cl.textM, fontSize: 10.5)),
          const Spacer(),
          if (match.league.isNotEmpty)
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: context.cl.surfaceDeep,
                  borderRadius: BorderRadius.circular(5)),
                child: Text(match.league.toUpperCase(),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.cl.textM,
                    fontSize: 8.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4)),
              ),
            ),
        ]),
        const SizedBox(height: 9),
        Row(children: [
          _teamSide(context, match.homeTeam, alignEnd: true),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text('${match.homeScore} - ${match.awayScore}',
              style: TextStyle(
                color: context.cl.textP,
                fontSize: 14, fontWeight: FontWeight.w800)),
          ),
          _teamSide(context, match.awayTeam, alignEnd: false),
        ]),
      ]),
    ),
    if (showDivider) Container(height: 1, color: context.cl.borderSoft),
  ]);
}

class _H2HLoading extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Column(
    children: List.generate(3, (_) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        height: 24,
        decoration: BoxDecoration(
          color: context.cl.surfaceD,
          borderRadius: BorderRadius.circular(6)),
      ).animate(onPlay: (c) {
        if (!context.animationsReduites) c.repeat();
      }).shimmer(duration: 1400.ms, color: context.cl.borderSoft),
    )),
  );
}

// ─── ANALYSE IA ──────────────────────────────────────────────────────────────

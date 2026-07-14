import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/team_logo_widget.dart';
import '../../domain/entities/match_entity.dart';
import '../providers/favorites_provider.dart';
import '../../../bankroll/presentation/providers/bankroll_provider.dart';
import '../../../../shared/widgets/premium_gate_sheet.dart';

class MatchCardWidget extends ConsumerStatefulWidget {
  final MatchEntity match;
  final bool isPremiumUser;
  final bool showDate;

  const MatchCardWidget({
    super.key,
    required this.match,
    this.isPremiumUser = false,
    this.showDate = false,
  });

  @override
  ConsumerState<MatchCardWidget> createState() => _MatchCardWidgetState();
}

class _MatchCardWidgetState extends ConsumerState<MatchCardWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _pressCtrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _pressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 90),
      reverseDuration: const Duration(milliseconds: 160),
      lowerBound: 0, upperBound: 1,
    );
    _scale = Tween<double>(begin: 1.0, end: 0.97).animate(
      CurvedAnimation(parent: _pressCtrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _pressCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locked  = widget.match.isPremium && !widget.isPremiumUser;
    final noProno = !widget.match.hasPronostic;

    final m = widget.match;
    final semanticLabel = locked
        ? '${m.homeTeam} contre ${m.awayTeam}, ${m.league}. Contenu premium verrouillé.'
        : noProno
            ? '${m.homeTeam} contre ${m.awayTeam}, ${m.league}. Pas de pronostic disponible.'
            : '${m.homeTeam} contre ${m.awayTeam}, ${m.league}. '
              'Pronostic : ${m.predictionLabel}. '
              'Confiance ${m.confidenceScore} sur 5. '
              'Cote recommandée ${m.oddsRecommended.toStringAsFixed(2)}.';

    // Matchs terminés sans pronostic → navigable pour voir les stats
    final canNavigate = !noProno || widget.match.status == MatchStatus.finished;

    return Semantics(
      label:  semanticLabel,
      button: canNavigate,
      child: GestureDetector(
      onTapDown: canNavigate ? (_) => _pressCtrl.forward() : null,
      onTapUp: canNavigate ? (_) {
        _pressCtrl.reverse();
        HapticFeedback.lightImpact();
        if (locked) {
          showPremiumGateSheet(context,
            matchLabel: '${widget.match.homeTeam} vs ${widget.match.awayTeam}');
        } else {
          context.push('/pronostics/${widget.match.id}', extra: widget.match);
        }
      } : null,
      onTapCancel: () => _pressCtrl.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: context.cl.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: widget.match.status == MatchStatus.live
                ? AppColors.error.withValues(alpha: 0.4)
                : noProno
                    ? context.cl.border
                    : locked
                        ? context.cl.border
                        : AppColors.primary.withValues(alpha: 0.25),
            width: widget.match.status == MatchStatus.live ? 1.5 : 0.5,
          ),
          boxShadow: widget.match.status == MatchStatus.live
              ? [
                  BoxShadow(
                    color: AppColors.error.withValues(alpha: 0.12),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  )
                ]
              : [],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: ExcludeSemantics(
            child: Column(
              children: [
                _buildHeader(context),
                noProno
                  ? _buildNoPronosticContent(context)
                  : locked
                      ? _buildLockedContent(context)
                      : _buildContent(context),
              ],
            ),
          ),
        ),
      ),
    )));
  }

  // ─── HEADER ────────────────────────────────────────────────────────────────
  Widget _buildHeader(BuildContext context) {
    final isFav   = ref.watch(favoritesProvider).matchIds.contains(widget.match.id);
    final hasBet  = ref.watch(betMatchIdsProvider).contains(widget.match.id);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 0),
      child: Row(
        children: [
          // Badge ligue
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: context.cl.surfaceDeep,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.sports_soccer_rounded,
                    color: AppColors.primaryLight, size: 12),
                const SizedBox(width: 5),
                Text(
                  widget.match.league,
                  style: TextStyle(color: context.cl.textS, fontSize: 11),
                ),
              ],
            ),
          ),
          if (widget.showDate) ...[
            const SizedBox(width: 6),
            Text(
              DateFormat('dd/MM', 'fr_FR').format(widget.match.matchDate),
              style: TextStyle(color: context.cl.textM, fontSize: 10),
            ),
          ],
          if (hasBet) ...[
            const SizedBox(width: 6),
            _BetBadge(),
          ],
          const Spacer(),
          // Bouton favoris
          Semantics(
            label:  isFav ? 'Retirer des favoris' : 'Ajouter aux favoris',
            button: true,
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                ref.read(favoritesProvider.notifier).toggleMatch(widget.match.id);
              },
              child: ExcludeSemantics(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    isFav ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                    key: ValueKey(isFav),
                    size: 18,
                    color: isFav ? AppColors.primary : context.cl.textM,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Badge premium VIP
          if (widget.match.isPremium) const _VipBadge(),
          if (widget.match.isPremium) const SizedBox(width: 8),
          // Heure / Statut LIVE
          widget.match.status == MatchStatus.live
              ? const _LivePulse()
              : widget.match.status == MatchStatus.finished
                  ? _ResultBadge(match: widget.match)
                  : Text(
                      DateFormat('HH:mm').format(widget.match.matchDate),
                      style: const TextStyle(
                          color: AppColors.primaryLight,
                          fontSize: 12,
                          fontWeight: FontWeight.w600),
                    ),
        ],
      ),
    );
  }

  // ─── CONTENU NORMAL ────────────────────────────────────────────────────────
  Widget _buildContent(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        children: [
          // Équipes + Score/VS
          Row(
            children: [
              Expanded(
                child: _TeamColumn(
                  name: widget.match.homeTeam,
                  logo: widget.match.homeTeamLogo,
                  isHome: true,
                  isWinner: widget.match.status == MatchStatus.finished &&
                      (widget.match.homeScore ?? 0) > (widget.match.awayScore ?? 0),
                ),
              ),
              _ScoreCenter(match: widget.match),
              Expanded(
                child: _TeamColumn(
                  name: widget.match.awayTeam,
                  logo: widget.match.awayTeamLogo,
                  isHome: false,
                  isWinner: widget.match.status == MatchStatus.finished &&
                      (widget.match.awayScore ?? 0) > (widget.match.homeScore ?? 0),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Ligne 1 : Pronostic + Confiance
          Row(children: [
            // Badge pronostic
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [
                    AppColors.primary.withValues(alpha: 0.15),
                    AppColors.primaryLight.withValues(alpha: 0.08),
                  ]),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.35), width: 0.5)),
                child: Text(
                  widget.match.predictionLabel,
                  style: const TextStyle(
                    color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w700),
                  textAlign: TextAlign.center,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
            const SizedBox(width: 10),
            // Score confiance (jauge)
            _ConfidenceBar(score: widget.match.confidenceScore),
          ]),

          const SizedBox(height: 8),

          // Ligne 2 : Cotes H / N / A
          _OddsRow(match: widget.match),
        ],
      ),
    );
  }

  // ─── CONTENU VERROUILLÉ ────────────────────────────────────────────────────
  Widget _buildLockedContent(BuildContext context) {
    return Stack(
      children: [
        // Contenu flouté en arrière-plan
        _buildContentBlurred(context),
        // Overlay glassmorphism
        Positioned.fill(
          child: ClipRRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
              child: Container(
                color: context.cl.surface.withValues(alpha: 0.7),
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppColors.primaryLight.withValues(alpha: 0.25),
                            AppColors.primary.withValues(alpha: 0.15),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.lock_rounded,
                          color: AppColors.primaryLight, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Pronostic VIP',
                              style: TextStyle(
                                  color: context.cl.textP,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text('Réservé aux membres Premium',
                              style: TextStyle(
                                  color: context.cl.textS,
                                  fontSize: 11)),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () => showPremiumGateSheet(context,
                        matchLabel: '${widget.match.homeTeam} vs ${widget.match.awayTeam}'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [
                            AppColors.primary,
                            AppColors.primaryLight
                          ]),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.4),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: const Text('Premium',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ─── PAS DE PRONOSTIC ──────────────────────────────────────────────────────
  Widget _buildNoPronosticContent(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(children: [
        // Équipes
        Row(children: [
          Expanded(child: _TeamColumn(
            name: widget.match.homeTeam,
            logo: widget.match.homeTeamLogo,
            isHome: true)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text('VS',
              style: TextStyle(
                color: context.cl.textM,
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 1))),
          Expanded(child: _TeamColumn(
            name: widget.match.awayTeam,
            logo: widget.match.awayTeamLogo,
            isHome: false)),
        ]),
        const SizedBox(height: 12),
        if (widget.match.status == MatchStatus.finished &&
            widget.match.homeScore != null &&
            widget.match.awayScore != null)
          // Score final
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: context.cl.surfaceD,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.cl.border, width: 0.5)),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('Score final',
                style: TextStyle(
                  color: context.cl.textM, fontSize: 11)),
              const SizedBox(width: 10),
              Text(
                '${widget.match.homeScore} - ${widget.match.awayScore}',
                style: TextStyle(
                  color: context.cl.textP,
                  fontSize: 18, fontWeight: FontWeight.w900,
                  letterSpacing: 1)),
            ]),
          )
        else if (widget.match.status != MatchStatus.finished)
          // Bandeau "Analyse en cours" (uniquement pour matchs non terminés)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: context.cl.surfaceD,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.cl.border, width: 0.5)),
            child: Row(children: [
              Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  color: context.cl.surface,
                  borderRadius: BorderRadius.circular(8)),
                child: Icon(Icons.hourglass_top_rounded,
                  color: context.cl.textM, size: 14)),
              const SizedBox(width: 10),
              Text('Analyse en cours...',
                style: TextStyle(
                  color: context.cl.textM,
                  fontSize: 12,
                  fontWeight: FontWeight.w500)),
            ]),
          ),
      ]),
    );
  }

  // Version floue du contenu pour l'arrière-plan du lock
  Widget _buildContentBlurred(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                  child: _TeamColumn(
                      name: widget.match.homeTeam,
                      logo: widget.match.homeTeamLogo,
                      isHome: true)),
              const _ScorePlaceholder(),
              Expanded(
                  child: _TeamColumn(
                      name: widget.match.awayTeam,
                      logo: widget.match.awayTeamLogo,
                      isHome: false)),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            height: 32,
            decoration: BoxDecoration(
              color: context.cl.surfaceDeep,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── LIVE PULSANT ─────────────────────────────────────────────────────────────
class _LivePulse extends StatefulWidget {
  const _LivePulse();
  @override
  State<_LivePulse> createState() => _LivePulseState();
}

class _LivePulseState extends State<_LivePulse>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.4), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _pulse,
            builder: (_, _) => Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: _pulse.value),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.error.withValues(alpha: _pulse.value * 0.6),
                    blurRadius: 4,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 5),
          const Text('LIVE',
              style: TextStyle(
                  color: AppColors.error,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5)),
        ],
      ),
    );
  }
}

// ─── BADGE VIP SHIMMER ────────────────────────────────────────────────────────
class _VipBadge extends StatefulWidget {
  const _VipBadge();
  @override
  State<_VipBadge> createState() => _VipBadgeState();
}

class _VipBadgeState extends State<_VipBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _shimmer;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
    _shimmer = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _shimmer,
      builder: (_, _) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment(_shimmer.value - 1, 0),
            end: Alignment(_shimmer.value, 0),
            colors: const [
              Color(0xFFB8860B),
              Color(0xFFFFD700),
              Color(0xFFDAA520),
              Color(0xFFFFD700),
              Color(0xFFB8860B),
            ],
            stops: const [0.0, 0.3, 0.5, 0.7, 1.0],
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.workspace_premium_rounded,
                color: Colors.white, size: 10),
            SizedBox(width: 3),
            Text('VIP',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5)),
          ],
        ),
      ),
    );
  }
}

// ─── COTES H / N / A ─────────────────────────────────────────────────────────
class _OddsRow extends StatelessWidget {
  final MatchEntity match;
  const _OddsRow({required this.match});

  bool get _hasOdds =>
    match.oddsHome > 0 || match.oddsDraw > 0 || match.oddsAway > 0;

  /// Détermine quelle cote est la recommandée pour la mettre en évidence
  _OddsHighlight get _highlight {
    return switch (match.predictionType) {
      PredictionType.win1    => _OddsHighlight.home,
      PredictionType.draw    => _OddsHighlight.draw,
      PredictionType.win2    => _OddsHighlight.away,
      _                      => _OddsHighlight.none,
    };
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasOdds) return const SizedBox.shrink();
    final h = _highlight;
    return Row(children: [
      _OddsCell(label: '1', value: match.oddsHome,
        highlighted: h == _OddsHighlight.home, context: context),
      const SizedBox(width: 6),
      _OddsCell(label: 'N', value: match.oddsDraw,
        highlighted: h == _OddsHighlight.draw, context: context),
      const SizedBox(width: 6),
      _OddsCell(label: '2', value: match.oddsAway,
        highlighted: h == _OddsHighlight.away, context: context),
    ]);
  }
}

enum _OddsHighlight { home, draw, away, none }

class _OddsCell extends StatelessWidget {
  final String label;
  final double value;
  final bool highlighted;
  final BuildContext context;
  const _OddsCell({
    required this.label,
    required this.value,
    required this.highlighted,
    required this.context,
  });

  @override
  Widget build(BuildContext _) {
    final color = highlighted ? AppColors.success : context.cl.textM;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          color: highlighted
            ? AppColors.success.withValues(alpha: 0.10)
            : context.cl.surfaceD,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: highlighted
              ? AppColors.success.withValues(alpha: 0.4)
              : context.cl.border,
            width: highlighted ? 0.8 : 0.5),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: TextStyle(
            color: color.withValues(alpha: 0.7),
            fontSize: 9, fontWeight: FontWeight.w600, letterSpacing: 0.3)),
          const SizedBox(height: 2),
          Text(value > 0 ? value.toStringAsFixed(2) : '—',
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: highlighted ? FontWeight.w800 : FontWeight.w600)),
        ]),
      ),
    );
  }
}

// ─── BADGE RÉSULTAT ───────────────────────────────────────────────────────────
class _ResultBadge extends StatelessWidget {
  final MatchEntity match;
  const _ResultBadge({required this.match});

  @override
  Widget build(BuildContext context) {
    final score  = '${match.homeScore ?? 0} - ${match.awayScore ?? 0}';
    final won    = match.predictionWon;
    final color  = won == null
        ? context.cl.textS
        : won ? AppColors.success : AppColors.error;
    final icon   = won == null ? null : (won ? Icons.check_circle_rounded : Icons.cancel_rounded);

    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text(score, style: TextStyle(
        color: color, fontSize: 12, fontWeight: FontWeight.w700)),
      if (icon != null) ...[
        const SizedBox(width: 4),
        Icon(icon, color: color, size: 14),
      ],
    ]);
  }
}

// ─── LOGO ÉQUIPE ──────────────────────────────────────────────────────────────
class _TeamLogo extends StatelessWidget {
  final String url;
  const _TeamLogo({required this.url});

  @override
  Widget build(BuildContext context) =>
      TeamLogoWidget(url: url.isEmpty ? null : url, size: 40);
}

// ─── COLONNE ÉQUIPE ───────────────────────────────────────────────────────────
class _TeamColumn extends StatelessWidget {
  final String name;
  final String? logo;
  final bool isHome;
  final bool isWinner;

  const _TeamColumn({
    required this.name,
    required this.logo,
    required this.isHome,
    this.isWinner = false,
  });

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Hero(
            tag: 'team_${isHome ? "home" : "away"}_$name',
            flightShuttleBuilder: _circleShuttleBuilder,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: context.cl.surfaceDeep,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isWinner
                      ? AppColors.success.withValues(alpha: 0.5)
                      : context.cl.border,
                  width: isWinner ? 1.5 : 0.5,
                ),
                boxShadow: isWinner
                    ? [BoxShadow(
                        color: AppColors.success.withValues(alpha: 0.2),
                        blurRadius: 8)]
                    : [],
              ),
              child: logo != null && logo!.isNotEmpty
                  ? ClipOval(child: _TeamLogo(url: logo!))
                  : Icon(Icons.sports_soccer_rounded,
                      color: context.cl.textM, size: 22),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            name,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isWinner ? context.cl.textP : context.cl.textS,
              fontSize: 11,
              fontWeight:
                  isWinner ? FontWeight.w700 : FontWeight.w500,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      );
}

// ─── SCORE CENTRAL ────────────────────────────────────────────────────────────
class _ScoreCenter extends StatelessWidget {
  final MatchEntity match;
  const _ScoreCenter({required this.match});

  @override
  Widget build(BuildContext context) {
    if (match.status == MatchStatus.live || match.status == MatchStatus.finished) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: match.status == MatchStatus.live
                    ? AppColors.error.withValues(alpha: 0.08)
                    : context.cl.surfaceDeep,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: match.status == MatchStatus.live
                      ? AppColors.error.withValues(alpha: 0.3)
                      : context.cl.borderSoft,
                  width: match.status == MatchStatus.live ? 1 : 0.5,
                ),
              ),
              child: Text(
                '${match.homeScore ?? 0} - ${match.awayScore ?? 0}',
                style: TextStyle(
                  color: match.status == MatchStatus.live ? AppColors.error : context.cl.textP,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                ),
              ),
            ),
            if (match.status == MatchStatus.live) ...[
              const SizedBox(height: 4),
              const Text('En direct',
                  style: TextStyle(
                      color: AppColors.error,
                      fontSize: 9,
                      fontWeight: FontWeight.w600)),
            ],
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Text('VS',
          style: TextStyle(
              color: context.cl.textM,
              fontSize: 13,
              fontWeight: FontWeight.w700)),
    );
  }
}

class _ScorePlaceholder extends StatelessWidget {
  const _ScorePlaceholder();
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: Text('VS',
        style: TextStyle(color: context.cl.textM, fontSize: 13)),
  );
}

// ─── JAUGE DE CONFIANCE ANIMÉE ───────────────────────────────────────────────
class _ConfidenceBar extends StatelessWidget {
  final int score; // 1-5
  const _ConfidenceBar({required this.score});

  Color get _barColor {
    if (score >= 5) return AppColors.success;
    if (score >= 4) return const Color(0xFF84CC16);
    if (score >= 3) return AppColors.warning;
    if (score >= 2) return const Color(0xFFF97316);
    return AppColors.error;
  }

  String get _label {
    if (score >= 5) return 'Excellent';
    if (score >= 4) return 'Bon';
    if (score >= 3) return 'Moyen';
    if (score >= 2) return 'Faible';
    return 'Risqué';
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Text(_label, style: TextStyle(
        color: _barColor, fontSize: 9, fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: score.toDouble()),
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOutCubic,
        builder: (_, value, _) => SizedBox(
          width: 48, height: 5,
          child: Row(
            children: List.generate(5, (i) {
              final fill = (value - i).clamp(0.0, 1.0);
              return Expanded(child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 1),
                decoration: BoxDecoration(
                  color: fill > 0
                    ? _barColor.withValues(alpha: fill)
                    : context.cl.borderSoft,
                  borderRadius: BorderRadius.circular(3))));
            }),
          ),
        ),
      ),
    ],
  );
}

// ─── PASTILLE BET ─────────────────────────────────────────────────────────────
class _BetBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color:  AppColors.success.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppColors.success.withValues(alpha: 0.35), width: 0.7)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.account_balance_wallet_rounded,
          color: AppColors.success, size: 9),
        const SizedBox(width: 3),
        Text('Misé', style: const TextStyle(
          color:      AppColors.success,
          fontSize:   9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2)),
      ]),
    );
  }
}

// ─── Helper Hero : transition circulaire fluide ───────────────────────────────
Widget _circleShuttleBuilder(
  BuildContext ctx,
  Animation<double> animation,
  HeroFlightDirection direction,
  BuildContext from,
  BuildContext to,
) {
  final heroWidget = direction == HeroFlightDirection.push ? to : from;
  return AnimatedBuilder(
    animation: animation,
    builder: (context, child) => ClipOval(child: heroWidget.widget),
  );
}

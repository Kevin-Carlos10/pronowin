import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../../core/utils/motion.dart';
import '../../../../shared/widgets/confidence_indicator.dart';
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
              'Pronostic : ${m.displayPredictionLabel}. '
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
                        ? const Color(0xFFDAA520).withValues(alpha: 0.5)
                        : AppColors.primary.withValues(alpha: 0.25),
            width: widget.match.status == MatchStatus.live ? 1.5
                : locked ? 1.0 : 0.5,
          ),
          boxShadow: widget.match.status == MatchStatus.live
              ? [BoxShadow(
                    color: AppColors.error.withValues(alpha: 0.12),
                    blurRadius: 16,
                    offset: const Offset(0, 4))]
              : locked
              ? [BoxShadow(
                    color: const Color(0xFFDAA520).withValues(alpha: 0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 3))]
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
          // Badge ligue.
          //
          // Le nom de la ligue n'avait aucune contrainte : ni `Flexible`, ni
          // troncature. « UEFA Champions League » ou « Campeonato Brasileiro
          // Série A » poussaient la rangée au-delà du bord, et la carte —
          // le widget le plus répété de l'application — affichait la bande
          // rayée jaune et noire. Dès 411 px, sans même agrandir le texte.
          //
          // `Flexible` sur les deux niveaux : le badge cède de la place au
          // reste de la rangée, et le libellé s'ellipse au lieu de pousser.
          Flexible(
            child: Container(
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
                  Flexible(
                    child: Text(
                      widget.match.league,
                      style: TextStyle(color: context.cl.textS, fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (widget.showDate) ...[
            const SizedBox(width: 6),
            // `Flexible` ici aussi : la date, le badge de pari et le badge de
            // résultat s'ajoutaient tous au groupe de gauche sans qu'aucun ne
            // puisse céder. Sur un match terminé avec la date affichée, la
            // rangée dépassait dès 411 px — sans même agrandir le texte.
            Flexible(
              child: Text(
                DateFormat('dd/MM', 'fr_FR').format(widget.match.matchDate),
                style: TextStyle(color: context.cl.textM, fontSize: 10),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
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
                // La cote recommandée vit dans la même boîte que le
                // pronostic auquel elle se rapporte. Elle n'était affichée
                // nulle part : les trois cotes 1/N/2 juste en dessous portent
                // sur le marché « vainqueur », pas sur le pronostic — on
                // pouvait donc prendre 1.79 pour la cote de « Plus de 2.5 ».
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        widget.match.displayPredictionLabel,
                        style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    ),
                    if (widget.match.oddsRecommended > 0) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          widget.match.oddsRecommended.toStringAsFixed(2),
                          style: const TextStyle(
                              color: AppColors.success,
                              fontSize: 12,
                              fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            // Score confiance (jauge)
            ConfidenceIndicator(score: widget.match.confidenceScore),
          ]),

          const SizedBox(height: 8),

          // Ligne 2 : cotes du marché « vainqueur ». Explicitement nommées :
          // sans titre, elles se lisaient comme les cotes du pronostic.
          Row(children: [
            Text('VAINQUEUR DU MATCH',
                style: TextStyle(
                    color: context.cl.textM,
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6)),
            const SizedBox(width: 6),
            Expanded(child: Divider(color: context.cl.border, height: 1)),
          ]),
          const SizedBox(height: 6),
          _OddsRow(match: widget.match),
        ],
      ),
    );
  }

  // ─── CONTENU VERROUILLÉ ────────────────────────────────────────────────────
  Widget _buildLockedContent(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(children: [

        // ── Équipes (VISIBLES) ──────────────────────────────────────────
        Row(children: [
          Expanded(child: _TeamColumn(
            name: widget.match.homeTeam,
            logo: widget.match.homeTeamLogo,
            isHome: true)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text('VS', style: TextStyle(
              color: context.cl.textM, fontSize: 13,
              fontWeight: FontWeight.w700))),
          Expanded(child: _TeamColumn(
            name: widget.match.awayTeam,
            logo: widget.match.awayTeamLogo,
            isHome: false)),
        ]),

        const SizedBox(height: 12),

        // ── Zone prédiction (floutée + cadenas) ─────────────────────────
        ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 0, sigmaY: 0),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [
                    const Color(0xFFDAA520).withValues(alpha: 0.08),
                    const Color(0xFFFFD700).withValues(alpha: 0.04),
                  ]),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFFDAA520).withValues(alpha: 0.3),
                    width: 0.8)),
                child: Row(children: [
                  // Fake blurred prediction text blocks
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Simule le badge prédiction flouté
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                          child: Container(
                            height: 22,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(6))),
                        ),
                      ),
                      const SizedBox(height: 6),
                      // Simule la cote floutée
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                          child: Container(
                            height: 14, width: 60,
                            decoration: BoxDecoration(
                              color: context.cl.textM.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4))),
                        ),
                      ),
                    ],
                  )),
                  const SizedBox(width: 12),
                  // Icône cadenas + texte
                  Column(children: [
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFB8860B), Color(0xFFFFD700)],
                          begin: Alignment.topLeft, end: Alignment.bottomRight),
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(
                          color: const Color(0xFFFFD700).withValues(alpha: 0.3),
                          blurRadius: 8)]),
                      child: const Icon(Icons.lock_rounded,
                        color: Colors.white, size: 16)),
                    const SizedBox(height: 4),
                    const Text('VIP', style: TextStyle(
                      color: Color(0xFFDAA520), fontSize: 9,
                      fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                  ]),
                ]),
              ),
            ),
        ),

        const SizedBox(height: 8),

        // ── Cotes du marché « vainqueur », visibles même verrouillé ─────
        if (widget.match.oddsHome > 0 || widget.match.oddsDraw > 0 ||
            widget.match.oddsAway > 0)
          _LockedOddsRow(match: widget.match),

        const SizedBox(height: 10),

        // ── CTA gold ────────────────────────────────────────────────────
        GestureDetector(
          onTap: () => showPremiumGateSheet(context,
            matchLabel: '${widget.match.homeTeam} vs ${widget.match.awayTeam}'),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFB8860B), Color(0xFFFFD700), Color(0xFFDAA520)],
                begin: Alignment.centerLeft, end: Alignment.centerRight),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(
                color: const Color(0xFFFFD700).withValues(alpha: 0.25),
                blurRadius: 10, offset: const Offset(0, 3))]),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.workspace_premium_rounded,
                  color: Colors.white, size: 15),
                SizedBox(width: 7),
                Text('Voir le pronostic VIP', style: TextStyle(
                  color: Colors.white, fontSize: 12,
                  fontWeight: FontWeight.w800, letterSpacing: 0.2)),
              ],
            ),
          ),
        ),
      ]),
    );
  }

  // ─── PAS DE PRONOSTIC ──────────────────────────────────────────────────────
  Widget _buildNoPronosticContent(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(children: [
        // Équipes + Score/VS (score bien centré, badge "Terminé" pour les matchs finis)
        Row(children: [
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
        ]),
        if (widget.match.status != MatchStatus.finished) ...[
          const SizedBox(height: 12),
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
        ],
      ]),
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
    );
    _pulse = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Boucle infinie : coupée si l'utilisateur a réduit les animations.
    // Ce hook est aussi rappelé quand le réglage système change.
    context.boucler(_ctrl, reverse: true);
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
    );
    _shimmer = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Boucle infinie : coupée si l'utilisateur a réduit les animations.
    // Ce hook est aussi rappelé quand le réglage système change.
    context.boucler(_ctrl);
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

// ─── COTES VERROUILLÉES (visible sans surlignage) ────────────────────────────
class _LockedOddsRow extends StatelessWidget {
  final MatchEntity match;
  const _LockedOddsRow({required this.match});

  @override
  Widget build(BuildContext context) => Row(children: [
    _LockedOddsCell(label: '1', value: match.oddsHome, context: context),
    const SizedBox(width: 6),
    _LockedOddsCell(label: 'N', value: match.oddsDraw, context: context),
    const SizedBox(width: 6),
    _LockedOddsCell(label: '2', value: match.oddsAway, context: context),
  ]);
}

class _LockedOddsCell extends StatelessWidget {
  final String label;
  final double value;
  final BuildContext context;
  const _LockedOddsCell({required this.label, required this.value, required this.context});

  @override
  Widget build(BuildContext _) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 7),
      decoration: BoxDecoration(
        color: context.cl.surfaceD,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.cl.border, width: 0.5)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: TextStyle(
          color: context.cl.textM.withValues(alpha: 0.5),
          fontSize: 9, fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(value > 0 ? value.toStringAsFixed(2) : '—',
          style: TextStyle(
            color: context.cl.textS, fontSize: 13, fontWeight: FontWeight.w600)),
      ]),
    ),
  );
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
    final result = match.result;
    final color  = switch (result) {
      PronosticResult.win  => AppColors.success,
      PronosticResult.loss => AppColors.error,
      PronosticResult.push => AppColors.info,
      null                 => context.cl.textS,
    };
    final icon = switch (result) {
      PronosticResult.win  => Icons.check_circle_rounded,
      PronosticResult.loss => Icons.cancel_rounded,
      PronosticResult.push => Icons.replay_rounded,
      null                 => null,
    };

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
      final isLive = match.status == MatchStatus.live;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          children: [
            if (!isLive) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: context.cl.surfaceDeep,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('TERMINÉ',
                    style: TextStyle(
                        color: context.cl.textM,
                        fontSize: 8,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5)),
              ),
              const SizedBox(height: 5),
            ],
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isLive
                    ? AppColors.error.withValues(alpha: 0.08)
                    : context.cl.surfaceDeep,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isLive
                      ? AppColors.error.withValues(alpha: 0.3)
                      : context.cl.borderSoft,
                  width: isLive ? 1 : 0.5,
                ),
              ),
              child: Text(
                '${match.homeScore ?? 0} - ${match.awayScore ?? 0}',
                style: TextStyle(
                  color: isLive ? AppColors.error : context.cl.textP,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                ),
              ),
            ),
            if (isLive) ...[
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


// ─── JAUGE DE CONFIANCE ANIMÉE ───────────────────────────────────────────────
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

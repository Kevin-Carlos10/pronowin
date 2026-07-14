import 'dart:async';
import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../shared/utils/premium_nav.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/services/prono_share_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../bankroll/presentation/widgets/miser_dialog.dart';
import '../../../bankroll/presentation/providers/bankroll_provider.dart';
import '../../../../core/widgets/team_logo_widget.dart';
import '../../../../features/auth/presentation/providers/auth_provider.dart';
import '../../domain/entities/match_entity.dart';
import '../providers/favorites_provider.dart';
import '../providers/pronostics_provider.dart';
import '../widgets/prono_share_card.dart';

class MatchDetailPage extends ConsumerStatefulWidget {
  final String       matchId;
  final MatchEntity? preloaded;

  const MatchDetailPage({
    super.key,
    required this.matchId,
    this.preloaded,
  });

  @override
  ConsumerState<MatchDetailPage> createState() => _MatchDetailPageState();
}

class _MatchDetailPageState extends ConsumerState<MatchDetailPage> {
  Timer? _liveTimer;

  @override
  void dispose() {
    _liveTimer?.cancel();
    super.dispose();
  }

  void _startLivePolling() {
    _liveTimer?.cancel();
    _liveTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      ref.invalidate(liveScoreProvider(widget.matchId));
    });
  }

  void _stopLivePolling() {
    _liveTimer?.cancel();
    _liveTimer = null;
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final isPremium = authState is AuthAuthenticated && authState.user.isPremium;

    // Utilise la donnée fraîche du provider, avec preloaded comme fallback
    final matchAsync = ref.watch(matchDetailProvider(widget.matchId));
    final match = matchAsync.valueOrNull ?? widget.preloaded;

    // Démarrer/arrêter le polling selon le statut du match
    if (match?.status == MatchStatus.live) {
      if (_liveTimer == null) _startLivePolling();
    } else {
      _stopLivePolling();
    }

    if (match == null) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            onPressed: () => context.pop()),
          title: Text('Détail du match')),
        body: matchAsync.isLoading
          ? Center(child: CircularProgressIndicator(color: AppColors.primary))
          : Center(child: Text('Match introuvable',
              style: TextStyle(color: context.cl.textS))));
    }

    final isLocked = match.isPremium && !isPremium;
    final isRefreshing = matchAsync.isLoading && match.status == MatchStatus.live;
    final isFav = ref.watch(favoritesProvider).matchIds.contains(match.id);

    return Scaffold(
      backgroundColor: context.cl.bg,
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => context.pop()),
        title: Text(match.league,
          style: TextStyle(fontSize: 14, color: context.cl.textS)),
        centerTitle: true,
        actions: [
          // Bouton favori
          IconButton(
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Icon(
                isFav ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                key: ValueKey(isFav),
                size: 22,
                color: isFav ? AppColors.primary : context.cl.textS,
              ),
            ),
            tooltip: isFav ? 'Retirer des favoris' : 'Ajouter aux favoris',
            onPressed: () {
              HapticFeedback.selectionClick();
              ref.read(favoritesProvider.notifier).toggleMatch(match.id);
            },
          ),
          // Spinner discret pendant le refresh live
          if (isRefreshing)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: SizedBox(
                width: 16, height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.error))),
          if (!isLocked)
            IconButton(
              icon: const Icon(Icons.share_rounded, size: 20),
              tooltip: 'Partager',
              onPressed: () {
                HapticFeedback.selectionClick();
                _showShareSheet(context, match);
              },
            ),
          if (match.isPremium)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(
                isPremium
                  ? Icons.workspace_premium_rounded
                  : Icons.lock_rounded,
                color: isPremium ? AppColors.warning : context.cl.textM,
                size: 20)),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
        child: Column(children: [
          _MatchHeader(match: match)
            .animate().fadeIn(duration: 350.ms)
            .slideY(begin: -0.04, end: 0, curve: Curves.easeOutCubic),
          const SizedBox(height: 16),
          _MatchStatusRow(match: match)
            .animate(delay: 80.ms).fadeIn(duration: 300.ms)
            .slideX(begin: -0.05, end: 0, curve: Curves.easeOutCubic),
          const SizedBox(height: 16),
          if (match.hasPronostic) ...[
            _PronosticCard(match: match, isLocked: isLocked)
              .animate(delay: 130.ms).fadeIn(duration: 350.ms)
              .slideY(begin: 0.06, end: 0, curve: Curves.easeOutCubic),
            const SizedBox(height: 16),
          ],
          // Résultat du pronostic si match terminé
          if (match.predictionWon != null) ...[
            _ResultBanner(won: match.predictionWon!, pronosticId: match.id)
              .animate(delay: 160.ms).fadeIn(duration: 350.ms)
              .scale(begin: const Offset(0.95, 0.95), end: const Offset(1, 1),
                curve: Curves.easeOutBack),
            const SizedBox(height: 16),
          ],
          // Statistiques détaillées (matchs terminés uniquement)
          if (!isLocked && match.status == MatchStatus.finished) ...[
            _MatchStatsCard(matchId: match.id)
              .animate(delay: 170.ms).fadeIn(duration: 350.ms)
              .slideY(begin: 0.06, end: 0, curve: Curves.easeOutCubic),
            const SizedBox(height: 16),
          ],
          if (!isLocked && match.hasPronostic) ...[
            _OddsCard(match: match)
              .animate(delay: 200.ms).fadeIn(duration: 350.ms)
              .slideY(begin: 0.06, end: 0, curve: Curves.easeOutCubic),
            const SizedBox(height: 16),
            // Forme des équipes (masquée si aucune donnée)
            if (match.homeFormPoints > 0 || match.awayFormPoints > 0)
              _FormCard(match: match)
                .animate(delay: 240.ms).fadeIn(duration: 350.ms)
                .slideY(begin: 0.06, end: 0, curve: Curves.easeOutCubic),
            const SizedBox(height: 16),
          ],
          if (!isLocked && match.hasPronostic) ...[
            _H2HCard(matchId: match.id)
              .animate(delay: 260.ms).fadeIn(duration: 350.ms)
              .slideY(begin: 0.06, end: 0, curve: Curves.easeOutCubic),
            const SizedBox(height: 16),
            _AIAnalysisCard(matchId: match.id)
              .animate(delay: 290.ms).fadeIn(duration: 350.ms)
              .slideY(begin: 0.06, end: 0, curve: Curves.easeOutCubic),
            const SizedBox(height: 16),
            // Bouton miser — uniquement pour les matchs à venir
            if (match.status == MatchStatus.upcoming)
              _MiserButton(match: match)
                .animate(delay: 320.ms).fadeIn(duration: 350.ms)
                .slideY(begin: 0.06, end: 0, curve: Curves.easeOutCubic),
            const SizedBox(height: 16),
          ],
          if (!isLocked && match.hasPronostic && match.analystNote?.isNotEmpty == true) ...[
            _AnalystCard(match: match)
              .animate(delay: 280.ms).fadeIn(duration: 350.ms)
              .slideY(begin: 0.06, end: 0, curve: Curves.easeOutCubic),
            const SizedBox(height: 16),
          ],
          if (isLocked)
            _PremiumBanner(
              onTap: () => goToPremium(context, ref))
              .animate(delay: 200.ms).fadeIn(duration: 400.ms)
              .scale(begin: const Offset(0.95, 0.95), end: const Offset(1, 1),
                curve: Curves.easeOutBack),
        ]),
      ),
    );
  }
}

// HEADER
class _MatchHeader extends ConsumerWidget {
  final MatchEntity match;
  const _MatchHeader({required this.match});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Écouter le score live si match en cours
    final liveAsync = match.status == MatchStatus.live
        ? ref.watch(liveScoreProvider(match.id))
        : null;
    final homeScore = liveAsync?.valueOrNull?.homeScore ?? match.homeScore;
    final awayScore = liveAsync?.valueOrNull?.awayScore ?? match.awayScore;
    final isRefreshingScore = liveAsync?.isLoading ?? false;

    return Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFF151B2E), Color(0xFF0D1220)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(
        color: match.status == MatchStatus.live
            ? AppColors.error.withValues(alpha: 0.5)
            : context.cl.border,
        width: match.status == MatchStatus.live ? 1.5 : 0.5,
      ),
      boxShadow: match.status == MatchStatus.live
          ? [BoxShadow(color: AppColors.error.withValues(alpha: 0.1), blurRadius: 20)]
          : [],
    ),
    child: Column(children: [
      Text(
        match.leagueCountry.isNotEmpty
          ? '${match.leagueCountry} · ${match.league}'
          : match.league,
        style: TextStyle(
          color: context.cl.textM, fontSize: 11, letterSpacing: 0.5)),
      const SizedBox(height: 18),

      Row(children: [
        // Domicile
        Expanded(child: Column(children: [
          Hero(
            tag: 'team_home_${match.homeTeam}',
            child: _TeamLogo(url: match.homeTeamLogo ?? '', size: 64),
          ),
          SizedBox(height: 10),
          Text(match.homeTeam,
            style: TextStyle(color: context.cl.textP,
              fontSize: 14, fontWeight: FontWeight.w700),
            textAlign: TextAlign.center,
            maxLines: 2, overflow: TextOverflow.ellipsis),
        ])),

        // Score central
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(children: [
            Container(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: match.status == MatchStatus.live
                  ? AppColors.success.withValues(alpha: 0.08)
                  : context.cl.surfaceDeep,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: match.status == MatchStatus.live
                    ? AppColors.success.withValues(alpha: 0.3)
                    : context.cl.borderSoft,
                  width: match.status == MatchStatus.live ? 1.5 : 0.5)),
              child: Text(
                match.status == MatchStatus.live || match.status == MatchStatus.finished
                  ? '${homeScore ?? 0}  -  ${awayScore ?? 0}'
                  : 'VS',
                style: TextStyle(
                  color: match.status == MatchStatus.live
                    ? AppColors.success
                    : context.cl.textP,
                  fontSize: 24, fontWeight: FontWeight.w800,
                  letterSpacing: 2))),
            const SizedBox(height: 6),
            if (isRefreshingScore)
              SizedBox(width: 12, height: 12,
                child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.success))
            else if (match.status == MatchStatus.live)
              _LiveBadge()
            else if (match.status == MatchStatus.finished)
              Text('Terminé',
                style: TextStyle(color: context.cl.textM, fontSize: 11))
            else
              Text(
                '${match.matchDate.hour.toString().padLeft(2, '0')}:'
                '${match.matchDate.minute.toString().padLeft(2, '0')}',
                style: TextStyle(
                  color: context.cl.textS,
                  fontSize: 14, fontWeight: FontWeight.w600)),
          ]),
        ),

        // Extérieur
        Expanded(child: Column(children: [
          Hero(
            tag: 'team_away_${match.awayTeam}',
            child: _TeamLogo(url: match.awayTeamLogo ?? '', size: 64),
          ),
          SizedBox(height: 10),
          Text(match.awayTeam,
            style: TextStyle(color: context.cl.textP,
              fontSize: 14, fontWeight: FontWeight.w700),
            textAlign: TextAlign.center,
            maxLines: 2, overflow: TextOverflow.ellipsis),
        ])),
      ]),
    ]),
  );
  }
}

// STATUT
class _MatchStatusRow extends StatelessWidget {
  final MatchEntity match;
  const _MatchStatusRow({required this.match});

  @override
  Widget build(BuildContext context) {
    final d = match.matchDate;
    final dateStr =
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/'
      '${d.year}';
    final timeStr =
      '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';

    return Row(children: [
      _InfoChip(icon: Icons.calendar_today_rounded, label: dateStr, color: AppColors.info),
      SizedBox(width: 8),
      _InfoChip(icon: Icons.access_time_rounded, label: timeStr, color: context.cl.textS),
      const SizedBox(width: 8),
      _InfoChip(
        icon: match.status == MatchStatus.finished
          ? Icons.check_circle_rounded
          : match.status == MatchStatus.live
            ? Icons.circle_rounded
            : Icons.schedule_rounded,
        label: match.status == MatchStatus.finished ? 'Terminé'
          : match.status == MatchStatus.live ? 'En direct' : 'À venir',
        color: match.status == MatchStatus.finished ? context.cl.textM
          : match.status == MatchStatus.live ? AppColors.success : AppColors.primary),
    ]);
  }
}

// PRONOSTIC
class _PronosticCard extends StatelessWidget {
  final MatchEntity match;
  final bool isLocked;
  const _PronosticCard({required this.match, required this.isLocked});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      gradient: isLocked ? null : LinearGradient(
        colors: [Color(0xFF1A2040), Color(0xFF0D1530)],
        begin: Alignment.topLeft, end: Alignment.bottomRight),
      color: isLocked ? context.cl.surface : null,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: isLocked
          ? context.cl.border
          : AppColors.primary.withValues(alpha: 0.3),
        width: isLocked ? 0.5 : 1)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('PRONOSTIC', style: TextStyle(
        color: context.cl.textM, fontSize: 11,
        fontWeight: FontWeight.w600, letterSpacing: 1)),
      SizedBox(height: 14),

      if (isLocked)
        Row(children: [
          Icon(Icons.lock_rounded, color: context.cl.textM, size: 20),
          SizedBox(width: 10),
          Expanded(child: Text('Contenu réservé aux membres Premium',
            style: TextStyle(color: context.cl.textM, fontSize: 14))),
        ])
      else ...[
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.primary.withValues(alpha: 0.18),
                      AppColors.primaryLight.withValues(alpha: 0.08),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.35), width: 0.5),
                ),
                child: Text(
                  match.predictionLabel,
                  style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 20,
                      fontWeight: FontWeight.w800),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            const SizedBox(width: 14),
            _DetailConfidenceBar(score: match.confidenceScore),
          ],
        ),
      ],
    ]),
  );
}

// COTES
class _OddsCard extends StatelessWidget {
  final MatchEntity match;
  const _OddsCard({required this.match});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cl.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.cl.border, width: 0.5)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('COTES', style: TextStyle(
          color: context.cl.textM, fontSize: 11,
          fontWeight: FontWeight.w600, letterSpacing: 1)),
        const SizedBox(height: 12),
        Row(children: [
          _OddBox(label: '1', sublabel: 'Domicile',
            value: match.oddsHome,
            isRecommended: match.predictionType == PredictionType.win1),
          const SizedBox(width: 8),
          _OddBox(label: 'X', sublabel: 'Match nul',
            value: match.oddsDraw,
            isRecommended: match.predictionType == PredictionType.draw),
          const SizedBox(width: 8),
          _OddBox(label: '2', sublabel: 'Extérieur',
            value: match.oddsAway,
            isRecommended: match.predictionType == PredictionType.win2),
        ]),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.success.withValues(alpha: 0.2))),
          child: Row(children: [
            Icon(Icons.recommend_rounded, color: AppColors.success, size: 18),
            SizedBox(width: 10),
            Text('Cote recommandée',
              style: TextStyle(color: context.cl.textS, fontSize: 13)),
            const Spacer(),
            Text(match.oddsRecommended.toStringAsFixed(2),
              style: const TextStyle(
                color: AppColors.success, fontSize: 20,
                fontWeight: FontWeight.w800)),
          ])),
      ]),
    );
  }
}

// NOTE ANALYSTE
class _AnalystCard extends StatelessWidget {
  final MatchEntity match;
  const _AnalystCard({required this.match});

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: context.cl.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: context.cl.border, width: 0.5)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(
          width: 38, height: 38,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.12),
            shape: BoxShape.circle),
          child: Icon(Icons.person_rounded, color: AppColors.primary, size: 20)),
        SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('ANALYSE DE L\'EXPERT', style: TextStyle(
            color: context.cl.textM, fontSize: 11,
            fontWeight: FontWeight.w600, letterSpacing: 1)),
          Text('Notre Analyste', style: TextStyle(
            color: context.cl.textS, fontSize: 12)),
        ]),
      ]),
      SizedBox(height: 14),
      Text(match.analystNote!, style: TextStyle(
        color: context.cl.textS, fontSize: 14, height: 1.7)),
    ]),
  );
}

// BANNIERE PREMIUM
class _PremiumBanner extends StatefulWidget {
  final VoidCallback onTap;
  const _PremiumBanner({required this.onTap});
  @override
  State<_PremiumBanner> createState() => _PremiumBannerState();
}

class _PremiumBannerState extends State<_PremiumBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _pressCtrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _pressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 85),
      reverseDuration: const Duration(milliseconds: 150),
    );
    _scale = Tween(begin: 1.0, end: 0.97).animate(
      CurvedAnimation(parent: _pressCtrl, curve: Curves.easeOut));
  }

  @override
  void dispose() { _pressCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTapDown: (_) => _pressCtrl.forward(),
    onTapUp: (_) { _pressCtrl.reverse(); HapticFeedback.lightImpact(); widget.onTap(); },
    onTapCancel: () => _pressCtrl.reverse(),
    child: ScaleTransition(scale: _scale, child: Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A2040), Color(0xFF0D1530)],
          begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.4), width: 1)),
      child: Row(children: [
        Container(
          width: 50, height: 50,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(14)),
          child: const Icon(Icons.workspace_premium_rounded,
            color: AppColors.primaryLight, size: 28)),
        SizedBox(width: 14),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Accès Premium requis', style: TextStyle(
            color: context.cl.textP, fontSize: 15,
            fontWeight: FontWeight.w700)),
          SizedBox(height: 3),
          Text('Pronostic, cotes et analyse complète',
            style: TextStyle(color: context.cl.textS, fontSize: 12)),
        ])),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(20)),
          child: const Text('5 000 F', style: TextStyle(
            color: Colors.white, fontSize: 12,
            fontWeight: FontWeight.w700)))
          .animate(onPlay: (c) => c.repeat())
          .shimmer(duration: 2000.ms, delay: 600.ms, color: Colors.white30),
      ]),
    )),
  );
}

// WIDGETS UTILITAIRES
class _TeamLogo extends StatelessWidget {
  final String url;
  final double size;
  const _TeamLogo({required this.url, this.size = 40});
  @override
  Widget build(BuildContext context) =>
      TeamLogoWidget(url: url.isEmpty ? null : url, size: size);
}

class _LiveBadge extends StatefulWidget {
  @override
  State<_LiveBadge> createState() => _LiveBadgeState();
}

class _LiveBadgeState extends State<_LiveBadge>
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
    _pulse = Tween<double>(begin: 0.4, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: AppColors.error.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: AppColors.error.withValues(alpha: 0.4), width: 0.5),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      AnimatedBuilder(
        animation: _pulse,
        builder: (_, _) => Container(
          width: 7, height: 7,
          decoration: BoxDecoration(
            color: AppColors.error.withValues(alpha: _pulse.value),
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(
              color: AppColors.error.withValues(alpha: _pulse.value * 0.6),
              blurRadius: 4,
            )],
          ),
        ),
      ),
      const SizedBox(width: 6),
      const Text('EN DIRECT', style: TextStyle(
        color: AppColors.error, fontSize: 11,
        fontWeight: FontWeight.w700, letterSpacing: 0.5)),
    ]));
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _InfoChip({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withValues(alpha: 0.2), width: 0.5)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 12, color: color),
      const SizedBox(width: 5),
      Text(label, style: TextStyle(
        color: color, fontSize: 11, fontWeight: FontWeight.w500)),
    ]));
}

class _DetailConfidenceBar extends StatelessWidget {
  final int score;
  const _DetailConfidenceBar({required this.score});

  Color get _color {
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
      Text('CONFIANCE',
          style: TextStyle(
              color: context.cl.textM,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8)),
      const SizedBox(height: 8),
      TweenAnimationBuilder<int>(
        tween: IntTween(begin: 0, end: score),
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeOutCubic,
        builder: (context, animScore, _) => SizedBox(
          width: 80,
          height: 7,
          child: Row(
            children: List.generate(5, (i) {
              final filled = i < animScore;
              return Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 1.5),
                  decoration: BoxDecoration(
                    color: filled ? _color : context.cl.borderSoft,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
      const SizedBox(height: 5),
      Text(_label,
          style: TextStyle(
              color: _color, fontSize: 11, fontWeight: FontWeight.w700)),
    ],
  );
}

// ─── PARTAGE ─────────────────────────────────────────────────────────────────

String _buildShareText(MatchEntity match) {
  final stars  = '⭐' * match.confidenceScore.clamp(1, 5);
  final date   = DateFormat('dd/MM/yyyy à HH:mm', 'fr_FR').format(match.matchDate);
  final link   = 'https://pronowin.app/pronostics/${match.id}';
  return '⚽ *PronoWin — Pronostic*\n\n'
      '🏟️ ${match.homeTeam} vs ${match.awayTeam}\n'
      '🏆 ${match.league}\n'
      '📅 $date\n\n'
      '🔮 *Pronostic :* ${match.predictionLabel}\n'
      '$stars Confiance : ${match.confidenceScore}/5\n'
      '💰 Cote recommandée : ${match.oddsRecommended.toStringAsFixed(2)}\n\n'
      '📲 Voir le pronostic complet : $link\n'
      '⬇️ Télécharge PronoWin pour tous les pronos !';
}

Future<void> _launchShare(String url) async {
  final uri = Uri.parse(url);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

void _showShareSheet(BuildContext context, MatchEntity match) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _ShareSheet(match: match),
  );
}

class _ShareSheet extends StatefulWidget {
  final MatchEntity match;
  const _ShareSheet({required this.match});
  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  final _cardKey = GlobalKey();
  bool _capturing = false;

  Future<void> _shareImage() async {
    if (_capturing) return;
    setState(() => _capturing = true);
    try {
      final text = _buildShareText(widget.match);
      await PronoShareService.captureAndShare(
        repaintKey: _cardKey,
        shareText:  text,
        pixelRatio: 3.0,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erreur de capture : $e'),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = _buildShareText(widget.match);

    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize:     0.5,
      maxChildSize:     0.95,
      builder: (_, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color:        context.cl.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border:       Border.all(color: context.cl.border, width: 0.5),
        ),
        child: ListView(
          controller: scrollCtrl,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          children: [

            // ── Handle ──────────────────────────────────────────────────────
            Center(
              child: Container(
                width: 36, height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: context.cl.borderS,
                  borderRadius: BorderRadius.circular(2)),
              ),
            ),

            Text('Partager ce pronostic',
              style: TextStyle(
                color: context.cl.textP, fontSize: 15,
                fontWeight: FontWeight.w700),
              textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text('${widget.match.homeTeam} vs ${widget.match.awayTeam}',
              style: TextStyle(color: context.cl.textS, fontSize: 12),
              textAlign: TextAlign.center),
            const SizedBox(height: 20),

            // ── Prévisualisation de la carte ─────────────────────────────────
            Center(
              child: RepaintBoundary(
                key: _cardKey,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: PronoShareCard(match: widget.match),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // ── Bouton principal : Partager l'image ──────────────────────────
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _capturing ? null : _shareImage,
                icon: _capturing
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.image_rounded, size: 18),
                label: Text(_capturing ? 'Génération…' : 'Partager l\'image'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                  textStyle: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // ── Boutons alternatifs ──────────────────────────────────────────
            Row(children: [
              Expanded(child: _ShareBtn(
                fallbackIcon: Icons.chat_rounded,
                label: 'WhatsApp',
                color: const Color(0xFF25D366),
                onTap: () async {
                  final encoded = Uri.encodeComponent(text);
                  await _launchShare('https://wa.me/?text=$encoded');
                  if (context.mounted) Navigator.pop(context);
                },
              )),
              const SizedBox(width: 10),
              Expanded(child: _ShareBtn(
                fallbackIcon: Icons.send_rounded,
                label: 'Telegram',
                color: const Color(0xFF0088CC),
                onTap: () async {
                  final encoded = Uri.encodeComponent(text);
                  await _launchShare('https://t.me/share/url?url=https://pronowin.app&text=$encoded');
                  if (context.mounted) Navigator.pop(context);
                },
              )),
              const SizedBox(width: 10),
              Expanded(child: _ShareBtn(
                fallbackIcon: Icons.copy_rounded,
                label: 'Copier',
                color: AppColors.primary,
                onTap: () {
                  Clipboard.setData(ClipboardData(text: text));
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Pronostic copié !'),
                    behavior: SnackBarBehavior.floating,
                    duration: Duration(seconds: 2),
                  ));
                },
              )),
            ]),
          ],
        ),
      ),
    );
  }
}

class _ShareBtn extends StatelessWidget {
  final IconData fallbackIcon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ShareBtn({
    required this.fallbackIcon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () { HapticFeedback.lightImpact(); onTap(); },
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 0.5)),
      child: Column(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            shape: BoxShape.circle),
          child: Center(child: Icon(fallbackIcon, color: color, size: 20)),
        ),
        const SizedBox(height: 8),
        Text(label, style: TextStyle(
          color: color, fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
    ),
  );
}

// ─── H2H ─────────────────────────────────────────────────────────────────────

class _H2HCard extends ConsumerWidget {
  final String matchId;
  const _H2HCard({required this.matchId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final h2hAsync = ref.watch(h2hProvider(matchId));

    // Pas de données → on n'affiche rien
    if (h2hAsync.valueOrNull?.matches.isEmpty == true) return const SizedBox.shrink();
    if (h2hAsync.hasError) return const SizedBox.shrink();

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
        h2hAsync.when(
          loading: () => _H2HLoading(),
          error: (_, __) => const SizedBox.shrink(),
          data: (h2h) => _H2HContent(h2h: h2h),
        ),
      ]),
    );
  }
}

class _H2HContent extends StatelessWidget {
  final H2HData h2h;
  const _H2HContent({required this.h2h});

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
      const SizedBox(height: 14),
      // Liste des derniers matchs
      ...h2h.matches.take(6).map((m) => _H2HRow(match: m, h2h: h2h)),
    ]);
  }
}

class _H2HRow extends StatelessWidget {
  final H2HMatchResult match;
  final H2HData        h2h;
  const _H2HRow({required this.match, required this.h2h});

  Color _winnerColor(BuildContext context) {
    if (match.winner == 'HOME_TEAM') return AppColors.success;
    if (match.winner == 'AWAY_TEAM') return AppColors.error;
    return context.cl.textM;
  }

  @override
  Widget build(BuildContext context) {
    final isHomeWin = match.winner == 'HOME_TEAM';
    final isAwayWin = match.winner == 'AWAY_TEAM';
    final dateStr   = DateFormat('dd/MM/yy').format(match.date);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        // Date
        SizedBox(
          width: 52,
          child: Text(dateStr,
            style: TextStyle(color: context.cl.textM, fontSize: 10))),
        // Équipe domicile
        Expanded(
          child: Text(match.homeTeam,
            textAlign: TextAlign.right,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isHomeWin ? AppColors.success : context.cl.textS,
              fontSize: 11,
              fontWeight: isHomeWin ? FontWeight.w700 : FontWeight.w400))),
        // Score
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 8),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: _winnerColor(context).withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: _winnerColor(context).withValues(alpha: 0.25), width: 0.5)),
          child: Text('${match.homeScore} - ${match.awayScore}',
            style: TextStyle(
              color: _winnerColor(context),
              fontSize: 12, fontWeight: FontWeight.w800)),
        ),
        // Équipe extérieure
        Expanded(
          child: Text(match.awayTeam,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isAwayWin ? AppColors.error : context.cl.textS,
              fontSize: 11,
              fontWeight: isAwayWin ? FontWeight.w700 : FontWeight.w400))),
      ]),
    );
  }
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
      ).animate(onPlay: (c) => c.repeat())
       .shimmer(duration: 1400.ms, color: context.cl.borderSoft),
    )),
  );
}

class _H2HError extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(children: [
      Icon(Icons.info_outline_rounded, color: context.cl.textM, size: 16),
      const SizedBox(width: 8),
      Text('Historique indisponible pour ce match.',
        style: TextStyle(color: context.cl.textM, fontSize: 12)),
    ]),
  );
}

class _H2HEmpty extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text('Aucune confrontation directe disponible.',
      style: TextStyle(color: context.cl.textM, fontSize: 12)),
  );
}

// ─── ANALYSE IA ──────────────────────────────────────────────────────────────

class _AIAnalysisCard extends ConsumerWidget {
  final String matchId;
  const _AIAnalysisCard({required this.matchId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aiAsync = ref.watch(aiAnalysisProvider(matchId));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF6C3AE8).withValues(alpha: 0.08),
            const Color(0xFF3A7BD5).withValues(alpha: 0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF6C3AE8).withValues(alpha: 0.25),
          width: 1,
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: const Color(0xFF6C3AE8).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.auto_awesome_rounded,
              color: Color(0xFF6C3AE8), size: 16),
          ),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Analyse IA',
              style: TextStyle(
                color: context.cl.textP,
                fontSize: 13,
                fontWeight: FontWeight.w700)),
            Text('Modèle ML + Claude AI',
              style: TextStyle(
                color: context.cl.textM,
                fontSize: 10,
                fontWeight: FontWeight.w500)),
          ]),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF6C3AE8).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text('UNIQUE EN AFRIQUE',
              style: TextStyle(
                color: Color(0xFF6C3AE8),
                fontSize: 8,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5)),
          ),
        ]),
        const SizedBox(height: 16),
        aiAsync.when(
          loading: () => _AILoadingState(),
          error: (_, __) => _AIErrorState(onRetry: () => ref.invalidate(aiAnalysisProvider(matchId))),
          data: (ai) => _AIData(analysis: ai),
        ),
      ]),
    );
  }
}

class _AIData extends StatelessWidget {
  final AiAnalysis analysis;
  const _AIData({required this.analysis});

  Color get _probColor {
    if (analysis.probability >= 70) return AppColors.success;
    if (analysis.probability >= 55) return const Color(0xFF84CC16);
    if (analysis.probability >= 45) return AppColors.warning;
    return AppColors.error;
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('PROBABILITÉ DE SUCCÈS',
              style: TextStyle(
                color: context.cl.textM,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6)),
            const SizedBox(height: 8),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: analysis.probability / 100),
              duration: const Duration(milliseconds: 1200),
              curve: Curves.easeOutCubic,
              builder: (ctx, val, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: val,
                      minHeight: 8,
                      backgroundColor: ctx.cl.borderSoft,
                      valueColor: AlwaysStoppedAnimation<Color>(_probColor),
                    ),
                  ),
                ],
              ),
            ),
          ]),
        ),
        const SizedBox(width: 16),
        TweenAnimationBuilder<int>(
          tween: IntTween(begin: 0, end: analysis.probability),
          duration: const Duration(milliseconds: 1200),
          curve: Curves.easeOutCubic,
          builder: (_, val, __) => Text('$val%',
            style: TextStyle(
              color: _probColor,
              fontSize: 28,
              fontWeight: FontWeight.w900,
            )),
        ),
      ]),
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.cl.surfaceD,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('✦ ', style: TextStyle(color: Color(0xFF6C3AE8), fontSize: 12)),
          Expanded(
            child: Text(analysis.explanation,
              style: TextStyle(
                color: context.cl.textS,
                fontSize: 12,
                height: 1.5,
              )),
          ),
        ]),
      ),
    ],
  );
}

class _AILoadingState extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(children: [
        SizedBox(
          width: 16, height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: const Color(0xFF6C3AE8),
          ),
        ),
        const SizedBox(width: 10),
        Text('Analyse en cours…',
          style: TextStyle(color: context.cl.textM, fontSize: 12)),
      ]),
      const SizedBox(height: 12),
      Container(
        height: 8,
        decoration: BoxDecoration(
          color: context.cl.borderSoft,
          borderRadius: BorderRadius.circular(6)),
      )
        .animate(onPlay: (c) => c.repeat())
        .shimmer(duration: 1500.ms, color: const Color(0xFF6C3AE8).withValues(alpha: 0.15)),
    ],
  );
}

class _AIErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  const _AIErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(Icons.warning_amber_rounded, color: context.cl.textM, size: 16),
    const SizedBox(width: 8),
    Expanded(
      child: Text('Analyse temporairement indisponible.',
        style: TextStyle(color: context.cl.textM, fontSize: 12))),
    TextButton(
      onPressed: onRetry,
      style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero),
      child: Text('Réessayer',
        style: TextStyle(color: const Color(0xFF6C3AE8), fontSize: 12))),
  ]);
}

// ─── RÉSULTAT DU PRONOSTIC ────────────────────────────────────────────────────

class _ResultBanner extends StatefulWidget {
  final bool won;
  final String pronosticId;
  const _ResultBanner({required this.won, required this.pronosticId});

  @override
  State<_ResultBanner> createState() => _ResultBannerState();
}

class _ResultBannerState extends State<_ResultBanner> {
  late final ConfettiController _confetti;

  static const _prefKey = 'celebrated_win_';

  @override
  void initState() {
    super.initState();
    _confetti = ConfettiController(duration: const Duration(milliseconds: 1500));
    if (widget.won) {
      _maybeCelebrate();
    }
  }

  Future<void> _maybeCelebrate() async {
    final prefs  = await SharedPreferences.getInstance();
    final key    = '$_prefKey${widget.pronosticId}';
    final already = prefs.getBool(key) ?? false;
    if (already || !mounted) return;

    await prefs.setBool(key, true);

    Future.delayed(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      HapticFeedback.vibrate();
      _confetti.play();
    });
  }

  @override
  void dispose() {
    _confetti.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.won ? AppColors.success : AppColors.error;
    final icon  = widget.won ? Icons.check_circle_rounded : Icons.cancel_rounded;
    final label = widget.won ? 'Pronostic gagnant !' : 'Pronostic perdant';

    return Stack(
      alignment: Alignment.topCenter,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.35), width: 1.2)),
          child: Row(children: [
            Icon(icon, color: color, size: 26),
            const SizedBox(width: 12),
            Text(label, style: TextStyle(
              color: color, fontSize: 15, fontWeight: FontWeight.w800)),
          ]),
        ),
        if (widget.won)
          ConfettiWidget(
            confettiController: _confetti,
            blastDirectionality: BlastDirectionality.explosive,
            numberOfParticles: 18,
            maxBlastForce: 12,
            minBlastForce: 4,
            gravity: 0.3,
            colors: const [
              AppColors.success,
              AppColors.warning,
              AppColors.primary,
              Color(0xFFFFFFFF),
            ],
            shouldLoop: false,
          ),
      ],
    );
  }
}

// ─── FORME RÉCENTE ────────────────────────────────────────────────────────────

class _FormCard extends StatelessWidget {
  final MatchEntity match;
  const _FormCard({required this.match});

  @override
  Widget build(BuildContext context) {
    final homePoints = match.homeFormPoints.clamp(0, 15);
    final awayPoints = match.awayFormPoints.clamp(0, 15);
    const maxPts     = 15;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cl.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.cl.border, width: 0.5)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('FORME RÉCENTE', style: TextStyle(
          color: context.cl.textM, fontSize: 11,
          fontWeight: FontWeight.w700, letterSpacing: 0.8)),
        const SizedBox(height: 14),
        _FormRow(team: match.homeTeam, points: homePoints, max: maxPts, color: AppColors.primary),
        const SizedBox(height: 10),
        _FormRow(team: match.awayTeam, points: awayPoints, max: maxPts, color: AppColors.warning),
        const SizedBox(height: 10),
        Text('Sur les 5 derniers matchs (victoire=3pts, nul=1pt)',
          style: TextStyle(color: context.cl.textM, fontSize: 10)),
      ]),
    );
  }
}

class _FormRow extends StatelessWidget {
  final String team;
  final int points, max;
  final Color color;
  const _FormRow({required this.team, required this.points, required this.max, required this.color});

  @override
  Widget build(BuildContext context) {
    final ratio = max > 0 ? points / max : 0.0;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(team, style: TextStyle(
          color: context.cl.textP, fontSize: 12, fontWeight: FontWeight.w600),
          maxLines: 1, overflow: TextOverflow.ellipsis)),
        Text('$points pts', style: TextStyle(
          color: color, fontSize: 12, fontWeight: FontWeight.w700)),
      ]),
      const SizedBox(height: 6),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: ratio.toDouble(),
          minHeight: 6,
          backgroundColor: context.cl.borderSoft,
          valueColor: AlwaysStoppedAnimation<Color>(color),
        ),
      ),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _OddBox extends StatelessWidget {
  final String label, sublabel;
  final double value;
  final bool isRecommended;
  const _OddBox({required this.label, required this.sublabel,
    required this.value, this.isRecommended = false});

  @override
  Widget build(BuildContext context) => Expanded(child: Container(
    padding: EdgeInsets.symmetric(vertical: 12),
    decoration: BoxDecoration(
      color: isRecommended
        ? AppColors.success.withValues(alpha: 0.08)
        : context.cl.surfaceDeep,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: isRecommended
          ? AppColors.success.withValues(alpha: 0.3)
          : context.cl.borderSoft,
        width: isRecommended ? 1.5 : 0.5)),
    child: Column(children: [
      Text(label, style: TextStyle(
        color: isRecommended ? AppColors.success : context.cl.textM,
        fontSize: 12, fontWeight: FontWeight.w600)),
      SizedBox(height: 4),
      Text(value.toStringAsFixed(2),
        style: TextStyle(
          color: isRecommended ? AppColors.success : context.cl.textP,
          fontSize: 20, fontWeight: FontWeight.w800)),
      SizedBox(height: 2),
      Text(sublabel, style: TextStyle(
        color: context.cl.textM, fontSize: 10)),
    ])));
}

// ══════════════════════════════════════════════════════════════════════════════
// BOUTON MISER
// ══════════════════════════════════════════════════════════════════════════════
class _MiserButton extends ConsumerStatefulWidget {
  final MatchEntity match;
  const _MiserButton({required this.match});
  @override
  ConsumerState<_MiserButton> createState() => _MiserButtonState();
}

// ─── STATISTIQUES DU MATCH TERMINÉ ───────────────────────────────────────────

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
            : _StatsContent(data: data),
        ),
      ]),
    );
  }
}

class _StatsContent extends StatefulWidget {
  final MatchStatsData data;
  const _StatsContent({required this.data});
  @override
  State<_StatsContent> createState() => _StatsContentState();
}

class _StatsContentState extends State<_StatsContent> {
  bool _showEvents = true;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Toggle événements / stats
      Row(children: [
        _TabChip(label: 'Événements', active: _showEvents,
          onTap: () => setState(() => _showEvents = true)),
        const SizedBox(width: 8),
        _TabChip(label: 'Stats', active: !_showEvents,
          onTap: () => setState(() => _showEvents = false)),
      ]),
      const SizedBox(height: 14),
      if (_showEvents)
        _EventsList(events: widget.data.events,
          homeTeam: widget.data.homeTeam, awayTeam: widget.data.awayTeam)
      else
        _StatsList(stats: widget.data.stats,
          homeTeam: widget.data.homeTeam, awayTeam: widget.data.awayTeam),
    ]);
  }
}

class _TabChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _TabChip({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: active ? AppColors.info.withValues(alpha: 0.15) : context.cl.surfaceDeep,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: active ? AppColors.info.withValues(alpha: 0.4) : context.cl.borderSoft,
          width: 0.8)),
      child: Text(label, style: TextStyle(
        color: active ? AppColors.info : context.cl.textM,
        fontSize: 12, fontWeight: FontWeight.w600)),
    ),
  );
}

class _EventsList extends StatelessWidget {
  final List<MatchEvent> events;
  final String homeTeam, awayTeam;
  const _EventsList({required this.events, required this.homeTeam, required this.awayTeam});

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
    final notable = events.where((e) =>
      e.type == 'Goal' ||
      e.type == 'Card'
    ).toList();

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
            SizedBox(width: 38,
              child: Text(minStr,
                style: TextStyle(
                  color: AppColors.info, fontSize: 11,
                  fontWeight: FontWeight.w700))),
            // Gauche (domicile)
            Expanded(child: isHome
              ? _EventItem(event: e, align: TextAlign.right)
              : const SizedBox()),
            // Icône centrale
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: _eventIcon(e),
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

    return Column(children: [
      // En-têtes d'équipes
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Expanded(child: Text(homeTeam,
            style: TextStyle(color: AppColors.primary, fontSize: 11,
              fontWeight: FontWeight.w700),
            textAlign: TextAlign.center,
            maxLines: 1, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 80),
          Expanded(child: Text(awayTeam,
            style: TextStyle(color: AppColors.warning, fontSize: 11,
              fontWeight: FontWeight.w700),
            textAlign: TextAlign.center,
            maxLines: 1, overflow: TextOverflow.ellipsis)),
        ]),
      ),
      ...filtered.map((s) => _StatRow(
        label: _frenchLabels[s.label] ?? s.label,
        home: s.home, away: s.away,
      )),
    ]);
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final dynamic home, away;
  const _StatRow({required this.label, this.home, this.away});

  double _parse(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    final s = v.toString().replaceAll('%', '');
    return double.tryParse(s) ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final hVal = _parse(home);
    final aVal = _parse(away);
    final total = hVal + aVal;
    final hRatio = total > 0 ? hVal / total : 0.5;

    final homeStr = home?.toString() ?? '0';
    final awayStr = away?.toString() ?? '0';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(homeStr,
            style: TextStyle(color: AppColors.primary, fontSize: 12,
              fontWeight: FontWeight.w700)),
          Expanded(child: Text(label,
            textAlign: TextAlign.center,
            style: TextStyle(color: context.cl.textM, fontSize: 10,
              letterSpacing: 0.3))),
          Text(awayStr,
            style: TextStyle(color: AppColors.warning, fontSize: 12,
              fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.5, end: hRatio),
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeOutCubic,
            builder: (_, val, __) => Stack(children: [
              Container(height: 7, color: AppColors.warning.withValues(alpha: 0.5)),
              FractionallySizedBox(
                widthFactor: val,
                child: Container(height: 7, color: AppColors.primary.withValues(alpha: 0.85)),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
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
      ).animate(onPlay: (c) => c.repeat())
       .shimmer(duration: 1400.ms, color: context.cl.borderSoft),
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

class _MiserButtonState extends ConsumerState<_MiserButton> {
  bool _betPlaced = false;

  @override
  Widget build(BuildContext context) {
    final alreadyBet = ref.watch(hasBetOnPronosticProvider(widget.match.id));

    if (_betPlaced || alreadyBet) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color:  AppColors.success.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.success.withValues(alpha: 0.3))),
        child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.check_circle_rounded, color: AppColors.success, size: 18),
          SizedBox(width: 8),
          Text('Mise enregistrée dans ton bankroll',
              style: TextStyle(color: AppColors.success,
                  fontSize: 13, fontWeight: FontWeight.w600)),
        ]),
      );
    }

    return GestureDetector(
      onTap: () async {
        HapticFeedback.lightImpact();
        final ok = await showMiserDialog(
          context,
          ref:              ref,
          pronosticId:      widget.match.id,
          homeTeam:         widget.match.homeTeam,
          awayTeam:         widget.match.awayTeam,
          predictionLabel:  widget.match.predictionLabel,
          confidenceScore:  widget.match.confidenceScore,
          oddsRecommended:  widget.match.oddsRecommended,
        );
        if (ok) setState(() => _betPlaced = true);
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.success, Color(0xFF059669)],
            begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(
            color: AppColors.success.withValues(alpha: 0.35),
            blurRadius: 14, offset: const Offset(0, 5))]),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.savings_rounded, color: Colors.white, size: 20),
          const SizedBox(width: 10),
          const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Valider ma mise',
                style: TextStyle(color: Colors.white,
                    fontSize: 15, fontWeight: FontWeight.w700)),
            Text('Ajouter à mon bankroll',
                style: TextStyle(color: Colors.white70, fontSize: 11)),
          ]),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20)),
            child: const Text('→', style: TextStyle(
                color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
          ),
        ]),
      ),
    );
  }
}

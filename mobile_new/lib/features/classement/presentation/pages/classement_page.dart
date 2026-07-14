import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/leaderboard_entity.dart';
import '../providers/leaderboard_provider.dart';

// Couleurs podium
const _gold   = Color(0xFFFFD700);
const _silver = Color(0xFFB0BEC5);
const _bronze = Color(0xFFCD7F32);

class ClassementPage extends ConsumerWidget {
  const ClassementPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period      = ref.watch(leaderboardPeriodProvider);
    final entriesAsync = ref.watch(leaderboardProvider(period));

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // ─── AppBar ────────────────────────────────────────────────
            _ClassementAppBar(period: period, onPeriodChange: (p) {
              HapticFeedback.selectionClick();
              ref.read(leaderboardPeriodProvider.notifier).state = p;
            }),

            // ─── Corps ─────────────────────────────────────────────────
            Expanded(
              child: entriesAsync.when(
                loading: () => const _Shimmer(),
                error:   (e, _) => Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.wifi_off_rounded, color: AppColors.error, size: 48),
                    const SizedBox(height: 12),
                    Text('Impossible de charger le classement',
                      style: TextStyle(color: context.cl.textS, fontSize: 14)),
                  ]),
                ),
                data: (entries) {
                  if (entries.isEmpty) {
                    return Center(child: Text('Aucune donnée',
                      style: TextStyle(color: context.cl.textM)));
                  }
                  final top3  = entries.take(3).toList();
                  final rest  = entries.skip(3).toList();

                  return RefreshIndicator(
                    color: _gold,
                    onRefresh: () async =>
                        ref.invalidate(leaderboardProvider(period)),
                    child: CustomScrollView(
                      slivers: [
                        // ── Podium ────────────────────────────────────
                        SliverToBoxAdapter(
                          child: _Podium(top3: top3)
                            .animate()
                            .fadeIn(duration: 500.ms)
                            .slideY(begin: 0.06, end: 0, curve: Curves.easeOutCubic),
                        ),

                        // ── Séparateur ────────────────────────────────
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                            child: Row(children: [
                              const Icon(Icons.format_list_numbered_rounded,
                                  color: AppColors.primary, size: 16),
                              const SizedBox(width: 8),
                              Text('SUITE DU CLASSEMENT', style: TextStyle(
                                color: context.cl.textS,
                                fontSize: 11, fontWeight: FontWeight.w600,
                                letterSpacing: 1)),
                            ]),
                          ),
                        ),

                        // ── Reste de la liste ─────────────────────────
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (_, i) => _EntryTile(entry: rest[i])
                                .animate(delay: Duration(milliseconds: i * 40))
                                .fadeIn(duration: 280.ms)
                                .slideX(begin: 0.04, end: 0,
                                    duration: 260.ms, curve: Curves.easeOutCubic),
                              childCount: rest.length,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── APP BAR ──────────────────────────────────────────────────────────────────
class _ClassementAppBar extends StatelessWidget {
  final LeaderboardPeriod period;
  final void Function(LeaderboardPeriod) onPeriodChange;
  const _ClassementAppBar({required this.period, required this.onPeriodChange});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        if (Navigator.canPop(context)) ...[
          GestureDetector(
            onTap: () { HapticFeedback.lightImpact(); Navigator.of(context).pop(); },
            child: Container(
              width: 34, height: 34,
              decoration: BoxDecoration(
                color: context.cl.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: context.cl.border, width: 0.5)),
              child: Icon(Icons.arrow_back_ios_new_rounded,
                color: context.cl.textP, size: 16),
            ),
          ),
          const SizedBox(width: 10),
        ],
        Container(
          width: 34, height: 34,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [_gold, Color(0xFFFF9800)],
              begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(10),
            boxShadow: [BoxShadow(
              color: _gold.withValues(alpha: 0.4),
              blurRadius: 10, offset: const Offset(0, 3))]),
          child: const Icon(Icons.emoji_events_rounded, color: Colors.white, size: 18),
        ).animate(onPlay: (c) => c.repeat(reverse: true))
         .scale(begin: const Offset(1.0, 1.0), end: const Offset(1.08, 1.08),
             duration: 1400.ms, curve: Curves.easeInOut),
        const SizedBox(width: 10),
        RichText(text: TextSpan(
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: context.cl.textP),
          children: const [
            TextSpan(text: 'Class'),
            TextSpan(text: 'ement', style: TextStyle(color: _gold)),
          ],
        )),
      ]).animate().fadeIn(duration: 400.ms).slideY(begin: -0.04, end: 0),
      const SizedBox(height: 12),
      _PeriodFilterBar(current: period, onChange: onPeriodChange)
        .animate(delay: 80.ms).fadeIn(duration: 300.ms),
    ]),
  );
}

// ─── FILTRE PÉRIODE ───────────────────────────────────────────────────────────
class _PeriodFilterBar extends StatelessWidget {
  final LeaderboardPeriod current;
  final void Function(LeaderboardPeriod) onChange;
  const _PeriodFilterBar({required this.current, required this.onChange});

  static const _tabs = [
    (LeaderboardPeriod.weekly,  'Cette semaine', Icons.calendar_view_week_rounded),
    (LeaderboardPeriod.monthly, 'Ce mois',       Icons.calendar_month_rounded),
    (LeaderboardPeriod.allTime, 'All time',      Icons.all_inclusive_rounded),
  ];

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 36,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: _tabs.length,
      separatorBuilder: (_, _) => const SizedBox(width: 8),
      itemBuilder: (_, i) {
        final (period, label, icon) = _tabs[i];
        final sel = period == current;
        return GestureDetector(
          onTap: () => onChange(period),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: sel ? AppColors.primary : context.cl.surfaceD,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: sel
                  ? AppColors.primary
                  : context.cl.borderS,
                width: sel ? 1.5 : 0.5),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon,
                color: sel ? Colors.white : context.cl.textM,
                size: 13),
              const SizedBox(width: 5),
              Text(label, style: TextStyle(
                color: sel ? Colors.white : context.cl.textM,
                fontSize: 12, fontWeight: sel ? FontWeight.w700 : FontWeight.w400)),
            ]),
          ),
        );
      },
    ),
  );
}

// ─── PODIUM ───────────────────────────────────────────────────────────────────
class _Podium extends StatelessWidget {
  final List<LeaderboardEntry> top3;
  const _Podium({required this.top3});

  @override
  Widget build(BuildContext context) {
    final e1 = top3.isNotEmpty ? top3[0] : null;
    final e2 = top3.length > 1 ? top3[1] : null;
    final e3 = top3.length > 2 ? top3[2] : null;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1A1200),
            context.cl.surfaceD,
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _gold.withValues(alpha: 0.2), width: 0.5),
      ),
      child: Column(children: [
        // ── Couronnes décoratives ─────────────────────────────────────
        Row(mainAxisAlignment: MainAxisAlignment.center, children: const [
          Icon(Icons.star_rounded, color: _gold, size: 12),
          SizedBox(width: 4),
          Icon(Icons.emoji_events_rounded, color: _gold, size: 22),
          SizedBox(width: 4),
          Icon(Icons.star_rounded, color: _gold, size: 12),
        ]),
        const SizedBox(height: 12),
        // ── Podium 3 colonnes : 2ème | 1er | 3ème ────────────────────
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // 2ème
            Expanded(child: _PodiumCol(entry: e2, color: _silver,
              height: 90, animDelay: 200.ms)),
            // 1er (plus grand)
            Expanded(child: _PodiumCol(entry: e1, color: _gold,
              height: 120, animDelay: 0.ms, isFirst: true)),
            // 3ème
            Expanded(child: _PodiumCol(entry: e3, color: _bronze,
              height: 72, animDelay: 300.ms)),
          ],
        ),
      ]),
    );
  }
}

class _PodiumCol extends StatelessWidget {
  final LeaderboardEntry? entry;
  final Color color;
  final double height;
  final Duration animDelay;
  final bool isFirst;
  const _PodiumCol({
    required this.entry,
    required this.color,
    required this.height,
    required this.animDelay,
    this.isFirst = false,
  });

  @override
  Widget build(BuildContext context) {
    if (entry == null) return const SizedBox();
    final e = entry!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Avatar
        Stack(alignment: Alignment.topRight, children: [
          _Avatar(pseudo: e.pseudo, avatarUrl: e.avatarUrl,
            size: isFirst ? 56 : 44, color: color),
          if (e.badge != null)
            Positioned(
              right: -2, top: -2,
              child: _Badge(badge: e.badge!),
            ),
        ]),
        const SizedBox(height: 6),

        // Pseudo
        Text(
          e.pseudo.length > 9 ? '${e.pseudo.substring(0, 9)}…' : e.pseudo,
          style: TextStyle(
            color: isFirst ? color : context.cl.textP,
            fontSize: isFirst ? 13 : 11,
            fontWeight: FontWeight.w700),
          textAlign: TextAlign.center,
        ),

        // Win rate
        Text(e.winRateLabel, style: TextStyle(
          color: color, fontSize: isFirst ? 13 : 11,
          fontWeight: FontWeight.w600)),

        const SizedBox(height: 6),

        // Bloc podium
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: height),
          duration: Duration(milliseconds: 600 + animDelay.inMilliseconds),
          curve: Curves.easeOutCubic,
          builder: (_, h, _) => Container(
            height: h,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [color.withValues(alpha: 0.4), color.withValues(alpha: 0.15)],
                begin: Alignment.topCenter, end: Alignment.bottomCenter),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
              border: Border.all(color: color.withValues(alpha: 0.5), width: 0.5),
            ),
            child: Center(
              child: Text(
                '#${e.rank}',
                style: TextStyle(
                  color: color, fontSize: 18, fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ),
      ],
    ).animate(delay: animDelay)
     .fadeIn(duration: 400.ms)
     .slideY(begin: 0.1, end: 0, curve: Curves.easeOutBack);
  }
}

// ─── AVATAR ───────────────────────────────────────────────────────────────────
class _Avatar extends StatelessWidget {
  final String pseudo;
  final String? avatarUrl;
  final double size;
  final Color color;
  const _Avatar({required this.pseudo, this.avatarUrl,
    required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 2),
        gradient: LinearGradient(
          colors: [color.withValues(alpha: 0.3), color.withValues(alpha: 0.1)],
          begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
      child: ClipOval(
        child: avatarUrl != null
          ? Image.network(avatarUrl!, fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _Initiale(pseudo: pseudo, size: size))
          : _Initiale(pseudo: pseudo, size: size),
      ),
    );
  }
}

class _Initiale extends StatelessWidget {
  final String pseudo;
  final double size;
  const _Initiale({required this.pseudo, required this.size});
  @override
  Widget build(BuildContext context) => Center(
    child: Text(
      pseudo.isNotEmpty ? pseudo[0].toUpperCase() : '?',
      style: TextStyle(
        color: context.cl.textP,
        fontSize: size * 0.42,
        fontWeight: FontWeight.w800),
    ),
  );
}

// ─── BADGE ────────────────────────────────────────────────────────────────────
class _Badge extends StatelessWidget {
  final String badge;
  const _Badge({required this.badge});

  static const _config = {
    'legend': (Icons.auto_awesome_rounded, Color(0xFFFFD700)),
    'expert': (Icons.workspace_premium_rounded, Color(0xFF7C3AED)),
    'rising': (Icons.trending_up_rounded, AppColors.success),
  };

  @override
  Widget build(BuildContext context) {
    final cfg = _config[badge];
    if (cfg == null) return const SizedBox.shrink();
    final (icon, color) = cfg;
    return Container(
      width: 16, height: 16,
      decoration: BoxDecoration(
        color: color, shape: BoxShape.circle,
        border: Border.all(color: context.cl.bg, width: 1.5)),
      child: Icon(icon, color: Colors.white, size: 9),
    );
  }
}

// ─── TUILE ENTRÉE (rang 4+) ───────────────────────────────────────────────────
class _EntryTile extends StatelessWidget {
  final LeaderboardEntry entry;
  const _EntryTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final e = entry;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: context.cl.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.cl.border, width: 0.5),
      ),
      child: Row(children: [
        // ── Rang ─────────────────────────────────────────────────────
        SizedBox(
          width: 28,
          child: Text(
            '#${e.rank}',
            style: TextStyle(
              color: e.rank <= 5 ? AppColors.primary : context.cl.textM,
              fontSize: 13,
              fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(width: 10),

        // ── Avatar ───────────────────────────────────────────────────
        Stack(alignment: Alignment.topRight, children: [
          _Avatar(pseudo: e.pseudo, avatarUrl: e.avatarUrl,
            size: 36, color: AppColors.primary),
          if (e.badge != null)
            Positioned(right: -1, top: -1, child: _Badge(badge: e.badge!)),
        ]),
        const SizedBox(width: 12),

        // ── Infos ────────────────────────────────────────────────────
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(e.pseudo, style: TextStyle(
              color: context.cl.textP,
              fontSize: 13, fontWeight: FontWeight.w600)),
            if (e.isPremium) ...[
              const SizedBox(width: 5),
              const Icon(Icons.workspace_premium_rounded,
                  color: _gold, size: 13),
            ],
          ]),
          const SizedBox(height: 2),
          Row(children: [
            Icon(Icons.check_circle_rounded,
              color: AppColors.success, size: 11),
            const SizedBox(width: 3),
            Text('${e.wonPredictions}/${e.totalPredictions} gagnés',
              style: TextStyle(color: context.cl.textM, fontSize: 10)),
          ]),
        ])),

        // ── Win rate ─────────────────────────────────────────────────
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          _WinRateBar(winRate: e.winRate),
          const SizedBox(height: 3),
          Text(e.winRateLabel, style: TextStyle(
            color: _winRateColor(e.winRate),
            fontSize: 12, fontWeight: FontWeight.w700)),
        ]),
      ]),
    );
  }

  Color _winRateColor(double rate) {
    if (rate >= 0.75) return AppColors.success;
    if (rate >= 0.60) return AppColors.warning;
    return AppColors.error;
  }
}

// ─── BARRE WIN RATE ───────────────────────────────────────────────────────────
class _WinRateBar extends StatelessWidget {
  final double winRate;
  const _WinRateBar({required this.winRate});

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: winRate),
    duration: const Duration(milliseconds: 700),
    curve: Curves.easeOutCubic,
    builder: (_, value, _) => SizedBox(
      width: 60, height: 5,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: LinearProgressIndicator(
          value: value,
          backgroundColor: context.cl.borderS,
          valueColor: AlwaysStoppedAnimation<Color>(_barColor(value)),
          minHeight: 5,
        ),
      ),
    ),
  );

  Color _barColor(double v) {
    if (v >= 0.75) return AppColors.success;
    if (v >= 0.60) return AppColors.warning;
    return AppColors.error;
  }
}

// ─── SHIMMER ──────────────────────────────────────────────────────────────────
class _Shimmer extends StatelessWidget {
  const _Shimmer();
  @override
  Widget build(BuildContext context) => ListView.builder(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
    itemCount: 10,
    itemBuilder: (_, i) => Container(
      margin: const EdgeInsets.only(bottom: 8),
      height: 62,
      decoration: BoxDecoration(
        color: context.cl.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.cl.border, width: 0.5)),
    ).animate(onPlay: (c) => c.repeat(reverse: true))
     .shimmer(duration: 1000.ms, color: Colors.white10),
  );
}

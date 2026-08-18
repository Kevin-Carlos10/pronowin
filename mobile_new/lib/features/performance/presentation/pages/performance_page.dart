import 'package:fl_chart/fl_chart.dart';
import '../../../../core/utils/motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

// ── Modèle ────────────────────────────────────────────────────────────────────
class PerformanceData {
  final int    periodDays;
  final int    stakeRef;
  final int    total;
  final int    wins;
  final int    losses;
  final int    winRate;
  final double roi;
  final int    simulatedNet;
  final int    bestStreak;
  final List<LeagueStat>   bestLeagues;
  final List<BalancePoint> history;
  final WeekStat thisWeek;

  const PerformanceData({
    required this.periodDays,
    required this.stakeRef,
    required this.total,
    required this.wins,
    required this.losses,
    required this.winRate,
    required this.roi,
    required this.simulatedNet,
    required this.bestStreak,
    required this.bestLeagues,
    required this.history,
    required this.thisWeek,
  });

  factory PerformanceData.fromJson(Map<String, dynamic> j) => PerformanceData(
    periodDays:   (j['period_days']      as num).toInt(),
    stakeRef:     (j['stake_reference']  as num).toInt(),
    total:        (j['total_pronostics'] as num).toInt(),
    wins:         (j['wins']             as num).toInt(),
    losses:       (j['losses']           as num).toInt(),
    winRate:      (j['win_rate']         as num).toInt(),
    roi:          (j['roi']              as num).toDouble(),
    simulatedNet: (j['simulated_net']    as num).toInt(),
    bestStreak:   (j['best_streak']      as num).toInt(),
    bestLeagues:  (j['best_leagues'] as List)
        .map((l) => LeagueStat.fromJson(l as Map<String, dynamic>)).toList(),
    history: (j['balance_history'] as List)
        .map((b) => BalancePoint.fromJson(b as Map<String, dynamic>)).toList(),
    thisWeek: WeekStat.fromJson(j['this_week'] as Map<String, dynamic>),
  );
}

class LeagueStat {
  final String league;
  final int    wins, total, winRate, netGain;
  const LeagueStat({required this.league, required this.wins,
      required this.total, required this.winRate, required this.netGain});
  factory LeagueStat.fromJson(Map<String, dynamic> j) => LeagueStat(
    league:  j['league']   as String,
    wins:    (j['wins']     as num).toInt(),
    total:   (j['total']    as num).toInt(),
    winRate: (j['win_rate'] as num).toInt(),
    netGain: (j['net_gain'] as num).toInt(),
  );
}

class BalancePoint {
  final DateTime date;
  final int      balance;
  final String?  result;
  const BalancePoint({required this.date, required this.balance, this.result});
  factory BalancePoint.fromJson(Map<String, dynamic> j) => BalancePoint(
    date:    DateTime.parse(j['date'] as String).toLocal(),
    balance: (j['balance'] as num).toInt(),
    result:  j['result'] as String?,
  );
}

class WeekStat {
  final int total, wins, winRate;
  const WeekStat({required this.total, required this.wins, required this.winRate});
  factory WeekStat.fromJson(Map<String, dynamic> j) => WeekStat(
    total:   (j['total']    as num).toInt(),
    wins:    (j['wins']     as num).toInt(),
    winRate: (j['win_rate'] as num).toInt(),
  );
}

// ── Provider ──────────────────────────────────────────────────────────────────
final performanceProvider = FutureProvider.autoDispose.family<PerformanceData, int>((ref, days) async {
  final dio = ref.read(dioProvider);
  final r   = await dio.get('/pronostics/performance', queryParameters: {'days': days});
  return PerformanceData.fromJson(r.data as Map<String, dynamic>);
});

// ── Page ──────────────────────────────────────────────────────────────────────
class PerformancePage extends ConsumerStatefulWidget {
  const PerformancePage({super.key});

  @override
  ConsumerState<PerformancePage> createState() => _PerformancePageState();
}

class _PerformancePageState extends ConsumerState<PerformancePage> {
  int _days = 30;

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final isPremium = authState is AuthAuthenticated && authState.user.isPremium;
    final perfAsync = ref.watch(performanceProvider(_days));

    return Scaffold(
      backgroundColor: context.cl.bg,
      appBar: AppBar(
        backgroundColor: context.cl.bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => context.pop()),
        title: RichText(text: TextSpan(
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: context.cl.textP),
          children: const [
            TextSpan(text: 'Ma '),
            TextSpan(text: 'Performance', style: TextStyle(color: AppColors.primary)),
          ],
        )),
        centerTitle: true,
        actions: [
          // Sélecteur de période
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _PeriodSelector(days: _days, onChange: (d) => setState(() => _days = d)),
          ),
        ],
      ),
      body: perfAsync.when(
        loading: () => const _PerformanceShimmer(),
        error:   (e, _) => _ErrorState(onRetry: () => ref.invalidate(performanceProvider(_days))),
        data: (perf) => _PerformanceView(
          perf:      perf,
          days:      _days,
          isPremium: isPremium,
        ),
      ),
    );
  }
}

// ── Sélecteur période ─────────────────────────────────────────────────────────
class _PeriodSelector extends StatelessWidget {
  final int days;
  final ValueChanged<int> onChange;
  const _PeriodSelector({required this.days, required this.onChange});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _PeriodSheet(current: days, onChange: onChange)),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('${days}j', style: const TextStyle(
          color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w700)),
        const SizedBox(width: 4),
        const Icon(Icons.expand_more_rounded, color: AppColors.primary, size: 14),
      ])),
  );
}

class _PeriodSheet extends StatelessWidget {
  final int current;
  final ValueChanged<int> onChange;
  const _PeriodSheet({required this.current, required this.onChange});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: context.cl.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 40, height: 4,
        decoration: BoxDecoration(color: context.cl.border, borderRadius: BorderRadius.circular(2))),
      const SizedBox(height: 16),
      Text('Période d\'analyse', style: TextStyle(
        color: context.cl.textP, fontSize: 15, fontWeight: FontWeight.w700)),
      const SizedBox(height: 16),
      ...[7, 14, 30, 60, 90].map((d) => ListTile(
        title: Text(_periodLabel(d), style: TextStyle(color: context.cl.textP)),
        trailing: current == d
            ? const Icon(Icons.check_rounded, color: AppColors.primary)
            : null,
        onTap: () { Navigator.pop(context); onChange(d); },
      )),
    ]),
  );

  String _periodLabel(int d) => switch (d) {
    7  => '7 derniers jours',
    14 => '2 dernières semaines',
    30 => '30 derniers jours',
    60 => '2 derniers mois',
    90 => '3 derniers mois',
    _  => '$d jours',
  };
}

// ── Vue principale ────────────────────────────────────────────────────────────
class _PerformanceView extends StatelessWidget {
  final PerformanceData perf;
  final int    days;
  final bool   isPremium;

  const _PerformanceView({required this.perf, required this.days, required this.isPremium});

  @override
  Widget build(BuildContext context) {
    final isPositive = perf.simulatedNet >= 0;

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async {},
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [

          // ── Carte ROI principale ──────────────────────────────────────
          _ROICard(perf: perf, isPositive: isPositive)
            .animate().fadeIn(duration: 350.ms).slideY(begin: -0.04, end: 0),

          const SizedBox(height: 14),

          // ── Simulation explication ────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.info.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.info.withValues(alpha: 0.2))),
            child: Row(children: [
              const Icon(Icons.info_outline_rounded, color: AppColors.info, size: 13),
              const SizedBox(width: 7),
              Expanded(child: Text(
                'Simulation basée sur une mise fixe de ${_fmt(perf.stakeRef.toDouble())} FCFA par pronostic sur ${perf.periodDays} jours.',
                style: TextStyle(color: context.cl.textS, fontSize: 11, height: 1.4))),
            ]),
          ).animate(delay: 60.ms).fadeIn(duration: 300.ms),

          const SizedBox(height: 14),

          // ── Stats rapides 4 chips ─────────────────────────────────────
          Row(children: [
            Expanded(child: _StatChip(
              icon:  Icons.receipt_long_rounded,
              label: 'Pronos',
              value: '${perf.total}',
              color: AppColors.info)),
            const SizedBox(width: 8),
            Expanded(child: _StatChip(
              icon:  Icons.emoji_events_rounded,
              label: 'Gagnés',
              value: '${perf.wins}',
              color: AppColors.success)),
            const SizedBox(width: 8),
            Expanded(child: _StatChip(
              icon:  Icons.trending_up_rounded,
              label: 'Win rate',
              value: '${perf.winRate}%',
              color: perf.winRate >= 55 ? AppColors.success : AppColors.warning)),
            const SizedBox(width: 8),
            Expanded(child: _StatChip(
              icon:  Icons.local_fire_department_rounded,
              label: 'Série max',
              value: '${perf.bestStreak}',
              color: AppColors.primaryLight)),
          ]).animate(delay: 80.ms).fadeIn(duration: 300.ms),

          const SizedBox(height: 14),

          // ── Cette semaine ─────────────────────────────────────────────
          _WeekCard(week: perf.thisWeek, stake: perf.stakeRef)
            .animate(delay: 100.ms).fadeIn(duration: 300.ms),

          const SizedBox(height: 14),

          // ── Graphique évolution simulée ───────────────────────────────
          if (perf.history.length >= 2)
            _SimulationChart(history: perf.history, stake: perf.stakeRef)
              .animate(delay: 120.ms).fadeIn(duration: 400.ms),

          if (perf.history.length >= 2) const SizedBox(height: 14),

          // ── Meilleures ligues ─────────────────────────────────────────
          if (perf.bestLeagues.isNotEmpty)
            _LeaguesCard(leagues: perf.bestLeagues)
              .animate(delay: 160.ms).fadeIn(duration: 300.ms),

          const SizedBox(height: 14),

          // ── CTA Premium si non premium ────────────────────────────────
          if (!isPremium)
            _PremiumCTA()
              .animate(delay: 200.ms).fadeIn(duration: 350.ms),
        ],
      ),
    );
  }
}

// ── Carte ROI ─────────────────────────────────────────────────────────────────
class _ROICard extends StatelessWidget {
  final PerformanceData perf;
  final bool isPositive;
  const _ROICard({required this.perf, required this.isPositive});

  @override
  Widget build(BuildContext context) {
    final color = isPositive ? AppColors.success : AppColors.error;

    // « +12 400 FCFA », « ROI », « +18 % », « 24 », « 9 » : cinq nombres sans
    // rattachement. Une seule phrase les relie et rappelle qu'il s'agit d'une
    // simulation, pas des gains réels de l'utilisateur.
    final annonce =
        'Performance simulée sur ${perf.periodDays} jours, '
        'pour une mise de référence de ${perf.stakeRef} FCFA. '
        '${isPositive ? "Gain" : "Perte"} de ${_fmt(perf.simulatedNet.abs().toDouble())} FCFA, '
        'retour sur investissement ${perf.roi} pour cent. '
        '${perf.wins} pronostics gagnés sur ${perf.total}, '
        'soit ${perf.winRate} pour cent de réussite.';

    return Semantics(
      label: annonce,
      excludeSemantics: true,
      child: Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withValues(alpha: 0.15),
            color.withValues(alpha: 0.04),
          ],
          begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.8)),
      child: Column(children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12)),
            child: Icon(Icons.analytics_rounded, color: color, size: 20)),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Gain simulé sur ${perf.periodDays} jours',
              style: TextStyle(color: context.cl.textM, fontSize: 11)),
            const SizedBox(height: 2),
            TweenAnimationBuilder<int>(
              tween: IntTween(begin: 0, end: perf.simulatedNet.abs()),
              duration: 900.ms,
              curve: Curves.easeOutCubic,
              builder: (_, v, _) => Text(
                '${isPositive ? '+' : '-'}${_fmt(v.toDouble())} FCFA',
                style: TextStyle(color: context.cl.textP, fontSize: 26,
                    fontWeight: FontWeight.w900, letterSpacing: -0.5)),
            ),
          ]),
          const Spacer(),
          // ROI badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: color.withValues(alpha: 0.4), width: 0.8)),
            child: Column(children: [
              Text('ROI', style: TextStyle(color: context.cl.textM, fontSize: 9,
                  fontWeight: FontWeight.w700, letterSpacing: 0.5)),
              const SizedBox(height: 2),
              Text('${isPositive ? '+' : ''}${perf.roi}%',
                style: TextStyle(color: color, fontSize: 18,
                    fontWeight: FontWeight.w900)),
            ]),
          ),
        ]),

        const SizedBox(height: 16),

        // Barre win/loss
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: perf.total > 0 ? perf.wins / perf.total : 0),
                duration: 800.ms,
                curve: Curves.easeOutCubic,
                builder: (_, v, _) => Stack(children: [
                  Container(height: 7, color: AppColors.error.withValues(alpha: 0.4)),
                  FractionallySizedBox(
                    widthFactor: v,
                    child: Container(height: 7, color: AppColors.success.withValues(alpha: 0.85))),
                ]),
              ),
            ),
            const SizedBox(height: 6),
            Row(children: [
              _Dot(color: AppColors.success),
              const SizedBox(width: 4),
              Text('${perf.wins} gagnés', style: TextStyle(color: context.cl.textM, fontSize: 10)),
              const SizedBox(width: 12),
              _Dot(color: AppColors.error),
              const SizedBox(width: 4),
              Text('${perf.losses} perdus', style: TextStyle(color: context.cl.textM, fontSize: 10)),
            ]),
          ])),
        ]),
      ]),
    ));
  }
}

class _Dot extends StatelessWidget {
  final Color color;
  const _Dot({required this.color});
  @override
  Widget build(BuildContext context) => Container(
    width: 7, height: 7,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle));
}

// ── Card semaine ──────────────────────────────────────────────────────────────
class _WeekCard extends StatelessWidget {
  final WeekStat week;
  final int      stake;
  const _WeekCard({required this.week, required this.stake});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: context.cl.surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: context.cl.border, width: 0.5)),
    child: Row(children: [
      Container(
        width: 38, height: 38,
        decoration: BoxDecoration(
          color: AppColors.info.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10)),
        child: const Icon(Icons.calendar_view_week_rounded, color: AppColors.info, size: 18)),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Cette semaine', style: TextStyle(
          color: context.cl.textP, fontSize: 13, fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text('${week.total} pronos · ${week.wins} gagnés · ${week.winRate}% réussite',
          style: TextStyle(color: context.cl.textM, fontSize: 11)),
      ])),
    ]),
  );
}

// ── Graphique simulation ──────────────────────────────────────────────────────
class _SimulationChart extends StatelessWidget {
  final List<BalancePoint> history;
  final int stake;
  const _SimulationChart({required this.history, required this.stake});

  @override
  Widget build(BuildContext context) {
    final spots = <FlSpot>[];
    for (var i = 0; i < history.length; i++) {
      spots.add(FlSpot(i.toDouble(), history[i].balance.toDouble()));
    }

    final minY = spots.map((s) => s.y).reduce((a, b) => a < b ? a : b) * 1.1;
    final maxY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b) * 1.1;
    final lastBalance = history.last.balance;
    final isPositive  = lastBalance >= 0;
    final lineColor   = isPositive ? AppColors.success : AppColors.error;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 16, 10),
      decoration: BoxDecoration(
        color: context.cl.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.cl.border, width: 0.5)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.show_chart_rounded, size: 14, color: lineColor),
          const SizedBox(width: 6),
          Text('Évolution simulée (${history.length} pronos)',
            style: TextStyle(color: context.cl.textP, fontSize: 13, fontWeight: FontWeight.w700)),
          const Spacer(),
          Text('Mise : ${_fmt(stake.toDouble())} FCFA/prono',
            style: TextStyle(color: context.cl.textM, fontSize: 10)),
        ]),
        const SizedBox(height: 14),
        SizedBox(
          height: 130,
          child: LineChart(LineChartData(
            minY: minY < 0 ? minY : 0,
            maxY: maxY > 0 ? maxY : 1,
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              getDrawingHorizontalLine: (_) => FlLine(color: context.cl.border, strokeWidth: 0.5),
            ),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              leftTitles: AxisTitles(sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 52,
                getTitlesWidget: (v, _) => Text(_shortAmt(v),
                  style: TextStyle(color: context.cl.textM, fontSize: 9)),
              )),
              bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles:    AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles:  AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipItems: (spots) => spots.map((s) => LineTooltipItem(
                  '${s.y >= 0 ? '+' : ''}${_fmt(s.y)} F',
                  TextStyle(color: s.y >= 0 ? AppColors.success : AppColors.error,
                    fontWeight: FontWeight.w700, fontSize: 11),
                )).toList(),
              ),
            ),
            lineBarsData: [
              // Ligne zéro
              LineChartBarData(
                spots: [FlSpot(0, 0), FlSpot((history.length - 1).toDouble(), 0)],
                color: context.cl.textM.withValues(alpha: 0.3),
                barWidth: 1,
                dashArray: [4, 4],
                dotData: FlDotData(show: false),
                belowBarData: BarAreaData(show: false),
              ),
              // Solde simulé
              LineChartBarData(
                spots: spots,
                isCurved: true,
                curveSmoothness: 0.3,
                color: lineColor,
                barWidth: 2.5,
                dotData: FlDotData(
                  show: true,
                  getDotPainter: (spot, _, _, idx) => FlDotCirclePainter(
                    radius:       idx == spots.length - 1 ? 4 : 1.5,
                    color:        idx == spots.length - 1 ? lineColor : lineColor.withValues(alpha: 0.5),
                    strokeWidth:  idx == spots.length - 1 ? 2 : 0,
                    strokeColor:  Colors.white,
                  ),
                ),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [lineColor.withValues(alpha: 0.15), lineColor.withValues(alpha: 0.0)],
                  ),
                ),
              ),
            ],
          )),
        ),
        const SizedBox(height: 6),
        Text(
          'Résultat final : ${isPositive ? '+' : ''}${_fmt(lastBalance.toDouble())} FCFA sur ${history.length} pronos',
          style: TextStyle(color: lineColor, fontSize: 11, fontWeight: FontWeight.w700)),
      ]),
    );
  }

  String _shortAmt(double v) {
    if (v.abs() >= 1000) return '${(v / 1000).toStringAsFixed(0)}k';
    return v.toStringAsFixed(0);
  }
}

// ── Meilleures ligues ─────────────────────────────────────────────────────────
class _LeaguesCard extends StatelessWidget {
  final List<LeagueStat> leagues;
  const _LeaguesCard({required this.leagues});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: context.cl.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: context.cl.border, width: 0.5)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: AppColors.warning.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10)),
          child: const Icon(Icons.emoji_events_rounded, color: AppColors.warning, size: 16)),
        const SizedBox(width: 10),
        Text('Ligues les plus rentables',
          style: TextStyle(color: context.cl.textP, fontSize: 13, fontWeight: FontWeight.w700)),
      ]),
      const SizedBox(height: 14),
      ...leagues.asMap().entries.map((e) {
        final i = e.key;
        final l = e.value;
        final isPos = l.netGain >= 0;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(children: [
            Container(
              width: 22, height: 22,
              decoration: BoxDecoration(
                color: i == 0
                    ? AppColors.warning.withValues(alpha: 0.2)
                    : context.cl.surfaceD,
                shape: BoxShape.circle),
              child: Center(child: Text('${i + 1}',
                style: TextStyle(
                  color: i == 0 ? AppColors.warning : context.cl.textM,
                  fontSize: 11, fontWeight: FontWeight.w800)))),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l.league, style: TextStyle(
                color: context.cl.textP, fontSize: 12, fontWeight: FontWeight.w600),
                maxLines: 1, overflow: TextOverflow.ellipsis),
              Text('${l.wins}/${l.total} · ${l.winRate}% réussite',
                style: TextStyle(color: context.cl.textM, fontSize: 10)),
            ])),
            Text(
              '${isPos ? '+' : ''}${_fmt(l.netGain.toDouble())} F',
              style: TextStyle(
                color: isPos ? AppColors.success : AppColors.error,
                fontSize: 12, fontWeight: FontWeight.w800)),
          ]),
        );
      }),
    ]),
  );
}

// ── CTA Premium ───────────────────────────────────────────────────────────────
class _PremiumCTA extends StatelessWidget {
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => context.push('/compte/activer-premium'),
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryLight],
          begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(
          color: AppColors.primary.withValues(alpha: 0.35),
          blurRadius: 14, offset: const Offset(0, 5))]),
      child: Row(children: [
        const Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 24),
        const SizedBox(width: 12),
        const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Accède à tous les pronos', style: TextStyle(
            color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
          Text('Et reproduis ces performances en réel', style: TextStyle(
            color: Colors.white70, fontSize: 11)),
        ])),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(20)),
          child: const Text('Premium', style: TextStyle(
            color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700))),
      ]),
    ),
  );
}

// ── Stat chip ─────────────────────────────────────────────────────────────────
class _StatChip extends StatelessWidget {
  final IconData icon;
  final String   label, value;
  final Color    color;
  const _StatChip({required this.icon, required this.label,
      required this.value, required this.color});

  @override
  // La valeur est au-dessus du libellé à l'écran : bon visuellement, mais lu
  // à l'envers par un lecteur d'écran.
  Widget build(BuildContext context) => Semantics(
    label: '$label : $value',
    excludeSemantics: true,
    child: Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: context.cl.surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: color.withValues(alpha: 0.2), width: 0.8)),
    child: Column(children: [
      Icon(icon, color: color, size: 18),
      const SizedBox(height: 5),
      Text(value, style: TextStyle(
        color: context.cl.textP, fontSize: 15, fontWeight: FontWeight.w800)),
      Text(label, style: TextStyle(color: context.cl.textM, fontSize: 9),
        textAlign: TextAlign.center),
    ]),
  ));
}

// ── Shimmer ───────────────────────────────────────────────────────────────────
class _PerformanceShimmer extends StatelessWidget {
  const _PerformanceShimmer();
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(children: [
      Container(height: 150, decoration: BoxDecoration(
        color: context.cl.surface, borderRadius: BorderRadius.circular(20)))
        .animate(onPlay: (c) { if (!context.animationsReduites) c.repeat(); })
        .shimmer(duration: 1200.ms, color: context.cl.borderSoft),
      const SizedBox(height: 14),
      Row(children: List.generate(4, (_) => Expanded(child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        height: 80,
        decoration: BoxDecoration(color: context.cl.surface, borderRadius: BorderRadius.circular(14)))
        .animate(onPlay: (c) { if (!context.animationsReduites) c.repeat(); })
        .shimmer(duration: 1200.ms, color: context.cl.borderSoft)))),
      const SizedBox(height: 14),
      Container(height: 170, decoration: BoxDecoration(
        color: context.cl.surface, borderRadius: BorderRadius.circular(16)))
        .animate(onPlay: (c) { if (!context.animationsReduites) c.repeat(); })
        .shimmer(duration: 1200.ms, color: context.cl.borderSoft),
    ]),
  );
}

// ── Error ─────────────────────────────────────────────────────────────────────
class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorState({required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(child: Column(
    mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.wifi_off_rounded, color: context.cl.textM, size: 40),
      const SizedBox(height: 12),
      Text('Données indisponibles', style: TextStyle(color: context.cl.textP, fontWeight: FontWeight.w700)),
      const SizedBox(height: 14),
      TextButton(onPressed: onRetry, child: const Text('Réessayer',
        style: TextStyle(color: AppColors.primary))),
    ],
  ));
}

// ── Helpers ───────────────────────────────────────────────────────────────────
String _fmt(double v) {
  final s = v.abs().toStringAsFixed(0);
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
    buf.write(s[i]);
  }
  return v < 0 ? '-${buf.toString()}' : buf.toString();
}

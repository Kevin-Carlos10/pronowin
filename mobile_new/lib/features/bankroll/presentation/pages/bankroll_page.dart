import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../providers/bankroll_provider.dart';

// ── Filtre actif ───────────────────────────────────────────────────────────────
enum _BetFilter { all, pending, win, loss }

class BankrollPage extends ConsumerStatefulWidget {
  const BankrollPage({super.key});
  @override
  ConsumerState<BankrollPage> createState() => _BankrollPageState();
}

class _BankrollPageState extends ConsumerState<BankrollPage> {
  _BetFilter _filter = _BetFilter.all;

  @override
  Widget build(BuildContext context) {
    final bankrollAsync = ref.watch(bankrollProvider);

    return Scaffold(
      backgroundColor: context.cl.bg,
      body: bankrollAsync.when(
        loading: () => const _BankrollShimmer(),
        error:   (e, _) => _ErrorState(onRetry: () => ref.invalidate(bankrollProvider)),
        data: (bankroll) => bankroll == null
            ? _SetupView(onSetup: () => _showBudgetDialog(context, null))
            : _BankrollView(
                bankroll:    bankroll,
                filter:      _filter,
                onFilter:    (f) => setState(() => _filter = f),
                onSetBudget: () => _showBudgetDialog(context, bankroll),
                onReset:     () => _confirmReset(context, ref),
              ),
      ),
    );
  }

  Future<void> _showBudgetDialog(BuildContext context, BankrollData? existing) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BudgetSheet(existing: existing),
    );
  }

  Future<void> _confirmReset(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.cl.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Réinitialiser ?',
            style: TextStyle(color: context.cl.textP, fontWeight: FontWeight.w700)),
        content: Text(
          'Ton solde sera remis à ton budget initial. L\'historique des paris reste conservé.',
          style: TextStyle(color: context.cl.textS, fontSize: 14)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: Text('Annuler', style: TextStyle(color: context.cl.textM))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Réinitialiser',
                style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        final dio = ref.read(dioProvider);
        await dio.post('/bankroll/reset');
        ref.invalidate(bankrollProvider);
        ref.invalidate(bankrollStatsProvider);
      } catch (_) {}
    }
  }
}

// ── Vue principale ────────────────────────────────────────────────────────────
class _BankrollView extends StatelessWidget {
  final BankrollData bankroll;
  final _BetFilter   filter;
  final ValueChanged<_BetFilter> onFilter;
  final VoidCallback onSetBudget;
  final VoidCallback onReset;

  const _BankrollView({
    required this.bankroll,
    required this.filter,
    required this.onFilter,
    required this.onSetBudget,
    required this.onReset,
  });

  List<BankrollBet> get _filtered {
    switch (filter) {
      case _BetFilter.pending: return bankroll.bets.where((b) => b.result == null).toList();
      case _BetFilter.win:     return bankroll.bets.where((b) => b.result == 'WIN').toList();
      case _BetFilter.loss:    return bankroll.bets.where((b) => b.result == 'LOSS').toList();
      case _BetFilter.all:     return bankroll.bets;
    }
  }

  @override
  Widget build(BuildContext context) {
    final settled  = bankroll.bets.where((b) => b.result != null).toList();
    final wins     = settled.where((b) => b.result == 'WIN').length;
    final winRate  = settled.isNotEmpty ? wins / settled.length * 100 : 0.0;
    final profit   = bankroll.currentBalance - bankroll.totalBudget;
    final pending  = bankroll.bets.where((b) => b.result == null).toList();
    final filtered = _filtered;

    return CustomScrollView(slivers: [
      // ── AppBar ─────────────────────────────────────────────────────────────
      SliverAppBar(
        floating: true, snap: true,
        backgroundColor: context.cl.bg,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Row(children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.success, Color(0xFF34D399)],
                begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(9),
              boxShadow: [BoxShadow(color: AppColors.success.withValues(alpha: 0.35),
                  blurRadius: 8, offset: const Offset(0, 3))]),
            child: const Icon(Icons.account_balance_wallet_rounded,
                color: Colors.white, size: 17)),
          const SizedBox(width: 10),
          RichText(text: TextSpan(
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700,
                color: context.cl.textP),
            children: const [
              TextSpan(text: 'Bank'),
              TextSpan(text: 'roll', style: TextStyle(color: AppColors.success)),
            ],
          )),
          const Spacer(),
          IconButton(
            icon: Icon(Icons.tune_rounded, color: context.cl.textM, size: 20),
            onPressed: onSetBudget),
        ]),
      ),

      SliverToBoxAdapter(child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // ── Carte solde principal ────────────────────────────────────────
          _BalanceCard(bankroll: bankroll, profit: profit).animate()
            .fadeIn(duration: 350.ms).slideY(begin: 0.05, end: 0),

          const SizedBox(height: 14),

          // ── Graphique évolution ──────────────────────────────────────────
          if (settled.length >= 2)
            _BalanceChart(bankroll: bankroll)
              .animate(delay: 60.ms).fadeIn(duration: 400.ms),

          if (settled.length >= 2) const SizedBox(height: 14),

          // ── Résumé hebdomadaire ──────────────────────────────────────────
          _WeeklySummary(bankroll: bankroll)
            .animate(delay: 80.ms).fadeIn(duration: 350.ms),

          const SizedBox(height: 14),

          // ── Stats rapides ─────────────────────────────────────────────
          Row(children: [
            Expanded(child: _StatChip(
              label: 'Paris',
              value: '${settled.length}',
              icon:  Icons.receipt_long_rounded,
              color: AppColors.info,
            )),
            const SizedBox(width: 10),
            Expanded(child: _StatChip(
              label: 'Victoires',
              value: '$wins',
              icon:  Icons.emoji_events_rounded,
              color: AppColors.success,
            )),
            const SizedBox(width: 10),
            Expanded(child: _StatChip(
              label: 'Win rate',
              value: '${winRate.toStringAsFixed(0)}%',
              icon:  Icons.trending_up_rounded,
              color: winRate >= 50 ? AppColors.success : AppColors.warning,
            )),
          ]).animate(delay: 100.ms).fadeIn(duration: 300.ms),

          const SizedBox(height: 14),

          // ── Alerte dérive ─────────────────────────────────────────────
          _DisciplineReminder()
            .animate(delay: 120.ms).fadeIn(duration: 300.ms),

          const SizedBox(height: 16),

          // ── Reset ─────────────────────────────────────────────────────
          GestureDetector(
            onTap: onReset,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color:  AppColors.error.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.error.withValues(alpha: 0.2), width: 0.8)),
              child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.refresh_rounded, color: AppColors.error, size: 16),
                SizedBox(width: 6),
                Text('Réinitialiser le solde', style: TextStyle(
                  color: AppColors.error, fontSize: 13, fontWeight: FontWeight.w600)),
              ]),
            ),
          ).animate(delay: 140.ms).fadeIn(duration: 300.ms),

          const SizedBox(height: 24),

          // ── Filtres ───────────────────────────────────────────────────
          _FilterRow(
            filter:   filter,
            pending:  pending.length,
            wins:     wins,
            losses:   settled.length - wins,
            total:    bankroll.bets.length,
            onFilter: onFilter,
          ).animate(delay: 160.ms).fadeIn(duration: 300.ms),

          const SizedBox(height: 12),

          // ── Liste filtrée ─────────────────────────────────────────────
          if (filtered.isEmpty)
            _EmptyFilter(filter: filter)
              .animate().fadeIn(duration: 300.ms)
          else
            ...filtered.asMap().entries.map((e) =>
              _BetCard(bet: e.value).animate(delay: Duration(milliseconds: e.key * 40))
                .fadeIn(duration: 280.ms)
                .slideY(begin: 0.06, end: 0, duration: 280.ms),
            ),

          const SizedBox(height: 100),
        ]),
      )),
    ]);
  }
}

// ── Graphique évolution du solde ──────────────────────────────────────────────
class _BalanceChart extends StatelessWidget {
  final BankrollData bankroll;
  const _BalanceChart({required this.bankroll});

  @override
  Widget build(BuildContext context) {
    // Construire les points : budget initial + chaque paris réglé dans l'ordre
    final settled = bankroll.bets
        .where((b) => b.result != null && b.profit != null)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    double running = bankroll.totalBudget;
    final spots = <FlSpot>[FlSpot(0, running)];
    for (var i = 0; i < settled.length; i++) {
      running += settled[i].profit!;
      spots.add(FlSpot((i + 1).toDouble(), running.clamp(0, double.infinity)));
    }

    final minY = spots.map((s) => s.y).reduce((a, b) => a < b ? a : b) * 0.95;
    final maxY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b) * 1.05;
    final isProfit = bankroll.currentBalance >= bankroll.totalBudget;
    final lineColor = isProfit ? AppColors.success : AppColors.error;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 16, 8),
      decoration: BoxDecoration(
        color: context.cl.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.cl.border, width: 0.5)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.show_chart_rounded, size: 14, color: lineColor),
          const SizedBox(width: 6),
          Text('Évolution du solde',
            style: TextStyle(color: context.cl.textP, fontSize: 13, fontWeight: FontWeight.w700)),
          const Spacer(),
          Text('${settled.length} paris',
            style: TextStyle(color: context.cl.textM, fontSize: 11)),
        ]),
        const SizedBox(height: 14),
        SizedBox(
          height: 110,
          child: LineChart(
            LineChartData(
              minY: minY,
              maxY: maxY,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) => FlLine(
                  color: context.cl.border,
                  strokeWidth: 0.5,
                ),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 48,
                  getTitlesWidget: (v, _) => Text(
                    _shortAmount(v),
                    style: TextStyle(color: context.cl.textM, fontSize: 9),
                  ),
                )),
                bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles:    AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:  AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipItems: (spots) => spots.map((s) => LineTooltipItem(
                    _shortAmount(s.y),
                    TextStyle(color: lineColor, fontWeight: FontWeight.w700, fontSize: 11),
                  )).toList(),
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  curveSmoothness: 0.35,
                  color: lineColor,
                  barWidth: 2.5,
                  dotData: FlDotData(
                    show: true,
                    getDotPainter: (spot, _, __, index) {
                      final isLast = index == spots.length - 1;
                      return FlDotCirclePainter(
                        radius: isLast ? 4 : 2,
                        color: lineColor,
                        strokeWidth: isLast ? 2 : 0,
                        strokeColor: Colors.white,
                      );
                    },
                  ),
                  belowBarData: BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        lineColor.withValues(alpha: 0.18),
                        lineColor.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
                // Ligne de référence (budget initial)
                LineChartBarData(
                  spots: [FlSpot(0, bankroll.totalBudget),
                          FlSpot((settled.length).toDouble(), bankroll.totalBudget)],
                  isCurved: false,
                  color: context.cl.textM.withValues(alpha: 0.3),
                  barWidth: 1,
                  dashArray: [4, 4],
                  dotData: FlDotData(show: false),
                  belowBarData: BarAreaData(show: false),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(children: [
          Container(width: 12, height: 2, color: lineColor),
          const SizedBox(width: 4),
          Text('Solde', style: TextStyle(color: context.cl.textM, fontSize: 9)),
          const SizedBox(width: 12),
          Container(width: 12, height: 2,
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(
                color: context.cl.textM.withValues(alpha: 0.3),
                width: 1,
                style: BorderStyle.solid,
              )),
            )),
          const SizedBox(width: 4),
          Text('Budget initial', style: TextStyle(color: context.cl.textM, fontSize: 9)),
        ]),
      ]),
    );
  }

  String _shortAmount(double v) {
    if (v.abs() >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v.abs() >= 1000)    return '${(v / 1000).toStringAsFixed(0)}k';
    return v.toStringAsFixed(0);
  }
}

// ── Résumé hebdomadaire ───────────────────────────────────────────────────────
class _WeeklySummary extends StatelessWidget {
  final BankrollData bankroll;
  const _WeeklySummary({required this.bankroll});

  @override
  Widget build(BuildContext context) {
    final now     = DateTime.now();
    final weekAgo = now.subtract(const Duration(days: 7));
    final weekly  = bankroll.bets
        .where((b) => b.createdAt.isAfter(weekAgo) && b.result != null)
        .toList();

    if (weekly.isEmpty) return const SizedBox.shrink();

    final wins    = weekly.where((b) => b.result == 'WIN').length;
    final profit  = weekly.fold<double>(0, (sum, b) => sum + (b.profit ?? 0));
    final isGain  = profit >= 0;
    final rate    = weekly.isNotEmpty ? (wins / weekly.length * 100).toStringAsFixed(0) : '0';

    return Container(
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
          child: const Icon(Icons.calendar_view_week_rounded,
              color: AppColors.info, size: 18)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Cette semaine',
            style: TextStyle(color: context.cl.textP, fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text('${weekly.length} paris · $wins gagnés · $rate% réussite',
            style: TextStyle(color: context.cl.textM, fontSize: 11)),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(
            '${isGain ? '+' : ''}${_formatAmount(profit)} ${bankroll.currency}',
            style: TextStyle(
              color: isGain ? AppColors.success : AppColors.error,
              fontSize: 13, fontWeight: FontWeight.w800)),
          Text('cette semaine', style: TextStyle(color: context.cl.textM, fontSize: 9)),
        ]),
      ]),
    );
  }
}

// ── Alerte discipline ─────────────────────────────────────────────────────────
class _DisciplineReminder extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: AppColors.warning.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppColors.warning.withValues(alpha: 0.2), width: 0.8)),
    child: Row(children: [
      const Icon(Icons.shield_rounded, color: AppColors.warning, size: 15),
      const SizedBox(width: 8),
      Expanded(child: Text(
        'Respecte toujours la mise calculée. Ne mise jamais plus sur le bookmaker.',
        style: TextStyle(color: context.cl.textS, fontSize: 11, height: 1.4),
      )),
    ]),
  );
}

// ── Filtres ───────────────────────────────────────────────────────────────────
class _FilterRow extends StatelessWidget {
  final _BetFilter   filter;
  final int pending, wins, losses, total;
  final ValueChanged<_BetFilter> onFilter;

  const _FilterRow({
    required this.filter,
    required this.pending,
    required this.wins,
    required this.losses,
    required this.total,
    required this.onFilter,
  });

  @override
  Widget build(BuildContext context) {
    final items = [
      (_BetFilter.all,     'Tous',      total,   context.cl.textM),
      (_BetFilter.pending, 'En attente', pending, AppColors.warning),
      (_BetFilter.win,     'Gagnés',    wins,    AppColors.success),
      (_BetFilter.loss,    'Perdus',    losses,  AppColors.error),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: items.map((item) {
        final (f, label, count, color) = item;
        final sel = filter == f;
        return GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            onFilter(f);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: sel ? color.withValues(alpha: 0.15) : context.cl.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: sel ? color : context.cl.border,
                width: sel ? 1.2 : 0.5)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(label, style: TextStyle(
                color: sel ? color : context.cl.textS,
                fontSize: 12,
                fontWeight: sel ? FontWeight.w700 : FontWeight.w500)),
              if (count > 0) ...[
                const SizedBox(width: 5),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: sel ? color.withValues(alpha: 0.2) : context.cl.border,
                    borderRadius: BorderRadius.circular(10)),
                  child: Text('$count', style: TextStyle(
                    color: sel ? color : context.cl.textM,
                    fontSize: 10, fontWeight: FontWeight.w700)),
                ),
              ],
            ]),
          ),
        );
      }).toList()),
    );
  }
}

// ── Etat vide filtre ──────────────────────────────────────────────────────────
class _EmptyFilter extends StatelessWidget {
  final _BetFilter filter;
  const _EmptyFilter({required this.filter});

  @override
  Widget build(BuildContext context) {
    final label = switch (filter) {
      _BetFilter.pending => 'Aucun pari en attente',
      _BetFilter.win     => 'Aucun pari gagné pour l\'instant',
      _BetFilter.loss    => 'Aucun pari perdu 🎉',
      _BetFilter.all     => 'Aucun pari enregistré',
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.inbox_rounded, color: context.cl.textM, size: 36),
        const SizedBox(height: 10),
        Text(label, style: TextStyle(color: context.cl.textS, fontSize: 13)),
      ]),
    );
  }
}

// ── Carte solde ───────────────────────────────────────────────────────────────
class _BalanceCard extends StatelessWidget {
  final BankrollData bankroll;
  final double profit;
  const _BalanceCard({required this.bankroll, required this.profit});

  @override
  Widget build(BuildContext context) {
    final isProfit    = profit >= 0;
    final profitColor = isProfit ? AppColors.success : AppColors.error;
    final pct         = bankroll.progressPct;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.success.withValues(alpha: 0.15),
            AppColors.success.withValues(alpha: 0.04),
          ],
          begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.25), width: 0.8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Solde actuel', style: TextStyle(
                color: context.cl.textM, fontSize: 12, fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            Text(
              '${_formatAmount(bankroll.currentBalance)} ${bankroll.currency}',
              style: TextStyle(
                color: context.cl.textP, fontSize: 28,
                fontWeight: FontWeight.w800, letterSpacing: -0.5)),
          ]),
          const Spacer(),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('Budget total', style: TextStyle(color: context.cl.textM, fontSize: 11)),
            const SizedBox(height: 2),
            Text(
              '${_formatAmount(bankroll.totalBudget)} ${bankroll.currency}',
              style: TextStyle(color: context.cl.textS, fontSize: 13, fontWeight: FontWeight.w600)),
          ]),
        ]),
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: pct.clamp(0.0, 1.0)),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (_, v, _) => LinearProgressIndicator(
              value: v,
              minHeight: 6,
              backgroundColor: AppColors.success.withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation<Color>(
                  pct >= 1 ? AppColors.success : AppColors.warning),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Icon(isProfit ? Icons.trending_up_rounded : Icons.trending_down_rounded,
              color: profitColor, size: 15),
          const SizedBox(width: 4),
          Text(
            '${isProfit ? '+' : ''}${_formatAmount(profit)} ${bankroll.currency}',
            style: TextStyle(color: profitColor, fontSize: 13, fontWeight: FontWeight.w700)),
          const Spacer(),
          Text(
            '${(pct * 100).toStringAsFixed(0)}% du budget',
            style: TextStyle(color: context.cl.textM, fontSize: 11)),
        ]),
      ]),
    );
  }
}

// ── Chip stat ─────────────────────────────────────────────────────────────────
class _StatChip extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _StatChip({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: context.cl.surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: color.withValues(alpha: 0.2), width: 0.8)),
    child: Column(children: [
      Icon(icon, color: color, size: 18),
      const SizedBox(height: 6),
      Text(value, style: TextStyle(
          color: context.cl.textP, fontSize: 16, fontWeight: FontWeight.w800)),
      Text(label, style: TextStyle(color: context.cl.textM, fontSize: 10)),
    ]),
  );
}

// ── Carte pari ────────────────────────────────────────────────────────────────
class _BetCard extends StatelessWidget {
  final BankrollBet bet;
  const _BetCard({required this.bet});

  @override
  Widget build(BuildContext context) {
    final isPending = bet.result == null;
    final isWin     = bet.result == 'WIN';
    final color     = isPending ? AppColors.warning
                    : isWin    ? AppColors.success
                    :             AppColors.error;
    final icon      = isPending ? Icons.hourglass_empty_rounded
                    : isWin    ? Icons.check_circle_rounded
                    :             Icons.cancel_rounded;

    return GestureDetector(
      onTap: () => context.push('/bankroll/bet/${bet.id}', extra: bet),
      child: Container(
        margin:  const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color:  context.cl.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: color.withValues(alpha: isPending ? 0.25 : 0.35), width: 0.8)),
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 18)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${bet.homeTeam} – ${bet.awayTeam}',
              style: TextStyle(color: context.cl.textP, fontSize: 13,
                  fontWeight: FontWeight.w600),
              maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 3),
            Text(bet.predictionLabel,
              style: TextStyle(color: context.cl.textM, fontSize: 11)),
          ])),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('−${_formatAmount(bet.stakedAmount)}',
              style: TextStyle(color: context.cl.textP, fontSize: 12,
                  fontWeight: FontWeight.w700)),
            const SizedBox(height: 3),
            if (bet.profit != null)
              Text(
                '${bet.profit! >= 0 ? '+' : ''}${_formatAmount(bet.profit!)}',
                style: TextStyle(
                  color: bet.profit! >= 0 ? AppColors.success : AppColors.error,
                  fontSize: 12, fontWeight: FontWeight.w700))
            else
              Text('→ ${_formatAmount(bet.potentialGain)}',
                style: TextStyle(color: context.cl.textM, fontSize: 11)),
          ]),
        ]),
      ),
    );
  }
}

// ── Vue setup ─────────────────────────────────────────────────────────────────
class _SetupView extends StatelessWidget {
  final VoidCallback onSetup;
  const _SetupView({required this.onSetup});

  @override
  Widget build(BuildContext context) {
    return SafeArea(child: Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Row(children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.success, Color(0xFF34D399)]),
              borderRadius: BorderRadius.circular(9)),
            child: const Icon(Icons.account_balance_wallet_rounded,
                color: Colors.white, size: 17)),
          const SizedBox(width: 10),
          RichText(text: TextSpan(
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700,
                color: context.cl.textP),
            children: const [
              TextSpan(text: 'Bank'),
              TextSpan(text: 'roll', style: TextStyle(color: AppColors.success)),
            ],
          )),
        ]),
      ),
      Expanded(child: Center(child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 90, height: 90,
            decoration: BoxDecoration(
              color:  AppColors.success.withValues(alpha: 0.1),
              shape:  BoxShape.circle,
              border: Border.all(color: AppColors.success.withValues(alpha: 0.3))),
            child: const Icon(Icons.savings_rounded,
                color: AppColors.success, size: 44)),
          const SizedBox(height: 24),
          Text('Configure ton bankroll', style: TextStyle(
              color: context.cl.textP, fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Text(
            'Définis ton budget de référence pour que PronoWin calcule automatiquement les mises optimales selon la discipline bankroll.',
            style: TextStyle(color: context.cl.textS, fontSize: 14, height: 1.55),
            textAlign: TextAlign.center),
          const SizedBox(height: 32),
          _features(context),
          const SizedBox(height: 32),
          GestureDetector(
            onTap: onSetup,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.success, Color(0xFF059669)]),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(
                  color: AppColors.success.withValues(alpha: 0.4),
                  blurRadius: 16, offset: const Offset(0, 6))]),
              child: const Center(child: Text('Définir mon budget',
                style: TextStyle(color: Colors.white, fontSize: 16,
                    fontWeight: FontWeight.w700))),
            ),
          ),
        ]).animate().fadeIn(duration: 400.ms)
          .scale(begin: const Offset(0.9, 0.9), duration: 400.ms,
              curve: Curves.easeOutCubic),
      ))),
    ]));
  }

  Widget _features(BuildContext context) {
    const items = [
      (Icons.bolt_rounded,       'Mises calculées selon ton solde et la confiance'),
      (Icons.auto_graph_rounded, 'Suivi du ROI et taux de réussite en temps réel'),
      (Icons.update_rounded,     'Solde mis à jour automatiquement à chaque résultat'),
      (Icons.shield_rounded,     'Rappel de discipline après chaque mise confirmée'),
    ];
    return Column(children: items.map((i) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(children: [
        Icon(i.$1, color: AppColors.success, size: 18),
        const SizedBox(width: 12),
        Expanded(child: Text(i.$2,
          style: TextStyle(color: context.cl.textS, fontSize: 13))),
      ]),
    )).toList());
  }
}

// ── Bottom sheet budget ───────────────────────────────────────────────────────
class _BudgetSheet extends ConsumerStatefulWidget {
  final BankrollData? existing;
  const _BudgetSheet({this.existing});
  @override
  ConsumerState<_BudgetSheet> createState() => _BudgetSheetState();
}

class _BudgetSheetState extends ConsumerState<_BudgetSheet> {
  final _ctrl    = TextEditingController();
  String _currency = 'XOF';
  bool   _loading  = false;
  String? _error;

  static const _currencies = ['XOF', 'XAF', 'GNF', 'EUR'];

  // Presets adaptés à la devise
  List<int> get _presets => switch (_currency) {
    'EUR' => [10, 25, 50, 100, 250],
    'GNF' => [50000, 100000, 250000, 500000, 1000000],
    _     => [5000, 10000, 25000, 50000, 100000],
  };

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      _ctrl.text = widget.existing!.totalBudget.toStringAsFixed(0);
      _currency  = widget.existing!.currency;
    }
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _save() async {
    final amount = double.tryParse(_ctrl.text.replaceAll(' ', ''));
    if (amount == null || amount < 100) {
      setState(() => _error = 'Entrez un montant valide (min 100)');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final dio = ref.read(dioProvider);
      await dio.post('/bankroll/budget',
          data: {'total_budget': amount, 'currency': _currency});
      if (!mounted) return;
      ref.invalidate(bankrollProvider);
      Navigator.pop(context);
    } catch (e) {
      setState(() { _error = 'Erreur : $e'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color:  context.cl.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
      padding: EdgeInsets.fromLTRB(20, 16, 20,
          MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 40, height: 4,
          decoration: BoxDecoration(
            color: context.cl.border,
            borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 18),

        Text(widget.existing == null ? 'Définir ton budget' : 'Modifier le budget',
          style: TextStyle(color: context.cl.textP, fontSize: 17,
              fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text('Ce montant sert de référence pour calculer les mises suggérées.',
          style: TextStyle(color: context.cl.textM, fontSize: 12),
          textAlign: TextAlign.center),

        const SizedBox(height: 20),

        // Devise d'abord pour adapter les presets
        Row(children: [
          Text('Devise :', style: TextStyle(color: context.cl.textM, fontSize: 13)),
          const SizedBox(width: 12),
          ..._currencies.map((c) => GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() { _currency = c; _ctrl.clear(); });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color:  _currency == c
                    ? AppColors.success.withValues(alpha: 0.15)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _currency == c ? AppColors.success : context.cl.border,
                  width: 0.8)),
              child: Text(c, style: TextStyle(
                color:      _currency == c ? AppColors.success : context.cl.textM,
                fontSize:   12,
                fontWeight: _currency == c ? FontWeight.w700 : FontWeight.w400)),
            ),
          )),
        ]),

        const SizedBox(height: 14),

        // Montant
        TextField(
          controller:   _ctrl,
          keyboardType: TextInputType.number,
          style:        TextStyle(color: context.cl.textP, fontSize: 18,
              fontWeight: FontWeight.w700),
          decoration: InputDecoration(
            hintText:  _currency == 'EUR' ? 'Ex: 50' : 'Ex: 50 000',
            hintStyle: TextStyle(color: context.cl.textM, fontWeight: FontWeight.w400),
            prefixIcon: Icon(Icons.account_balance_wallet_rounded,
                color: AppColors.success, size: 20),
            suffixText:  _currency,
            suffixStyle: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w700),
            filled: true, fillColor: context.cl.bg,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: context.cl.border)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.success, width: 1.5)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: context.cl.border)),
          ),
        ),

        const SizedBox(height: 12),

        // Presets adaptés à la devise
        Wrap(spacing: 8, runSpacing: 6, children: _presets.map((p) => GestureDetector(
          onTap: () => setState(() => _ctrl.text = '$p'),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color:  AppColors.success.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.success.withValues(alpha: 0.3))),
            child: Text(_formatAmount(p.toDouble()),
              style: const TextStyle(color: AppColors.success, fontSize: 12,
                  fontWeight: FontWeight.w600)),
          ),
        )).toList()),

        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 12)),
        ],

        const SizedBox(height: 20),

        GestureDetector(
          onTap: _loading ? null : _save,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: double.infinity, height: 52,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [AppColors.success, Color(0xFF059669)]),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(
                color: AppColors.success.withValues(alpha: 0.35),
                blurRadius: 12, offset: const Offset(0, 5))]),
            child: Center(child: _loading
                ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                : const Text('Enregistrer', style: TextStyle(
                    color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700))),
          ),
        ),
      ]),
    );
  }
}

// ── Shimmer ───────────────────────────────────────────────────────────────────
class _BankrollShimmer extends StatefulWidget {
  const _BankrollShimmer();
  @override
  State<_BankrollShimmer> createState() => _BankrollShimmerState();
}
class _BankrollShimmerState extends State<_BankrollShimmer>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _anim;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: 900.ms)..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.3, end: 0.7)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _anim,
    builder: (_, _) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 60, 16, 0),
      child: Column(children: [
        Container(
          height: 140,
          decoration: BoxDecoration(
            color: context.cl.surface.withValues(alpha: _anim.value),
            borderRadius: BorderRadius.circular(20))),
        const SizedBox(height: 16),
        Container(
          height: 120,
          decoration: BoxDecoration(
            color: context.cl.surface.withValues(alpha: _anim.value),
            borderRadius: BorderRadius.circular(16))),
        const SizedBox(height: 16),
        Row(children: List.generate(3, (_) => Expanded(child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 5),
          height: 80,
          decoration: BoxDecoration(
            color: context.cl.surface.withValues(alpha: _anim.value),
            borderRadius: BorderRadius.circular(14)))))),
      ]),
    ),
  );
}

// ── Error ─────────────────────────────────────────────────────────────────────
class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorState({required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(child: Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Icons.wifi_off_rounded, color: context.cl.textM, size: 42),
      const SizedBox(height: 12),
      Text('Impossible de charger', style: TextStyle(color: context.cl.textP,
          fontWeight: FontWeight.w700)),
      const SizedBox(height: 16),
      TextButton(onPressed: onRetry,
          child: const Text('Réessayer', style: TextStyle(color: AppColors.success))),
    ],
  ));
}

// ── Helpers ───────────────────────────────────────────────────────────────────
String _formatAmount(double amount) {
  if (amount.abs() >= 1000) {
    final s = amount.abs().toStringAsFixed(0);
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
      buf.write(s[i]);
    }
    return amount < 0 ? '-${buf.toString()}' : buf.toString();
  }
  return amount.toStringAsFixed(0);
}

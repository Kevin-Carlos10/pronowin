import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../providers/compte_provider.dart';

class StatsPage extends ConsumerWidget {
  const StatsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(userStatsProvider);

    return Scaffold(
      backgroundColor: context.cl.bg,
      appBar: AppBar(
        backgroundColor: context.cl.bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Mes statistiques',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
      ),
      body: statsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error:   (e, _) => Center(child: Text('Erreur : $e')),
        data:    (stats) => _StatsBody(stats: stats),
      ),
    );
  }
}

// ─── Corps principal ──────────────────────────────────────────────────────────
class _StatsBody extends StatelessWidget {
  final Map<String, dynamic> stats;
  const _StatsBody({required this.stats});

  @override
  Widget build(BuildContext context) {
    final suivis      = (stats['pronostics_suivis'] as num?)?.toInt()  ?? 0;
    final gagnes      = (stats['paris_gagnes']      as num?)?.toInt()  ?? 0;
    final perdus      = (stats['paris_perdus']      as num?)?.toInt()  ?? 0;
    final taux        = (stats['taux_reussite']     as num?)?.toDouble() ?? 0.0;
    final serie       = (stats['serie_gagnante']    as num?)?.toInt()  ?? 0;
    final bestSerie   = (stats['meilleure_serie']   as num?)?.toInt()  ?? 0;
    final roi         = (stats['roi']               as num?)?.toDouble() ?? 0.0;
    final profitNet   = (stats['profit_net']        as num?)?.toInt()  ?? 0;
    final totalMise   = (stats['total_mise']        as num?)?.toInt()  ?? 0;
    final bestOdds    = (stats['meilleure_cote']    as num?)?.toDouble() ?? 0.0;
    final history     = (stats['bankroll_history']  as List<dynamic>?) ?? [];
    final leagues     = (stats['league_stats']      as List<dynamic>?) ?? [];

    return RefreshIndicator(
      color: const Color(0xFFFF6B35),
      onRefresh: () async {},
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // ── KPIs top ─────────────────────────────────────────────────────
          _SectionTitle('PERFORMANCE GLOBALE'),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _KpiCard(
              label: 'Taux de réussite',
              value: '${taux.toStringAsFixed(0)}%',
              icon: Icons.percent_rounded,
              color: taux >= 60 ? Colors.green : taux >= 45 ? Colors.orange : Colors.red,
              sub: '$gagnes victoires / $perdus défaites',
            )),
            const SizedBox(width: 10),
            Expanded(child: _KpiCard(
              label: 'ROI',
              value: '${roi >= 0 ? '+' : ''}${roi.toStringAsFixed(1)}%',
              icon: Icons.trending_up_rounded,
              color: roi >= 0 ? Colors.green : Colors.red,
              sub: 'Retour sur investissement',
            )),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _KpiCard(
              label: 'Profit net',
              value: '${profitNet >= 0 ? '+' : ''}${_fmt(profitNet)} F',
              icon: Icons.account_balance_wallet_rounded,
              color: profitNet >= 0 ? Colors.green : Colors.red,
              sub: 'Misé : ${_fmt(totalMise)} F',
            )),
            const SizedBox(width: 10),
            Expanded(child: _KpiCard(
              label: 'Meilleure cote',
              value: bestOdds > 0 ? bestOdds.toStringAsFixed(2) : '–',
              icon: Icons.star_rounded,
              color: const Color(0xFFFF6B35),
              sub: 'Cote gagnée la + haute',
            )),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _KpiCard(
              label: 'Série actuelle',
              value: serie > 0 ? '🔥 $serie' : '$serie',
              icon: Icons.local_fire_department_rounded,
              color: serie >= 5 ? Colors.orange : const Color(0xFFFF6B35),
              sub: 'Record : $bestSerie victoires',
            )),
            const SizedBox(width: 10),
            Expanded(child: _KpiCard(
              label: 'Paris suivis',
              value: '$suivis',
              icon: Icons.sports_score_rounded,
              color: const Color(0xFF6C63FF),
              sub: '${suivis - gagnes - perdus} en attente',
            )),
          ]),

          // ── Graphe bankroll ───────────────────────────────────────────────
          if (history.isNotEmpty) ...[
            const SizedBox(height: 24),
            _SectionTitle('ÉVOLUTION BANKROLL (30 JOURS)'),
            const SizedBox(height: 12),
            _BankrollChart(history: history),
          ],

          // ── Stats par ligue ───────────────────────────────────────────────
          if (leagues.isNotEmpty) ...[
            const SizedBox(height: 24),
            _SectionTitle('PERFORMANCE PAR COMPÉTITION'),
            const SizedBox(height: 12),
            ...leagues.map((l) => _LeagueRow(league: l as Map<String, dynamic>)),
          ],
        ],
      ),
    );
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────
String _fmt(int v) {
  final abs = v.abs();
  if (abs >= 1000000) return '${(abs / 1000000).toStringAsFixed(1)}M';
  if (abs >= 1000)    return '${(abs / 1000).toStringAsFixed(0)}K';
  return abs.toString();
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      fontSize: 11, fontWeight: FontWeight.w700,
      color: context.cl.textS, letterSpacing: 1.1),
  );
}

// ─── KPI Card ─────────────────────────────────────────────────────────────────
class _KpiCard extends StatelessWidget {
  final String label, value, sub;
  final IconData icon;
  final Color color;
  const _KpiCard({required this.label, required this.value, required this.icon,
      required this.color, required this.sub});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cl.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.cl.border, width: 0.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Expanded(child: Text(label,
              style: TextStyle(fontSize: 11, color: context.cl.textS),
              overflow: TextOverflow.ellipsis)),
        ]),
        const SizedBox(height: 8),
        Text(value, style: TextStyle(
            fontSize: 22, fontWeight: FontWeight.w800, color: color)),
        const SizedBox(height: 4),
        Text(sub, style: TextStyle(fontSize: 10, color: context.cl.textS),
            overflow: TextOverflow.ellipsis),
      ]),
    );
  }
}

// ─── Graphe évolution bankroll ────────────────────────────────────────────────
class _BankrollChart extends StatelessWidget {
  final List<dynamic> history;
  const _BankrollChart({required this.history});

  @override
  Widget build(BuildContext context) {
    final spots = <FlSpot>[];
    for (int i = 0; i < history.length; i++) {
      final bal = (history[i]['balance'] as num).toDouble();
      spots.add(FlSpot(i.toDouble(), bal));
    }
    if (spots.isEmpty) return const SizedBox.shrink();

    final minY = spots.map((s) => s.y).reduce((a, b) => a < b ? a : b);
    final maxY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    final pad  = (maxY - minY) * 0.15;
    final isPos = spots.last.y >= spots.first.y;
    final lineColor = isPos ? Colors.green : Colors.red;

    return Container(
      height: 200,
      padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
      decoration: BoxDecoration(
        color: context.cl.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.cl.border, width: 0.5),
      ),
      child: LineChart(LineChartData(
        minY: minY - pad,
        maxY: maxY + pad,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => FlLine(
              color: context.cl.border, strokeWidth: 0.5),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 52,
            getTitlesWidget: (v, _) => Text(
              '${_fmt(v.toInt())} F',
              style: TextStyle(fontSize: 9, color: context.cl.textS),
            ),
          )),
          bottomTitles: AxisTitles(sideTitles: SideTitles(
            showTitles: true,
            interval: 10,
            getTitlesWidget: (v, _) {
              final idx = v.toInt();
              if (idx < 0 || idx >= history.length) return const SizedBox.shrink();
              final date = history[idx]['date'] as String;
              final parts = date.split('-');
              return Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('${parts[2]}/${parts[1]}',
                    style: TextStyle(fontSize: 9, color: context.cl.textS)),
              );
            },
          )),
          rightTitles:  AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:    AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        lineBarsData: [LineChartBarData(
          spots: spots,
          isCurved: true,
          curveSmoothness: 0.3,
          color: lineColor,
          barWidth: 2.5,
          dotData: FlDotData(show: false),
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              colors: [lineColor.withValues(alpha: 0.25), lineColor.withValues(alpha: 0.0)],
              begin: Alignment.topCenter,
              end:   Alignment.bottomCenter,
            ),
          ),
        )],
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (spots) => spots.map((s) => LineTooltipItem(
              '${_fmt(s.y.toInt())} F',
              const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12),
            )).toList(),
          ),
        ),
      )),
    );
  }
}

// ─── Ligne ligue ──────────────────────────────────────────────────────────────
class _LeagueRow extends StatelessWidget {
  final Map<String, dynamic> league;
  const _LeagueRow({required this.league});

  @override
  Widget build(BuildContext context) {
    final name  = league['name']  as String? ?? '–';
    final total = (league['total'] as num?)?.toInt() ?? 0;
    final wins  = (league['wins']  as num?)?.toInt() ?? 0;
    final taux  = (league['taux']  as num?)?.toInt() ?? 0;
    final color = taux >= 60 ? Colors.green : taux >= 45 ? Colors.orange : Colors.red;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: context.cl.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.cl.border, width: 0.5),
      ),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text('$total paris · $wins victoires',
              style: TextStyle(fontSize: 11, color: context.cl.textS)),
        ])),
        const SizedBox(width: 12),
        // Barre de progression
        SizedBox(width: 80, child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('$taux%', style: TextStyle(
              fontWeight: FontWeight.w700, fontSize: 14, color: color)),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: taux / 100,
              backgroundColor: context.cl.border,
              color: color,
              minHeight: 5,
            ),
          ),
        ])),
      ]),
    );
  }
}

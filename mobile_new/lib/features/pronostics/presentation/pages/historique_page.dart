import 'dart:convert';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../../../../core/cache/cache_service.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../core/theme/app_theme.dart';

// ─── Filtres ──────────────────────────────────────────────────────────────────
enum _ResultFilter { all, win, loss, pending }
enum _PeriodFilter { week7, days30, days90 }

extension _PeriodExt on _PeriodFilter {
  int get days => switch (this) {
    _PeriodFilter.week7  => 7,
    _PeriodFilter.days30 => 30,
    _PeriodFilter.days90 => 90,
  };
  String get label => switch (this) {
    _PeriodFilter.week7  => '7 jours',
    _PeriodFilter.days30 => '30 jours',
    _PeriodFilter.days90 => '90 jours',
  };
}

// ─── Providers ────────────────────────────────────────────────────────────────
final _periodProvider = StateProvider.autoDispose<_PeriodFilter>(
  (ref) => _PeriodFilter.days30,
);
final _resultFilterProvider = StateProvider.autoDispose<_ResultFilter>(
  (ref) => _ResultFilter.all,
);

final historiqueProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, int>((ref, days) async {
  final cacheKey = 'pronostics_history_$days';
  try {
    final r    = await ref.read(dioProvider).get('/pronostics/history',
        queryParameters: {'days': days});
    final data = (r.data as List).cast<Map<String, dynamic>>();
    await CacheService.save(cacheKey, data);
    return data;
  } catch (_) {
    return await CacheService.loadStale<List<Map<String, dynamic>>>(
        cacheKey, (d) => (d as List).cast<Map<String, dynamic>>()) ?? [];
  }
});

// ─── Page ─────────────────────────────────────────────────────────────────────
class HistoriquePage extends ConsumerWidget {
  const HistoriquePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(_periodProvider);
    final async  = ref.watch(historiqueProvider(period.days));
    final filter = ref.watch(_resultFilterProvider);

    return Scaffold(
      backgroundColor: context.cl.bg,
      appBar: AppBar(
        backgroundColor: context.cl.bg,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: context.cl.textP),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('Historique', style: TextStyle(
          color: context.cl.textP, fontSize: 17, fontWeight: FontWeight.w700)),
        centerTitle: true,
        actions: [
          async.whenOrNull(
            data: (entries) => IconButton(
              icon: Icon(Icons.download_rounded, color: context.cl.textS, size: 22),
              tooltip: 'Exporter CSV',
              onPressed: () => _exportCsv(context, entries, period),
            ),
          ) ?? const SizedBox.shrink(),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
        error:   (_, __) => const _ErrorView(),
        data: (all) {
          final entries = _applyFilter(all, filter);
          return Column(
            children: [
              // Filtres période
              _PeriodBar(selected: period,
                onTap: (p) => ref.read(_periodProvider.notifier).state = p),
              // Filtres résultat
              _ResultBar(selected: filter, all: all,
                onTap: (f) => ref.read(_resultFilterProvider.notifier).state = f),
              // Corps
              Expanded(
                child: entries.isEmpty
                  ? const _EmptyView()
                  : _HistoriqueBody(entries: entries, allEntries: all),
              ),
            ],
          );
        },
      ),
    );
  }

  static List<Map<String, dynamic>> _applyFilter(
      List<Map<String, dynamic>> all, _ResultFilter f) => switch (f) {
    _ResultFilter.all     => all,
    _ResultFilter.win     => all.where((e) => e['result'] == 'WIN').toList(),
    _ResultFilter.loss    => all.where((e) => e['result'] == 'LOSS').toList(),
    _ResultFilter.pending => all.where((e) => e['result'] == null).toList(),
  };

  static void _exportCsv(BuildContext context,
      List<Map<String, dynamic>> entries, _PeriodFilter period) {
    final buf = StringBuffer();
    buf.writeln('Date,Match,Ligue,Prédiction,Cote,Résultat');
    for (final e in entries) {
      final match  = e['match'] as Map<String, dynamic>? ?? {};
      final date   = match['matchDate'] as String? ?? '';
      final home   = match['homeTeam']  as String? ?? '';
      final away   = match['awayTeam']  as String? ?? '';
      final league = match['league']    as String? ?? '';
      final pred   = e['predictionLabel'] as String? ?? '';
      final odds   = (e['oddsRecommended'] as num?)?.toStringAsFixed(2) ?? '';
      final result = e['result'] as String? ?? 'EN ATTENTE';
      buf.writeln('"$date","$home vs $away","$league","$pred",$odds,$result');
    }
    final bytes = utf8.encode(buf.toString());
    final file = XFile.fromData(
      bytes,
      name:     'pronowin_historique_${period.days}j.csv',
      mimeType: 'text/csv',
    );
    Share.shareXFiles(
      [file],
      text: 'Historique PronoWin — ${period.label}',
    );
  }
}

// ─── Barre période ────────────────────────────────────────────────────────────
class _PeriodBar extends StatelessWidget {
  final _PeriodFilter selected;
  final void Function(_PeriodFilter) onTap;
  const _PeriodBar({required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: _PeriodFilter.values.map((p) {
          final active = p == selected;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => onTap(p),
              child: AnimatedContainer(
                duration: 220.ms,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color:  active ? AppColors.primary : context.cl.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: active
                      ? AppColors.primary
                      : context.cl.border,
                    width: 0.8)),
                child: Text(p.label, style: TextStyle(
                  color: active ? Colors.white : context.cl.textS,
                  fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─── Barre filtre résultat ────────────────────────────────────────────────────
class _ResultBar extends StatelessWidget {
  final _ResultFilter selected;
  final List<Map<String, dynamic>> all;
  final void Function(_ResultFilter) onTap;
  const _ResultBar({required this.selected, required this.all, required this.onTap});

  @override
  Widget build(BuildContext context) {
    int count(_ResultFilter f) => switch (f) {
      _ResultFilter.all     => all.length,
      _ResultFilter.win     => all.where((e) => e['result'] == 'WIN').length,
      _ResultFilter.loss    => all.where((e) => e['result'] == 'LOSS').length,
      _ResultFilter.pending => all.where((e) => e['result'] == null).length,
    };

    final specs = [
      (_ResultFilter.all,     'Tous',        context.cl.textP,   context.cl.border),
      (_ResultFilter.win,     'WIN',          AppColors.success,  AppColors.success),
      (_ResultFilter.loss,    'LOSS',         AppColors.error,    AppColors.error),
      (_ResultFilter.pending, 'En attente',   AppColors.warning,  AppColors.warning),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Row(
        children: specs.map((s) {
          final (f, label, color, borderColor) = s;
          final active = f == selected;
          final n      = count(f);
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => onTap(f),
              child: AnimatedContainer(
                duration: 220.ms,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color:  active ? color.withValues(alpha: 0.12) : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: active ? borderColor : context.cl.border,
                    width: active ? 1.2 : 0.8)),
                child: Row(children: [
                  Text(label, style: TextStyle(
                    color: active ? color : context.cl.textS,
                    fontSize: 11, fontWeight: FontWeight.w700)),
                  const SizedBox(width: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: active ? color.withValues(alpha: 0.15) : context.cl.surfaceD,
                      borderRadius: BorderRadius.circular(8)),
                    child: Text('$n', style: TextStyle(
                      color: active ? color : context.cl.textM,
                      fontSize: 10, fontWeight: FontWeight.w800))),
                ]),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─── Corps principal ──────────────────────────────────────────────────────────
class _HistoriqueBody extends StatelessWidget {
  final List<Map<String, dynamic>> entries;
  final List<Map<String, dynamic>> allEntries; // pour le graphe (non filtré)
  const _HistoriqueBody({required this.entries, required this.allEntries});

  @override
  Widget build(BuildContext context) {
    final won   = allEntries.where((e) => e['result'] == 'WIN').length;
    final total = allEntries.length;
    final taux  = total > 0 ? (won / total * 100).round() : 0;
    int serie   = 0;
    for (final e in allEntries) {
      if (e['result'] == 'WIN') serie++; else break;
    }

    // Grouper par semaine
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final e in entries) {
      final date  = DateTime.tryParse(e['match']?['matchDate'] as String? ?? '') ?? DateTime.now();
      grouped.putIfAbsent(_weekLabel(date), () => []).add(e);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      children: [
        _StatsHeader(won: won, total: total, taux: taux, serie: serie)
          .animate().fadeIn(duration: 350.ms).slideY(begin: -0.04, end: 0),
        const SizedBox(height: 16),

        // ── Graphe de performance ────────────────────────────────────────────
        if (allEntries.isNotEmpty) ...[
          _PerformanceChart(entries: allEntries)
            .animate().fadeIn(duration: 400.ms, delay: 100.ms),
          const SizedBox(height: 20),
        ],

        // ── Liste filtrée ────────────────────────────────────────────────────
        for (final week in grouped.entries) ...[
          _WeekHeader(label: week.key, entries: week.value),
          const SizedBox(height: 8),
          for (final (i, e) in week.value.indexed)
            _EntryCard(entry: e)
              .animate(delay: Duration(milliseconds: i * 45))
              .fadeIn(duration: 250.ms)
              .slideY(begin: 0.05, end: 0, curve: Curves.easeOutCubic),
          const SizedBox(height: 20),
        ],
      ],
    );
  }

  static String _weekLabel(DateTime d) {
    final diff = DateTime.now().difference(d).inDays;
    if (diff < 7)  return 'Cette semaine';
    if (diff < 14) return 'La semaine dernière';
    return 'Il y a ${(diff / 7).ceil()} semaines';
  }
}

// ─── Graphe de performance ─────────────────────────────────────────────────
class _PerformanceChart extends StatelessWidget {
  final List<Map<String, dynamic>> entries;
  const _PerformanceChart({required this.entries});

  @override
  Widget build(BuildContext context) {
    // Construire les points : % réussite cumulé au fil du temps
    // On trie du plus ancien au plus récent
    final settled = entries
        .where((e) => e['result'] != null)
        .toList()
      ..sort((a, b) {
        final da = DateTime.tryParse(a['match']?['matchDate'] as String? ?? '') ?? DateTime(2000);
        final db = DateTime.tryParse(b['match']?['matchDate'] as String? ?? '') ?? DateTime(2000);
        return da.compareTo(db);
      });

    if (settled.length < 2) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.cl.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.cl.border, width: 0.8)),
        child: Center(child: Text('Graphe disponible après 2+ résultats',
          style: TextStyle(color: context.cl.textM, fontSize: 12))),
      );
    }

    int wins = 0;
    final spots = <FlSpot>[];
    for (int i = 0; i < settled.length; i++) {
      if (settled[i]['result'] == 'WIN') wins++;
      spots.add(FlSpot(i.toDouble(), wins / (i + 1) * 100));
    }

    final maxY = 100.0;
    final lastPct = spots.last.y;
    final color   = lastPct >= 60 ? AppColors.success
                  : lastPct >= 45 ? AppColors.warning
                  : AppColors.error;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 16, 16, 12),
      decoration: BoxDecoration(
        color: context.cl.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.cl.border, width: 0.8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.show_chart_rounded, color: color, size: 16),
          const SizedBox(width: 6),
          Text('Courbe de réussite', style: TextStyle(
            color: context.cl.textP, fontSize: 13, fontWeight: FontWeight.w700)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10)),
            child: Text('${lastPct.toStringAsFixed(0)}%', style: TextStyle(
              color: color, fontSize: 12, fontWeight: FontWeight.w800))),
        ]),
        const SizedBox(height: 16),
        SizedBox(
          height: 120,
          child: LineChart(
            LineChartData(
              minY: 0, maxY: maxY,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: 25,
                getDrawingHorizontalLine: (_) => FlLine(
                  color: context.cl.border, strokeWidth: 0.6),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 32,
                    interval: 25,
                    getTitlesWidget: (v, _) => Text(
                      '${v.toInt()}%',
                      style: TextStyle(color: context.cl.textM, fontSize: 9)),
                  ),
                ),
                rightTitles:  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles:    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  curveSmoothness: 0.3,
                  color: color,
                  barWidth: 2.5,
                  dotData: FlDotData(
                    show: true,
                    getDotPainter: (spot, _, __, ___) {
                      final isLast = spot.x == spots.last.x;
                      return FlDotCirclePainter(
                        radius: isLast ? 5 : 0,
                        color: color,
                        strokeWidth: isLast ? 2 : 0,
                        strokeColor: context.cl.surface,
                      );
                    },
                  ),
                  belowBarData: BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      colors: [
                        color.withValues(alpha: 0.20),
                        color.withValues(alpha: 0.00),
                      ],
                      begin: Alignment.topCenter,
                      end:   Alignment.bottomCenter,
                    ),
                  ),
                ),
                // Ligne de référence 50%
                LineChartBarData(
                  spots: [FlSpot(0, 50), FlSpot((settled.length - 1).toDouble(), 50)],
                  isCurved: false,
                  color: context.cl.textM.withValues(alpha: 0.35),
                  barWidth: 1,
                  dotData: const FlDotData(show: false),
                  dashArray: [4, 4],
                ),
              ],
            ),
          ),
        ),
      ]),
    );
  }
}

// ─── Header stats ─────────────────────────────────────────────────────────────
class _StatsHeader extends StatelessWidget {
  final int won, total, taux, serie;
  const _StatsHeader({required this.won, required this.total,
    required this.taux, required this.serie});

  @override
  Widget build(BuildContext context) {
    final lost  = total - won;
    final color = taux >= 60 ? AppColors.success
                : taux >= 45 ? AppColors.warning
                : AppColors.error;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            context.isDark ? const Color(0xFF151B2E) : Colors.white,
            context.isDark ? const Color(0xFF0D1220) : const Color(0xFFF8FAFC),
          ],
          begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2))),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          _BigStat(label: 'Total',    value: '$total', color: context.cl.textP),
          _VDivider(),
          _BigStat(label: 'Réussite', value: '$taux%', color: color),
          _VDivider(),
          _BigStat(label: 'Série',    value: '+$serie', color: AppColors.warning),
        ]),
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Row(children: [
            if (won  > 0) Expanded(flex: won,  child: Container(height: 8, color: AppColors.success)),
            if (lost > 0) Expanded(flex: lost, child: Container(height: 8,
              color: AppColors.error.withValues(alpha: 0.6))),
          ]),
        ),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          _LegendDot(color: AppColors.success, label: '$won victoires'),
          _LegendDot(color: AppColors.error.withValues(alpha: 0.6), label: '$lost défaites'),
        ]),
      ]),
    );
  }
}

class _BigStat extends StatelessWidget {
  final String label, value; final Color color;
  const _BigStat({required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) => Column(children: [
    Text(value, style: TextStyle(color: color, fontSize: 26, fontWeight: FontWeight.w900)),
    const SizedBox(height: 2),
    Text(label, style: TextStyle(color: context.cl.textM, fontSize: 11)),
  ]);
}

class _VDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
    Container(width: 0.5, height: 36, color: context.cl.border);
}

class _LegendDot extends StatelessWidget {
  final Color color; final String label;
  const _LegendDot({required this.color, required this.label});
  @override
  Widget build(BuildContext context) => Row(children: [
    Container(width: 8, height: 8, decoration: BoxDecoration(
      color: color, borderRadius: BorderRadius.circular(2))),
    const SizedBox(width: 4),
    Text(label, style: TextStyle(color: context.cl.textM, fontSize: 11)),
  ]);
}

// ─── En-tête de semaine ───────────────────────────────────────────────────────
class _WeekHeader extends StatelessWidget {
  final String label;
  final List<Map<String, dynamic>> entries;
  const _WeekHeader({required this.label, required this.entries});

  @override
  Widget build(BuildContext context) {
    final won   = entries.where((e) => e['result'] == 'WIN').length;
    final total = entries.length;
    return Row(children: [
      Text(label.toUpperCase(), style: TextStyle(
        color: context.cl.textS, fontSize: 11,
        fontWeight: FontWeight.w700, letterSpacing: 0.8)),
      const Spacer(),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color:  AppColors.success.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.success.withValues(alpha: 0.2))),
        child: Text('$won/$total ✅', style: const TextStyle(
          color: AppColors.success, fontSize: 11, fontWeight: FontWeight.w700))),
    ]);
  }
}

// ─── Carte d'entrée ───────────────────────────────────────────────────────────
class _EntryCard extends StatelessWidget {
  final Map<String, dynamic> entry;
  const _EntryCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final match      = entry['match'] as Map<String, dynamic>? ?? {};
    final result     = entry['result'] as String?;
    final isPending  = result == null;
    final isWin      = result == 'WIN';
    final homeTeam   = match['homeTeam']  as String? ?? '';
    final awayTeam   = match['awayTeam']  as String? ?? '';
    final homeScore  = match['homeScore'] as int?;
    final awayScore  = match['awayScore'] as int?;
    final league     = match['league']    as String? ?? '';
    final date       = DateTime.tryParse(match['matchDate'] as String? ?? '');
    final dateStr    = date != null ? DateFormat('dd/MM', 'fr_FR').format(date) : '';
    final pred       = entry['predictionLabel'] as String? ?? '';
    final odds       = (entry['oddsRecommended'] as num?)?.toDouble() ?? 0.0;

    final resultColor = isPending ? AppColors.warning
                      : isWin    ? AppColors.success
                      : AppColors.error;

    final scoreStr = (homeScore != null && awayScore != null)
      ? '$homeScore – $awayScore'
      : 'vs';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.cl.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: resultColor.withValues(alpha: 0.2), width: 0.8)),
      child: Row(children: [
        // Badge résultat
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color:  resultColor.withValues(alpha: 0.12),
            shape:  BoxShape.circle),
          child: Icon(
            isPending ? Icons.schedule_rounded
            : isWin  ? Icons.check_rounded
            : Icons.close_rounded,
            color: resultColor, size: 20)),
        const SizedBox(width: 12),

        // Infos
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$homeTeam  $scoreStr  $awayTeam',
            style: TextStyle(color: context.cl.textP,
              fontSize: 13, fontWeight: FontWeight.w600),
            maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 3),
          Row(children: [
            Flexible(child: Text(league, style: TextStyle(
              color: context.cl.textM, fontSize: 11),
              maxLines: 1, overflow: TextOverflow.ellipsis)),
            if (dateStr.isNotEmpty)
              Text('  ·  $dateStr', style: TextStyle(
                color: context.cl.textM, fontSize: 11)),
          ]),
          const SizedBox(height: 5),
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6)),
              child: Text(pred, style: const TextStyle(
                color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w700))),
            const SizedBox(width: 6),
            Text('@ ${odds.toStringAsFixed(2)}',
              style: TextStyle(color: context.cl.textS, fontSize: 11)),
          ]),
        ])),

        // Label
        Text(
          isPending ? 'WAIT' : (isWin ? 'WIN' : 'LOSS'),
          style: TextStyle(color: resultColor,
            fontSize: 11, fontWeight: FontWeight.w800)),
      ]),
    );
  }
}

// ─── États vides / erreur ─────────────────────────────────────────────────────
class _EmptyView extends StatelessWidget {
  const _EmptyView();
  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.history_rounded, size: 56, color: context.cl.textM),
      const SizedBox(height: 16),
      Text('Aucun résultat pour ce filtre',
        style: TextStyle(color: context.cl.textS, fontSize: 15,
          fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      Text('Essaie un autre filtre ou une période plus longue.',
        style: TextStyle(color: context.cl.textM, fontSize: 13),
        textAlign: TextAlign.center),
    ]),
  );
}

class _ErrorView extends StatelessWidget {
  const _ErrorView();
  @override
  Widget build(BuildContext context) => Center(
    child: Text("Impossible de charger l'historique",
      style: TextStyle(color: context.cl.textS)));
}

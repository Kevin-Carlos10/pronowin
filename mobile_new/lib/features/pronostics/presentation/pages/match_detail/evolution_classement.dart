// Évolution au classement — 7 novembre 2026.
part of '../match_detail_page.dart';

@visibleForTesting
Widget evolutionClassementSeule(MatchEntity match) => _EvolutionClassement(match: match);

/// Les positions des deux équipes après chaque journée, en courbes (le
/// « Tracker de classement » de Sofascore). La première place est en haut.
///
/// Le serveur reconstitue le classement à partir des résultats de la saison ;
/// à égalité parfaite, deux équipes peuvent être inversées par rapport au
/// classement officiel (voir `evolution_classement.service.ts`). Absente pour
/// une coupe, ou avant la deuxième journée : une seule journée ne trace rien.
class _EvolutionClassement extends ConsumerWidget {
  final MatchEntity match;
  const _EvolutionClassement({required this.match});

  static const _couleurDomicile = AppColors.primary;
  static const _couleurExterieur = Color(0xFF2F7CF6);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final evolution = ref.watch(evolutionClassementProvider(match.id)).valueOrNull;
    if (evolution == null || evolution.journees.length < 2) return const SizedBox.shrink();

    final n = evolution.equipes;
    List<FlSpot> points(int? Function(({int journee, int? domicile, int? exterieur})) rang) => [
      for (final j in evolution.journees)
        if (rang(j) != null) FlSpot(j.journee.toDouble(), -rang(j)!.toDouble()),
    ];
    final dom = points((j) => j.domicile), ext = points((j) => j.exterieur);
    final derniere = evolution.journees.last;
    final intervalle = n > 12 ? 5.0 : 2.0;

    LineChartBarData courbe(List<FlSpot> spots, Color couleur) => LineChartBarData(
      spots: spots,
      isCurved: false,
      color: couleur,
      barWidth: 2.4,
      dotData: FlDotData(
        show: true,
        getDotPainter: (spot, _, _, _) => FlDotCirclePainter(
          radius: spot.x == spots.last.x ? 4.5 : 2,
          color: couleur, strokeWidth: spot.x == spots.last.x ? 2 : 0,
          strokeColor: context.cl.surface),
      ),
    );

    Widget legende(String nom, String? logo, int? rang, Color couleur) => Expanded(
      child: Row(children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: couleur, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        TeamLogoWidget(url: logo, size: 18),
        const SizedBox(width: 6),
        Flexible(child: Text(nom, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(color: context.cl.textP, fontSize: 13, fontWeight: FontWeight.w600))),
        if (rang != null) ...[
          const SizedBox(width: 6),
          Text(_rang(context, rang),
            style: TextStyle(color: couleur, fontSize: 13, fontWeight: FontWeight.w800)),
        ],
      ]),
    );

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Container(
        key: const Key('evolution-classement'),
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 16, 16, 12),
        decoration: BoxDecoration(
          color: context.cl.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.cl.borderSoft, width: 0.8),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Semantics(header: true, child: Text(tr(context, "Évolution au classement"),
            style: TextStyle(color: context.cl.textP, fontSize: 16, fontWeight: FontWeight.w700))),
          const SizedBox(height: 4),
          Text(tr(context, "Position après chaque journée"),
            style: TextStyle(color: context.cl.textM, fontSize: 12)),
          const SizedBox(height: 12),
          Row(children: [
            legende(match.homeTeam, match.homeTeamLogo, derniere.domicile, _couleurDomicile),
            const SizedBox(width: 10),
            legende(match.awayTeam, match.awayTeamLogo, derniere.exterieur, _couleurExterieur),
          ]),
          const SizedBox(height: 14),
          Semantics(
            label: tr(context, "Après la journée {arg0} : {arg1} {arg2}, {arg3} {arg4}.", [
              derniere.journee,
              match.homeTeam, derniere.domicile == null ? '–' : _rang(context, derniere.domicile!),
              match.awayTeam, derniere.exterieur == null ? '–' : _rang(context, derniere.exterieur!)]),
            child: ExcludeSemantics(child: SizedBox(
              height: 180,
              child: LineChart(LineChartData(
                minY: -n.toDouble() - 0.5, maxY: -0.5,
                minX: evolution.journees.first.journee.toDouble(),
                maxX: derniere.journee.toDouble(),
                lineTouchData: const LineTouchData(enabled: false),
                borderData: FlBorderData(show: false),
                gridData: FlGridData(
                  show: true, drawVerticalLine: false, horizontalInterval: intervalle,
                  getDrawingHorizontalLine: (_) => FlLine(color: context.cl.border, strokeWidth: 0.6)),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(sideTitles: SideTitles(
                    showTitles: true, reservedSize: 26, interval: intervalle,
                    getTitlesWidget: (v, _) {
                      final rang = -v.round();
                      if (rang < 1 || rang > n) return const SizedBox.shrink();
                      return Text('$rang', style: TextStyle(color: context.cl.textM, fontSize: 11));
                    })),
                  bottomTitles: AxisTitles(sideTitles: SideTitles(
                    showTitles: true, reservedSize: 22,
                    interval: evolution.journees.length > 12 ? 5 : 2,
                    getTitlesWidget: (v, _) => Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('J${v.toInt()}', style: TextStyle(color: context.cl.textM, fontSize: 11))))),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                lineBarsData: [courbe(ext, _couleurExterieur), courbe(dom, _couleurDomicile)],
              )),
            )),
          ),
        ]),
      ),
    );
  }
}

/// « 1er », « 2e » ; « 1st », « 2nd », « 3rd », « 4th » en anglais.
String _rang(BuildContext context, int n) {
  if (AppStrings.of(context).locale.languageCode != 'en') return n == 1 ? '1er' : '${n}e';
  final suffixe = (n % 100 >= 11 && n % 100 <= 13) ? 'th'
      : switch (n % 10) { 1 => 'st', 2 => 'nd', 3 => 'rd', _ => 'th' };
  return '$n$suffixe';
}

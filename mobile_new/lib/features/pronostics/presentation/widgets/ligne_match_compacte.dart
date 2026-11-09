import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pronowin/l10n/app_strings.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/team_logo_widget.dart';
import '../../../../shared/providers/favoris_provider.dart';
import '../../../../shared/widgets/suivre_match.dart';
import '../../domain/entities/match_entity.dart';
import 'minute_direct.dart';
import 'eclair_but.dart';

/// Un match sans pronostic, sur une ligne (7 novembre 2026).
///
/// La liste du jour donnait à chaque match la grande carte des pronostics,
/// environ 170 points de haut, avec « Aucune analyse publiée » et le nom de la
/// ligue répétés sous l'en-tête de cette même ligue. Quarante-neuf matchs un
/// samedi : on faisait défiler longtemps pour trouver les sept qui ont un
/// pronostic. Sofascore et FotMob montrent un match par ligne ; la grande carte
/// reste ici aux matchs qui ont un pronostic, ce que l'application vend.
///
/// Les lignes d'une même ligue se posent dans un seul bloc ([BlocLignesMatch]).
class LigneMatchCompacte extends ConsumerWidget {
  final MatchEntity match;
  /// Le jour au-dessus de l'heure, pour une liste qui couvre plusieurs jours
  /// (les prochains matchs des équipes suivies).
  final bool avecDate;
  const LigneMatchCompacte({super.key, required this.match, this.avecDate = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = match;
    final suivi = ref.watch(favorisProvider).valueOrNull?.matchIds.contains(m.id) ?? false;
    final enDirect = m.status == MatchStatus.live;
    final termine = m.status == MatchStatus.finished;
    final avecScore = enDirect || termine;
    final dom = m.homeScore ?? 0, ext = m.awayScore ?? 0;

    final etat = enDirect
        ? libelleMinuteDirect(context, m.elapsed)
        : termine
            ? tr(context, "Terminé")
            : DateFormat('HH:mm').format(m.matchDate);
    final libelle = avecScore
        ? tr(context, "{arg0} {arg1}, {arg2} {arg3}. {arg4}.", [m.homeTeam, dom, m.awayTeam, ext, etat])
        : tr(context, "{arg0} contre {arg1}, à {arg2}.", [m.homeTeam, m.awayTeam,
            avecDate ? '${DateFormat('dd/MM').format(m.matchDate)} $etat' : etat]);

    Widget equipe(String nom, String? logo, int buts, int adverse) {
      final gagne = termine && buts > adverse;
      final perd = termine && buts < adverse;
      return Row(children: [
        TeamLogoWidget(url: logo, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(nom,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: perd ? context.cl.textS : context.cl.textP,
              fontSize: 14,
              fontWeight: gagne ? FontWeight.w700 : FontWeight.w500)),
        ),
        if (avecScore)
          SizedBox(
            width: 22,
            child: Text('$buts',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: enDirect ? context.cl.error : perd ? context.cl.textS : context.cl.textP,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()])),
          ),
      ]);
    }

    // Un but : la ligne s'illumine un instant (eclair_but.dart).
    return EclairBut(
      dom: m.homeScore, ext: m.awayScore, rayon: BorderRadius.zero,
      child: Semantics(
      label: libelle,
      button: true,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          context.push('/pronostics/${m.id}', extra: m);
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 9, 4, 9),
          child: ExcludeSemantics(
            child: Row(children: [
              // L'heure, ou l'état du match.
              SizedBox(
                width: 50,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (avecDate && !enDirect)
                      Text(DateFormat('dd/MM').format(m.matchDate),
                        style: TextStyle(color: context.cl.textM, fontSize: 11, fontWeight: FontWeight.w600)),
                    Text(etat,
                    style: TextStyle(
                      color: enDirect ? context.cl.error : termine ? context.cl.textM : context.cl.textS,
                      fontSize: 12,
                      fontWeight: enDirect ? FontWeight.w700 : FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()])),
                  ]),
                ),
              ),
              Container(width: 0.8, height: 34, color: context.cl.borderSoft),
              const SizedBox(width: 10),
              Expanded(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  equipe(m.homeTeam, m.homeTeamLogo, dom, ext),
                  const SizedBox(height: 6),
                  equipe(m.awayTeam, m.awayTeamLogo, ext, dom),
                ]),
              ),
              // Suivre le match : la cloche, comme sur la grande carte.
              Semantics(
                label: libelleSuivi(context, suivi),
                button: true,
                excludeSemantics: true,
                child: IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    basculerSuivi(context, m.id, termine: termine);
                  },
                  icon: Icon(iconeSuivi(suivi), size: 19,
                    color: suivi ? AppColors.primary : context.cl.textM),
                ),
              ),
            ]),
          ),
        ),
      ),
    ));
  }
}

/// Les lignes d'une ligue dans un seul bloc, séparées d'un filet.
class BlocLignesMatch extends StatelessWidget {
  final List<MatchEntity> matchs;
  final bool avecDate;
  const BlocLignesMatch({super.key, required this.matchs, this.avecDate = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: context.cl.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.cl.border, width: 0.5),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Material(
          type: MaterialType.transparency,
          child: Column(children: [
            for (final (i, m) in matchs.indexed) ...[
              if (i > 0) Divider(height: 0.5, thickness: 0.5, indent: 72, color: context.cl.borderSoft),
              LigneMatchCompacte(match: m, avecDate: avecDate),
            ],
          ]),
        ),
      ),
    );
  }
}

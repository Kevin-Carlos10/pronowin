import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:pronowin/l10n/app_strings.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/team_logo_widget.dart';
import '../../../../shared/widgets/logotype_pronowin.dart';
import '../../domain/entities/match_entity.dart';
import 'fil_evenements.dart' show Buteur, abregerJoueur;
import 'fond_equipes.dart';

/// L'image d'un match à partager, comme « Partager les détails » de
/// Sofascore (vidéo du 8 novembre 2026) : compétition, logos, score, minute
/// ou état, buteurs, date, et la marque en pied.
///
/// PronoWin ne savait partager qu'un pronostic : un match sans pronostic, ou
/// le score d'un match suivi, ne se partageait qu'en texte. Rien ici ne
/// touche au pari : l'image part aussi de la version iPhone.
///
/// Largeur logique 360, comme la carte du pronostic ; toujours sombre.
class CarteMatchPartage extends StatelessWidget {
  final MatchEntity match;
  final int? dom, ext, minute;
  final ({List<Buteur> dom, List<Buteur> ext})? buteurs;

  const CarteMatchPartage({
    super.key,
    required this.match,
    this.dom,
    this.ext,
    this.minute,
    this.buteurs,
  });

  @override
  Widget build(BuildContext context) {
    final langue = AppStrings.of(context).locale.languageCode;
    final d = match.matchDate;
    final date = DateFormat('EEE d MMM · HH:mm', langue).format(d);
    final avecScore = match.status != MatchStatus.upcoming;
    final etat = switch (match.status) {
      MatchStatus.live => minute != null && minute! > 0 ? "$minute'" : tr(context, "En direct"),
      MatchStatus.finished => tr(context, "Terminé"),
      _ => DateFormat('HH:mm').format(d),
    };

    Widget equipe(String nom, String? logo) => Expanded(
      child: Column(children: [
        TeamLogoWidget(url: logo, size: 60),
        const SizedBox(height: 10),
        Text(nom, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700, height: 1.2)),
      ]),
    );

    Widget buts(List<Buteur> liste, TextAlign alignement) => Expanded(
      child: Column(
        crossAxisAlignment: alignement == TextAlign.right ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          for (final b in liste.take(4))
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text('${abregerJoueur(b.joueur)} ${b.minutes}',
                textAlign: alignement, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 11)),
            ),
        ],
      ),
    );

    final listeButs = buteurs;
    final avecButs = listeButs != null && (listeButs.dom.isNotEmpty || listeButs.ext.isNotEmpty);

    return SurfaceSombre(builder: (context) => SizedBox(
      width: 360,
      child: Stack(children: [
        // Le fond teinté par les deux équipes, comme l'en-tête de la fiche.
        Positioned.fill(child: FondEquipes(
          fond: const Color(0xFF0D1220),
          domicile: TeamLogoWidget(url: match.homeTeamLogo, size: 100),
          exterieur: TeamLogoWidget(url: match.awayTeamLogo, size: 100))),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
          child: Column(children: [
            Row(children: [
              const LogotypePronoWin(taille: 20, surFondSombre: true),
              const SizedBox(width: 10),
              const Spacer(),
              Flexible(flex: 3, child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20)),
                child: Text(match.league, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.right,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 11, fontWeight: FontWeight.w600)),
              )),
            ]),
            const SizedBox(height: 26),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              equipe(match.homeTeam, match.homeTeamLogo),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Column(children: [
                  const SizedBox(height: 8),
                  Text(avecScore ? '${dom ?? 0} - ${ext ?? 0}' : 'VS',
                    key: const Key('partage-score'),
                    style: TextStyle(
                      color: avecScore ? Colors.white : Colors.white.withValues(alpha: 0.55),
                      fontSize: avecScore ? 34 : 24, fontWeight: FontWeight.w800,
                      fontFeatures: const [FontFeature.tabularFigures()])),
                  const SizedBox(height: 4),
                  Text(etat, style: TextStyle(
                    color: match.status == MatchStatus.live ? const Color(0xFFEF4444) : Colors.white.withValues(alpha: 0.65),
                    fontSize: 12, fontWeight: FontWeight.w700)),
                ]),
              ),
              equipe(match.awayTeam, match.awayTeamLogo),
            ]),
            if (avecButs) ...[
              const SizedBox(height: 16),
              Container(height: 0.6, color: Colors.white.withValues(alpha: 0.12)),
              const SizedBox(height: 12),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                buts(listeButs.dom, TextAlign.left),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.sports_soccer_rounded, size: 14, color: Colors.white.withValues(alpha: 0.5))),
                buts(listeButs.ext, TextAlign.right),
              ]),
            ],
            const SizedBox(height: 18),
            Row(children: [
              Icon(Icons.event_rounded, size: 12, color: Colors.white.withValues(alpha: 0.5)),
              const SizedBox(width: 5),
              Expanded(child: Text(date, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 11))),
              Text(AppConstants.domaine,
                style: TextStyle(color: context.cl.accent, fontSize: 11, fontWeight: FontWeight.w700)),
            ]),
          ]),
        ),
      ]),
    ));
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:pronowin/l10n/app_strings.dart';
import 'package:pronowin/l10n/football_labels.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/team_logo_widget.dart';
import '../../../parametres/presentation/widgets/reglages_ui.dart' show EnTeteReglages;
import '../providers/pronostics_provider.dart';
import '../widgets/fil_evenements.dart';
import 'match_detail_page.dart' show statistiquesParPeriode;

/// Le détail d'une confrontation passée (15 novembre 2026) : on touchait une
/// ligne des confrontations directes, et rien ne s'ouvrait. Score et
/// mi-temps, faits du match, statistiques — ce que le fournisseur publie pour
/// une rencontre terminée. Si elle est dans notre base, sa fiche complète
/// s'ouvre aussi.
class ConfrontationPage extends ConsumerWidget {
  final String matchId;
  final int fixtureId;
  /// La ligne touchée : l'en-tête s'affiche tout de suite, le détail suit.
  final H2HMatchResult apercu;
  const ConfrontationPage({super.key, required this.matchId, required this.fixtureId, required this.apercu});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cle = (matchId: matchId, fixtureId: fixtureId);
    final detail = ref.watch(confrontationProvider(cle));
    final c = detail.valueOrNull;
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        leading: IconButton(
          tooltip: tr(context, "Retour"),
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(tr(context, "Confrontation"),
          style: TextStyle(color: context.cl.textP, fontSize: 17, fontWeight: FontWeight.w600)),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(confrontationProvider(cle).future),
        child: ListView(
          key: const Key('confrontation-detail'),
          padding: const EdgeInsets.fromLTRB(margeEcran, 12, margeEcran, 40),
          children: [
            _EnTete(apercu: apercu, detail: c),
            if (c?.matchId != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const Key('confrontation-fiche'),
                onPressed: () => context.push('/pronostics/${c!.matchId}'),
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: Text(tr(context, "Voir la fiche complète du match")),
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.cl.textP,
                  minimumSize: const Size.fromHeight(46),
                  side: BorderSide(color: context.cl.border),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              ),
            ],
            const SizedBox(height: 22),
            ...detail.when(
              loading: () => [const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator(color: AppColors.primary)))],
              error: (_, _) => [_Message(
                icone: Icons.cloud_off_rounded,
                texte: tr(context, "Le détail de cette rencontre est momentanément indisponible."),
                reessayer: () => ref.invalidate(confrontationProvider(cle)))],
              data: (c) => _sections(context, c),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _sections(BuildContext context, Confrontation c) {
    final s = c.stats;
    final carte = BoxDecoration(
      color: context.cl.surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: context.cl.border, width: 0.5));
    return [
      EnTeteReglages(tr(context, "Faits marquants")),
      if (s == null || s.events.isEmpty)
        _Message(icone: Icons.event_note_outlined,
          texte: tr(context, "Le fournisseur ne publie pas les faits de cette rencontre."))
      else Container(
        key: const Key('confrontation-faits'),
        padding: const EdgeInsets.all(14),
        decoration: carte,
        child: FilEvenements(lignes: construireFil(
          s.events,
          domicile: s.homeTeam,
          termine: true,
          periodeAtteinte: 2,
          scoreFinal: c.homeScore != null && c.awayScore != null
              ? (dom: c.homeScore!, ext: c.awayScore!) : null,
        )),
      ),
      const SizedBox(height: 22),
      EnTeteReglages(tr(context, "Statistiques")),
      if (s == null || s.stats.isEmpty)
        _Message(icone: Icons.bar_chart_rounded,
          texte: tr(context, "Le fournisseur ne publie pas les statistiques de cette rencontre."))
      else Container(
        key: const Key('confrontation-stats'),
        padding: const EdgeInsets.all(14),
        decoration: carte,
        child: statistiquesParPeriode(s),
      ),
    ];
  }
}

/// L'en-tête : compétition, date, les deux équipes et le score, la mi-temps.
class _EnTete extends StatelessWidget {
  final H2HMatchResult apercu;
  final Confrontation? detail;
  const _EnTete({required this.apercu, this.detail});

  @override
  Widget build(BuildContext context) {
    final d = detail;
    final langue = AppStrings.of(context).locale.languageCode;
    final date = d?.date ?? apercu.date;
    final ligue = d?.league ?? apercu.league;
    final dom = d?.homeTeam ?? apercu.homeTeam, ext = d?.awayTeam ?? apercu.awayTeam;
    final butsDom = d?.homeScore ?? apercu.homeScore, butsExt = d?.awayScore ?? apercu.awayScore;
    final infos = [
      // « Regular Season - 27 » → « Journée 27 », comme au classement.
      if (d?.round != null && d!.round!.isNotEmpty) FootballLabels.round(d.round!, language: langue),
      if (d?.venue != null && d!.venue!.isNotEmpty) d.venue!,
    ].join(' · ');

    Widget equipe(String nom, String? logo, bool gagne) => Expanded(child: Column(children: [
      TeamLogoWidget(url: logo, size: 46),
      const SizedBox(height: 8),
      Text(nom, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis,
        style: TextStyle(color: context.cl.textP, fontSize: 14,
          fontWeight: gagne ? FontWeight.w700 : FontWeight.w500)),
    ]));

    return Container(
      key: const Key('confrontation-entete'),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      decoration: BoxDecoration(
        color: context.cl.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.cl.border, width: 0.5)),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (d?.leagueLogo != null) ...[
            Container(
              width: 22, height: 22, padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              child: TeamLogoWidget(url: d!.leagueLogo, size: 18)),
            const SizedBox(width: 8),
          ],
          Flexible(child: Text(ligue, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(color: context.cl.textS, fontSize: 13, fontWeight: FontWeight.w600))),
        ]),
        const SizedBox(height: 4),
        Text(DateFormat('EEEE d MMMM y', langue).format(date),
          style: TextStyle(color: context.cl.textM, fontSize: 12)),
        const SizedBox(height: 16),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          equipe(dom, d?.homeLogo, butsDom > butsExt),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Column(children: [
              const SizedBox(height: 8),
              Text('$butsDom - $butsExt', key: const Key('confrontation-score'),
                style: TextStyle(color: context.cl.textP, fontSize: 30, fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()])),
              const SizedBox(height: 4),
              Text(tr(context, "Terminé"), style: TextStyle(color: context.cl.textM, fontSize: 12)),
              if (d?.mtHome != null && d?.mtAway != null)
                Text(tr(context, "Mi-temps : {arg0} - {arg1}", [d!.mtHome, d.mtAway]),
                  key: const Key('confrontation-mi-temps'),
                  style: TextStyle(color: context.cl.textS, fontSize: 12)),
            ]),
          ),
          equipe(ext, d?.awayLogo, butsExt > butsDom),
        ]),
        if (infos.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(infos, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis,
            style: TextStyle(color: context.cl.textM, fontSize: 12)),
        ],
      ]),
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icone;
  final String texte;
  final VoidCallback? reessayer;
  const _Message({required this.icone, required this.texte, this.reessayer});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
    child: Column(children: [
      Icon(icone, size: 30, color: context.cl.textM),
      const SizedBox(height: 8),
      Text(texte, textAlign: TextAlign.center, style: TextStyle(color: context.cl.textS, fontSize: 13)),
      if (reessayer != null) TextButton(onPressed: reessayer, child: Text(tr(context, "Réessayer"))),
    ]),
  );
}

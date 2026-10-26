part of '../match_detail_page.dart';

@visibleForTesting
Widget informationsMatchSeules(String id) => _MatchInformationCard(matchId: id);

/// Informations du match, au modèle de Sofascore : une ligne par fait —
/// libellé à gauche, valeur à droite —, rien d'autre.
///
/// La carte affichait aussi l'état du match (« Première mi-temps »), le temps
/// de jeu et l'heure du dernier relevé (« Actualisé à 21:04 ») : l'en-tête et
/// son chrono disent déjà où en est le match, et l'heure d'un relevé n'est
/// pas une information sur le match (demande du 18 octobre 2026). Les scores
/// par période sont dans le fil des événements (« À la mi-temps 1-0 ») ; seuls
/// les tirs au but restent ici, que l'en-tête n'affiche pas.
///
/// Sans rien à montrer, la carte disparaît, avec sa marge.
class _MatchInformationCard extends ConsumerWidget {
  final String matchId;
  const _MatchInformationCard({required this.matchId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(matchInfoProvider(matchId));
    final info = state.valueOrNull;
    final cl = context.cl;

    final lignes = <(IconData, String, String)>[
      if (info?.round != null) (Icons.emoji_events_outlined, 'Tour de compétition',
          FootballLabels.round(info!.round!, language: AppStrings.of(context).locale.languageCode)),
      if (info?.season != null) (Icons.calendar_today_outlined, 'Saison', info!.season.toString()),
      if (info?.venue != null) (Icons.stadium_outlined, 'Stade', info!.venue!),
      if (info?.city != null) (Icons.place_outlined, 'Ville', info!.city!),
      if (info?.referee != null) (Icons.sports_outlined, 'Arbitre', info!.referee!),
      if (['P', 'PEN'].contains(info?.phase) && info!.scores['penalty']?.available == true)
        (Icons.sports_soccer_outlined, 'Tirs au but', info.scores['penalty']!.label),
    ];

    final Widget contenu;
    if (info == null && state.isLoading) {
      contenu = LinearProgressIndicator(color: cl.info);
    } else if (info == null && state.hasError) {
      contenu = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr(context, 'Informations du match momentanément indisponibles.'),
            style: TextStyle(color: cl.textS)),
        TextButton(
          onPressed: () => ref.invalidate(matchInfoProvider(matchId)),
          child: Text(tr(context, 'Réessayer')),
        ),
      ]);
    } else if (lignes.isEmpty) {
      return const SizedBox.shrink();
    } else {
      contenu = Column(children: [
        for (final (i, (icone, libelle, valeur)) in lignes.indexed) ...[
          if (i > 0) Divider(color: cl.borderSoft, height: 1),
          _LigneInformation(icone: icone, libelle: tr(context, libelle), valeur: valeur),
        ],
      ]);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        decoration: BoxDecoration(
          color: cl.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cl.borderSoft),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr(context, 'Informations du match'),
              style: TextStyle(color: cl.textP, fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            contenu,
          ],
        ),
      ),
    );
  }
}

class _LigneInformation extends StatelessWidget {
  final IconData icone;
  final String libelle, valeur;
  const _LigneInformation({required this.icone, required this.libelle, required this.valeur});

  @override
  Widget build(BuildContext context) {
    final cl = context.cl;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icone, size: 18, color: cl.textS),
        const SizedBox(width: 10),
        Flexible(flex: 2, child: Text(libelle, style: TextStyle(color: cl.textS, fontSize: 13))),
        const SizedBox(width: 12),
        Expanded(flex: 3, child: Text(valeur, textAlign: TextAlign.end,
            style: TextStyle(color: cl.textP, fontSize: 13.5, fontWeight: FontWeight.w600))),
      ]),
    );
  }
}

part of '../match_detail_page.dart';

@visibleForTesting
Widget informationsMatchSeules(String id) => _MatchInformationCard(matchId: id);

const _phasesMatch = {
  'TBD': 'Horaire à confirmer',
  'NS': 'À venir',
  '1H': 'Première mi-temps',
  'HT': 'Mi-temps',
  '2H': 'Deuxième mi-temps',
  'ET': 'Prolongations',
  'BT': 'Pause avant reprise',
  'P': 'Tirs au but en cours',
  'FT': 'Terminé',
  'AET': 'Terminé après prolongations',
  'PEN': 'Terminé aux tirs au but',
  'SUSP': 'Match suspendu',
  'INT': 'Match interrompu',
  'PST': 'Match reporté',
  'CANC': 'Match annulé',
  'ABD': 'Match abandonné',
  'AWD': 'Résultat attribué',
  'WO': 'Forfait',
  'LIVE': 'En direct',
};

class _MatchInformationCard extends ConsumerWidget {
  final String matchId;
  const _MatchInformationCard({required this.matchId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(matchInfoProvider(matchId));
    final info = state.valueOrNull;
    final cl = context.cl;
    Widget row(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr(context, label),
            style: TextStyle(color: cl.textS, fontSize: 12),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              color: cl.textP,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
    final periodLabels = {
      'halftime': info?.phase == '1H'
          ? 'Première mi-temps (en cours)'
          : 'Mi-temps',
      'fulltime': ['1H', 'HT', '2H', 'LIVE'].contains(info?.phase)
          ? 'Temps réglementaire (en cours)'
          : 'Temps réglementaire',
      'extratime': ['ET', 'BT'].contains(info?.phase)
          ? 'Prolongations (en cours)'
          : 'Prolongations',
      'penalty': info?.phase == 'P' ? 'Tirs au but (en cours)' : 'Tirs au but',
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
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
            style: TextStyle(
              color: cl.textP,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          if (info == null) ...[
            if (state.isLoading)
              LinearProgressIndicator(color: cl.info)
            else
              Text(
                tr(
                  context,
                  state.hasError
                      ? 'Informations du match momentanément indisponibles.'
                      : 'Informations non fournies pour ce match.',
                ),
                style: TextStyle(color: cl.textS),
              ),
            if (state.hasError)
              TextButton(
                onPressed: () => ref.invalidate(matchInfoProvider(matchId)),
                child: Text(tr(context, 'Réessayer')),
              ),
          ] else ...[
            _FraicheurDonnees(
              updatedAt: info.updatedAt,
              stale: info.stale || state.hasError,
            ),
            if (info.phase != null)
              row(
                'État du match',
                tr(context, _phasesMatch[info.phase] ?? 'État non précisé'),
              ),
            if (info.elapsed != null &&
                ['1H', '2H', 'ET', 'LIVE'].contains(info.phase))
              row(
                'Temps de jeu',
                info.extra != null && info.extra! > 0
                    ? '${info.elapsed} + ${info.extra} min'
                    : '${info.elapsed} min',
              ),
            if (info.venue != null || info.city != null)
              row(
                info.venue != null ? 'Stade' : 'Ville',
                [info.venue, info.city].whereType<String>().join(' · '),
              ),
            if (info.referee != null) row('Arbitre', info.referee!),
            if (info.round != null) row('Tour de compétition', FootballLabels.round(info.round!, language: AppStrings.of(context).locale.languageCode)),
            if (info.season != null) row('Saison', info.season.toString()),
            if (!['NS', 'TBD', 'PST', 'CANC'].contains(info.phase) &&
                info.scores.values.any((s) => s.available)) ...[
              Divider(color: cl.borderSoft),
              Text(
                [info.homeTeam, info.awayTeam].whereType<String>().join(' — '),
                style: TextStyle(color: cl.textS, fontSize: 12),
              ),
              for (final entry in periodLabels.entries)
                if (info.scores[entry.key]?.available == true)
                  row(entry.value, info.scores[entry.key]!.label),
            ],
            if (info.stale || state.hasError)
              TextButton(
                onPressed: () => ref.invalidate(matchInfoProvider(matchId)),
                child: Text(tr(context, 'Réessayer')),
              ),
          ],
        ],
      ),
    );
  }
}

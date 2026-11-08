import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:pronowin/l10n/app_strings.dart';
import '../../core/constants/app_constants.dart';
import '../../core/network/dio_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/team_logo_widget.dart';
import '../../shared/utils/retour.dart';
import '../auth/presentation/providers/auth_provider.dart';
import '../pronostics/data/models/match_model.dart';
import '../pronostics/domain/entities/match_entity.dart';
import '../pronostics/presentation/widgets/ligne_match_compacte.dart';
import '../pronostics/presentation/widgets/match_card_widget.dart';

/// Les grandes compétitions, d'un geste depuis l'accueil (8 novembre 2026).
///
/// Repris de 1xBet (« TOP-EVENTS » : Ligue des champions, Ligue Europa en
/// tête de l'accueil) et de Sofascore, où chaque compétition a sa page. Dans
/// PronoWin, retrouver les matchs de Premier League demandait d'ouvrir la
/// liste, de choisir le jour, puis de filtrer la ligue.
///
/// [code] : le code de compétition du serveur (`leagueCode`) ; [id] : son
/// identifiant API-Football, qui donne le logo.
class Competition {
  final String code;
  final int id;
  final String nom;
  const Competition(this.code, this.id, this.nom);

  String get logo => 'https://media.api-sports.io/football/leagues/$id.png';
}

const grandesCompetitions = [
  Competition('CL', 2, 'Ligue des champions'),
  Competition('PL', 39, 'Premier League'),
  Competition('PD', 140, 'LaLiga'),
  Competition('SA', 135, 'Serie A'),
  Competition('BL1', 78, 'Bundesliga'),
  Competition('FL1', 61, 'Ligue 1'),
  Competition('AF_3', 3, 'Ligue Europa'),
];

Competition? competitionDe(String code) {
  for (final c in grandesCompetitions) {
    if (c.code == code) return c;
  }
  return null;
}

/// Les matchs d'une compétition sur les sept prochains jours (le direct
/// compris), par ordre de coup d'envoi.
final matchsCompetitionProvider =
    FutureProvider.autoDispose.family<List<MatchEntity>, String>((ref, code) async {
  final r = await ref.read(dioProvider).get(ApiEndpoints.pronostics, queryParameters: {
    'include_all': 'true',
    'league_code': code,
    'date_filter': 'week',
    'limit': 50,
    'tz_offset': decalageUtcMinutes(),
  });
  final liste = (r.data as Map<String, dynamic>)['data'] as List<dynamic>;
  return liste.map((e) => MatchModel.fromJson(e as Map<String, dynamic>)).toList()
    ..sort((a, b) => a.matchDate.compareTo(b.matchDate));
});

/// La rangée de l'accueil : un logo et un nom par compétition.
class GrandesCompetitions extends StatelessWidget {
  const GrandesCompetitions({super.key});

  @override
  Widget build(BuildContext context) {
    final echelle = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          const Icon(Icons.emoji_events_rounded, color: AppColors.primary, size: 16),
          const SizedBox(width: 6),
          Text(tr(context, "Grandes compétitions"),
            style: TextStyle(color: context.cl.textP, fontSize: 16, fontWeight: FontWeight.w700)),
        ]),
      ),
      SizedBox(
        height: 92 * echelle,
        child: ListView.separated(
          key: const Key('grandes-competitions'),
          scrollDirection: Axis.horizontal,
          itemCount: grandesCompetitions.length,
          separatorBuilder: (_, _) => const SizedBox(width: 10),
          itemBuilder: (context, i) {
            final c = grandesCompetitions[i];
            return Semantics(
              button: true,
              label: tr(context, "Matchs de la compétition {arg0}", [tr(context, c.nom)]),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => context.push('/competitions/${c.code}'),
                child: ExcludeSemantics(
                  child: Container(
                    width: 92 * echelle,
                    padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
                    decoration: BoxDecoration(
                      color: context.cl.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: context.cl.border, width: 0.5)),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      // Fond clair : certains logos (Ligue des champions) sont
                      // sombres, illisibles sur la carte en thème sombre.
                      Container(
                        width: 40, height: 40, padding: const EdgeInsets.all(5),
                        decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                        child: TeamLogoWidget(url: c.logo, size: 30)),
                      const SizedBox(height: 7),
                      Text(tr(context, c.nom),
                        maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: context.cl.textP, fontSize: 11, fontWeight: FontWeight.w600, height: 1.15)),
                    ]),
                  ),
                ),
              ),
            );
          },
        ),
      ),
      const SizedBox(height: 24),
    ]);
  }
}

/// La page d'une compétition : ses matchs des sept prochains jours, jour par
/// jour. Les matchs pronostiqués gardent leur grande carte, les autres une
/// ligne, comme dans la liste principale.
class CompetitionPage extends ConsumerWidget {
  final String code;
  const CompetitionPage({super.key, required this.code});

  String _jour(BuildContext context, DateTime d) {
    final aujourdhui = DateTime.now();
    final j = DateTime(d.year, d.month, d.day);
    final ecart = j.difference(DateTime(aujourdhui.year, aujourdhui.month, aujourdhui.day)).inDays;
    if (ecart == 0) return tr(context, "Aujourd'hui");
    if (ecart == 1) return tr(context, "Demain");
    final texte = DateFormat('EEEE d MMMM', AppStrings.of(context).locale.languageCode).format(d);
    return texte[0].toUpperCase() + texte.substring(1);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = competitionDe(code);
    final matchs = ref.watch(matchsCompetitionProvider(code));
    final etat = ref.watch(authProvider);
    final premium = etat is AuthAuthenticated && etat.user.isPremium;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: tr(context, "Retour"),
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => retourOuAller(context, repli: '/home'),
        ),
        titleSpacing: 0,
        title: Row(children: [
          if (c != null) ...[
            Container(
              width: 30, height: 30, padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              child: TeamLogoWidget(url: c.logo, size: 22)),
            const SizedBox(width: 10),
          ],
          Flexible(child: Text(c == null ? code : tr(context, c.nom), overflow: TextOverflow.ellipsis)),
        ]),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(matchsCompetitionProvider(code).future),
        child: matchs.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => ListView(children: [
            const SizedBox(height: 120),
            Center(child: Text(tr(context, "Impossible de charger les matchs."),
              style: TextStyle(color: context.cl.textS))),
            Center(child: TextButton(
              onPressed: () => ref.invalidate(matchsCompetitionProvider(code)),
              child: Text(tr(context, "Réessayer")))),
          ]),
          data: (liste) {
            if (liste.isEmpty) {
              return ListView(children: [
                const SizedBox(height: 120),
                Icon(Icons.event_busy_rounded, size: 44, color: context.cl.textM),
                const SizedBox(height: 12),
                Center(child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(tr(context, "Aucun match de cette compétition dans les sept prochains jours."),
                    textAlign: TextAlign.center, style: TextStyle(color: context.cl.textS)))),
              ]);
            }
            // Jour par jour.
            final parJour = <DateTime, List<MatchEntity>>{};
            for (final m in liste) {
              final d = m.matchDate;
              parJour.putIfAbsent(DateTime(d.year, d.month, d.day), () => []).add(m);
            }
            return ListView(
              key: const Key('matchs-competition'),
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 40),
              children: [
                for (final e in parJour.entries) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 10, 4, 8),
                    child: Text(_jour(context, e.key),
                      style: TextStyle(color: context.cl.textP, fontSize: 14, fontWeight: FontWeight.w700)),
                  ),
                  for (final m in e.value.where((m) => m.hasPronostic)) MatchCardWidget(match: m, isPremiumUser: premium),
                  if (e.value.any((m) => !m.hasPronostic))
                    BlocLignesMatch(matchs: e.value.where((m) => !m.hasPronostic).toList()),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

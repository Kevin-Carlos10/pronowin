import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pronowin/l10n/app_strings.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/team_logo_widget.dart';
import '../../../../shared/providers/favoris_provider.dart';
import '../../../../shared/utils/messages.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../equipes/presentation/pages/fiche_equipe_page.dart';
import '../../../equipes/presentation/providers/fiche_equipe_provider.dart';
import '../../domain/entities/match_entity.dart';
import '../providers/pronostics_provider.dart';
import 'ligne_match_compacte.dart';

/// Les équipes suivies dans « Suivis » (7 novembre 2026, comme FotMob) : leurs
/// écussons, puis leurs prochains matchs, chacun avec sa cloche.
///
/// Sans équipe suivie, des suggestions tirées des matchs du jour : un appui
/// les suit.

/// Fenêtre des « prochains matchs » : les matchs en direct, ceux de la
/// veille et ceux des deux semaines à venir.
const _fenetreAvant = Duration(days: 1);
const _fenetreApres = Duration(days: 14);
const _maxMatchs = 12;

/// Les prochains matchs des équipes suivies, du plus proche au plus lointain.
///
/// Chaque équipe est cherchée par son nom (la recherche des matchs, côté
/// serveur), puis seuls les matchs dont un écusson porte son identifiant sont
/// gardés : « Bayern » ne ramène pas Bayern II.
final matchsEquipesSuiviesProvider = FutureProvider.autoDispose<List<MatchEntity>>((ref) async {
  final equipes = ref.watch(favorisProvider.select((f) => f.valueOrNull?.equipes ?? const <EquipeSuivie>[]));
  if (equipes.isEmpty) return const [];
  final maintenant = DateTime.now();
  final listes = await Future.wait([
    for (final e in equipes)
      ref.watch(rechercheMatchsProvider(e.nom).future).catchError((_) => const <MatchEntity>[]),
  ]);
  final ids = {for (final e in equipes) e.id};
  final parId = <String, MatchEntity>{};
  for (final m in listes.expand((l) => l)) {
    final concerne = ids.contains(idEquipeDepuisLogo(m.homeTeamLogo)) || ids.contains(idEquipeDepuisLogo(m.awayTeamLogo));
    final dansFenetre = m.status == MatchStatus.live ||
        (m.matchDate.isAfter(maintenant.subtract(_fenetreAvant)) && m.matchDate.isBefore(maintenant.add(_fenetreApres)));
    if (concerne && dansFenetre) parId[m.id] = m;
  }
  final tries = parId.values.toList()..sort((a, b) {
    if (a.status == MatchStatus.live && b.status != MatchStatus.live) return -1;
    if (b.status == MatchStatus.live && a.status != MatchStatus.live) return 1;
    return a.matchDate.compareTo(b.matchDate);
  });
  return tries.take(_maxMatchs).toList();
});

/// Écussons des équipes suivies et leurs prochains matchs.
class EquipesSuiviesSection extends ConsumerWidget {
  const EquipesSuiviesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final equipes = ref.watch(favorisProvider).valueOrNull?.equipes ?? const <EquipeSuivie>[];
    if (equipes.isEmpty) return const SuggestionsEquipes();
    final matchs = ref.watch(matchsEquipesSuiviesProvider);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _Titre(tr(context, "Mes équipes"), equipes.length),
      SizedBox(
        height: 92,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: equipes.length,
          separatorBuilder: (_, _) => const SizedBox(width: 10),
          itemBuilder: (_, i) => _Ecusson(equipe: equipes[i]),
        ),
      ),
      const SizedBox(height: 14),
      _Titre(tr(context, "Prochains matchs de mes équipes"), null),
      matchs.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))),
        error: (_, _) => const SizedBox.shrink(),
        data: (liste) => liste.isEmpty
            ? Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Text(tr(context, "Aucun match de tes équipes dans les deux semaines à venir."),
                  style: TextStyle(color: context.cl.textM, fontSize: 13)))
            : BlocLignesMatch(matchs: liste, avecDate: true),
      ),
    ]);
  }
}

/// Sans équipe suivie : les équipes des matchs du jour, celles qui ont un
/// pronostic d'abord. Un appui les suit.
class SuggestionsEquipes extends ConsumerWidget {
  const SuggestionsEquipes({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matchs = [...ref.watch(matchesPaginatedProvider).matches]
      ..sort((a, b) => (b.hasPronostic ? 1 : 0) - (a.hasPronostic ? 1 : 0));
    final suggestions = <int, EquipeSuivie>{};
    for (final m in matchs) {
      for (final (nom, logo) in [(m.homeTeam, m.homeTeamLogo), (m.awayTeam, m.awayTeamLogo)]) {
        final id = idEquipeDepuisLogo(logo);
        if (id != null) suggestions.putIfAbsent(id, () => EquipeSuivie(id: id, nom: nom, logo: logo, competition: m.leagueCountry));
      }
      if (suggestions.length >= 10) break;
    }
    if (suggestions.isEmpty) return const SizedBox.shrink();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _Titre(tr(context, "Suis tes équipes"), null),
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(tr(context, "Leurs prochains matchs s'afficheront ici."),
          style: TextStyle(color: context.cl.textM, fontSize: 13)),
      ),
      SizedBox(
        height: 92,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: suggestions.length,
          separatorBuilder: (_, _) => const SizedBox(width: 10),
          itemBuilder: (_, i) => _Ecusson(equipe: suggestions.values.elementAt(i), suggestion: true),
        ),
      ),
      const SizedBox(height: 14),
    ]);
  }
}

class _Titre extends StatelessWidget {
  final String texte;
  final int? nombre;
  const _Titre(this.texte, this.nombre);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10, top: 4),
    child: Semantics(header: true, child: Row(children: [
      const Icon(Icons.star_rounded, size: 15, color: AppColors.primary),
      const SizedBox(width: 6),
      Flexible(child: Text(texte, style: TextStyle(color: context.cl.textP, fontSize: 13, fontWeight: FontWeight.w700))),
      if (nombre != null) ...[
        const SizedBox(width: 8),
        Text('$nombre', style: TextStyle(color: context.cl.accent, fontSize: 11, fontWeight: FontWeight.w700)),
      ],
    ])),
  );
}

/// Un écusson et son nom. Suivie : ouvre la fiche ; suggestion : la suit.
class _Ecusson extends ConsumerWidget {
  final EquipeSuivie equipe;
  final bool suggestion;
  const _Ecusson({required this.equipe, this.suggestion = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Semantics(
      button: true,
      label: suggestion
          ? tr(context, "Suivre {arg0}", [equipe.nom])
          : tr(context, "{arg0}, ouvrir la fiche de l'équipe", [equipe.nom]),
      excludeSemantics: true,
      child: InkWell(
        key: Key('${suggestion ? 'suggestion' : 'equipe-suivie'}-${equipe.id}'),
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          HapticFeedback.selectionClick();
          if (suggestion) {
            ref.read(favorisProvider.notifier).basculerEquipe(equipe);
          } else {
            ouvrirFicheEquipe(context, nom: equipe.nom, logo: equipe.logo,
              competition: equipe.competition, id: equipe.id);
          }
        },
        child: Container(
          width: 84,
          padding: const EdgeInsets.fromLTRB(6, 10, 6, 8),
          decoration: BoxDecoration(
            color: context.cl.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.cl.border, width: 0.6),
          ),
          child: Column(children: [
            Stack(clipBehavior: Clip.none, children: [
              TeamLogoWidget(url: equipe.logo, size: 36),
              if (suggestion)
                Positioned(right: -6, bottom: -4, child: Container(
                  width: 18, height: 18,
                  decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                  child: const Icon(Icons.add_rounded, size: 14, color: Colors.white))),
            ]),
            const Spacer(),
            Text(equipe.nom, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
              style: TextStyle(color: context.cl.textP, fontSize: 12, fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }
}

/// L'étoile « Suivre l'équipe » à côté d'un logo, dans l'en-tête d'un match
/// (8 novembre 2026, comme Sofascore). Suivre une équipe demandait d'ouvrir
/// sa fiche. Rien si l'équipe n'a pas d'identifiant connu.
class EtoileSuivreEquipe extends ConsumerWidget {
  final String nom;
  final String? logo, competition;
  final double taille;
  const EtoileSuivreEquipe({super.key, required this.nom, this.logo, this.competition, this.taille = 22});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = idEquipeDepuisLogo(logo);
    if (id == null || nom.isEmpty) return const SizedBox.shrink();
    final suivie = ref.watch(favorisProvider).valueOrNull?.suitEquipe(id) ?? false;
    final libelle = suivie ? tr(context, "Ne plus suivre {arg0}", [nom]) : tr(context, "Suivre {arg0}", [nom]);
    return IconButton(
      key: Key('etoile-equipe-$id'),
      tooltip: libelle,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      icon: Icon(suivie ? Icons.star_rounded : Icons.star_outline_rounded,
        size: taille, color: suivie ? AppColors.primary : context.cl.textS),
      onPressed: () async {
        HapticFeedback.selectionClick();
        if (!ref.read(effectiveLoggedInProvider)) {
          context.push('/auth/email?from=${Uri.encodeComponent('/equipes/$id')}');
          return;
        }
        final message = suivie
            ? tr(context, "Tu ne suis plus {arg0}.", [nom])
            : tr(context, "{arg0} est suivie : ses matchs sont dans « Suivis ».", [nom]);
        await ref.read(favorisProvider.notifier)
            .basculerEquipe(EquipeSuivie(id: id, nom: nom, logo: logo, competition: competition));
        if (context.mounted) {
          afficherMessage(context, message, type: suivie ? TypeMessage.info : TypeMessage.succes);
        }
      },
    );
  }
}

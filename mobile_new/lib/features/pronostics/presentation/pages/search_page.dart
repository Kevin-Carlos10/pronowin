import 'package:pronowin/l10n/app_strings.dart';
import 'package:flutter/material.dart';
import '../../../../shared/widgets/erreur_chargement.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../providers/pronostics_provider.dart';
import '../widgets/match_card_widget.dart';
import '../../../../features/auth/presentation/providers/auth_provider.dart';
import '../../../../core/widgets/team_logo_widget.dart';
import '../../../../core/widgets/image_distante.dart';
import '../../../equipes/presentation/pages/fiche_equipe_page.dart';
import '../../../joueurs/presentation/pages/fiche_joueur_page.dart';
import '../providers/recherche_provider.dart';
import '../../domain/entities/match_entity.dart';

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _ctrl   = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  // Le filtre local a été retiré.
  //
  // Il parcourait `pagedState.matches` — la liste **déjà chargée** du provider
  // paginé : vingt matchs, ceux de la page courante et des filtres courants.
  // Une équipe qui existe mais dont la page n'avait pas été téléchargée était
  // annoncée absente, et le résultat dépendait du nombre de fois qu'on avait
  // fait défiler la liste.
  //
  // La recherche est faite par la base, via `rechercheMatchsProvider`.

  @override
  Widget build(BuildContext context) {
    final terme      = _query.trim();
    // La recherche part au serveur, dès deux caractères — même seuil que lui.
    final resultats  = ref.watch(rechercheMatchsProvider(terme));
    // Équipes et joueurs (7 novembre 2026) : ils complètent les matchs.
    final autres     = ref.watch(rechercheEquipesJoueursProvider(terme)).valueOrNull
        ?? ResultatsRecherche.vide;
    final authState  = ref.watch(authProvider);
    final isPremium  = authState is AuthAuthenticated && authState.user.isPremium;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: context.cl.bg,
        titleSpacing: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: context.cl.textP),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: TextField(
          controller: _ctrl,
          autofocus: true,
          style: TextStyle(color: context.cl.textP, fontSize: 16),
          decoration: InputDecoration(
            hintText: tr(context, "Équipe, joueur, ligue…"),
            hintStyle: TextStyle(color: context.cl.textM, fontSize: 16),
            border: InputBorder.none,
            suffixIcon: _query.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.close_rounded, color: context.cl.textM, size: 20),
                  onPressed: () {
                    _ctrl.clear();
                    setState(() => _query = '');
                  },
                )
              : null,
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
      ),
      body: terme.length < 2
        ? _EmptyPrompt()
        : resultats.when(
            loading: () => autres.estVide
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : _Resultats(autres: autres, matchs: const [], isPremium: isPremium, matchsEnCours: true),
            error: (_, _) => autres.estVide
                ? ErreurChargement(
                    erreur: tr(context, "La recherche n'a pas abouti."),
                    quoi: tr(context, "les matchs"),
                    from: '/recherche',
                    onRetry: () =>
                        ref.invalidate(rechercheMatchsProvider(terme)))
                : _Resultats(autres: autres, matchs: const [], isPremium: isPremium),
            data: (liste) => liste.isEmpty && autres.estVide
                ? _NoResults(query: _query)
                : _Resultats(autres: autres, matchs: liste, isPremium: isPremium),
          ),
    );
  }
}

/// Équipes, joueurs, puis matchs : chaque section n'apparaît que si elle a
/// quelque chose à montrer.
class _Resultats extends StatelessWidget {
  final ResultatsRecherche autres;
  final List<MatchEntity> matchs;
  final bool isPremium, matchsEnCours;
  const _Resultats({required this.autres, required this.matchs, required this.isPremium,
    this.matchsEnCours = false});

  @override
  Widget build(BuildContext context) {
    Widget titre(String texte) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
      child: Semantics(header: true, child: Text(texte,
        style: TextStyle(color: context.cl.textS, fontSize: 12.5, fontWeight: FontWeight.w800, letterSpacing: 0.4))),
    );
    Widget bloc(List<Widget> lignes) => Container(
      decoration: BoxDecoration(
        color: context.cl.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.cl.border, width: 0.5)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Material(type: MaterialType.transparency, child: Column(children: [
          for (final (i, l) in lignes.indexed) ...[
            if (i > 0) Divider(height: 0.5, thickness: 0.5, indent: 60, color: context.cl.borderSoft),
            l,
          ],
        ])),
      ),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 100),
      children: [
        if (autres.equipes.isNotEmpty) ...[
          titre(tr(context, "ÉQUIPES")),
          bloc([
            for (final e in autres.equipes)
              ListTile(
                key: Key('equipe-${e.id}'),
                leading: TeamLogoWidget(url: e.logo, size: 30),
                title: Text(e.nom, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: context.cl.textP, fontSize: 14.5, fontWeight: FontWeight.w600)),
                trailing: Icon(Icons.chevron_right_rounded, color: context.cl.textM),
                onTap: () => ouvrirFicheEquipe(context, nom: e.nom, logo: e.logo,
                  competition: e.competition, id: e.id),
              ),
          ]),
        ],
        if (autres.joueurs.isNotEmpty) ...[
          titre(tr(context, "JOUEURS")),
          bloc([
            for (final j in autres.joueurs)
              ListTile(
                key: Key('joueur-${j.id}'),
                leading: ClipOval(child: SizedBox(width: 34, height: 34, child: ImageDistante(
                  url: j.photo, largeur: 34, hauteur: 34, fit: BoxFit.cover,
                  repli: ColoredBox(color: context.cl.surfaceDeep,
                    child: Icon(Icons.person_rounded, size: 20, color: context.cl.textM))))),
                title: Text(j.nom, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: context.cl.textP, fontSize: 14.5, fontWeight: FontWeight.w600)),
                subtitle: Text(
                  [libellePoste(context, j.poste), if (j.nationalite != null) j.nationalite!]
                      .where((x) => x.isNotEmpty).join(' · '),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: context.cl.textM, fontSize: 12)),
                trailing: Icon(Icons.chevron_right_rounded, color: context.cl.textM),
                onTap: () => ouvrirFicheJoueur(context, id: j.id, nom: j.nom, photo: j.photo),
              ),
          ]),
        ],
        if (matchs.isNotEmpty || matchsEnCours) titre(tr(context, "MATCHS")),
        if (matchsEnCours && matchs.isEmpty)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))),
        for (final m in matchs)
          MatchCardWidget(match: m, isPremiumUser: isPremium, showDate: true),
      ],
    );
  }
}

class _EmptyPrompt extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.search_rounded, size: 56, color: context.cl.textM),
      const SizedBox(height: 16),
      Text(tr(context, "Rechercher une équipe, un joueur ou un match"),
        style: TextStyle(color: context.cl.textS, fontSize: 15,
          fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      Text(tr(context, "Ex : PSG, Mbappé, Ligue 1…"),
        style: TextStyle(color: context.cl.textM, fontSize: 13)),
    ]),
  );
}

class _NoResults extends StatelessWidget {
  final String query;
  const _NoResults({required this.query});

  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.sentiment_dissatisfied_rounded,
        size: 52, color: context.cl.textM),
      const SizedBox(height: 16),
      Text(tr(context, "Aucun résultat pour \"{arg0}\"", [query]),
        style: TextStyle(color: context.cl.textS, fontSize: 15,
          fontWeight: FontWeight.w600),
        textAlign: TextAlign.center),
      const SizedBox(height: 6),
      Text(tr(context, "Essayez un autre nom d'équipe, de joueur ou de ligue"),
        style: TextStyle(color: context.cl.textM, fontSize: 13)),
    ]),
  );
}

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
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../shared/providers/favoris_provider.dart';
import '../../../competitions/competitions.dart';

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _ctrl   = TextEditingController();
  String _query = '';
  /// Recherches récentes, comme l'écran de recherche de Sofascore
  /// (10 novembre 2026) : les dernières, en tête quand le champ est vide.
  List<String> _recentes = const [];

  @override
  void initState() {
    super.initState();
    RecherchesRecentes.lire().then((l) { if (mounted) setState(() => _recentes = l); });
  }

  @override
  void dispose() {
    // Ce qu'on cherchait en quittant l'écran devient une recherche récente.
    RecherchesRecentes.ajouter(_query);
    _ctrl.dispose();
    super.dispose();
  }

  void _chercher(String terme) {
    _ctrl.text = terme;
    _ctrl.selection = TextSelection.collapsed(offset: terme.length);
    setState(() => _query = terme);
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
          textInputAction: TextInputAction.search,
          onSubmitted: (v) => RecherchesRecentes.ajouter(v).then((_) => RecherchesRecentes.lire())
              .then((l) { if (mounted) setState(() => _recentes = l); }),
        ),
      ),
      body: terme.length < 2
        ? _Suggestions(
            recentes: _recentes,
            onChercher: _chercher,
            onEffacer: () async {
              await RecherchesRecentes.effacer();
              if (mounted) setState(() => _recentes = const []);
            })
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
        style: TextStyle(color: context.cl.textS, fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0.4))),
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
                  style: TextStyle(color: context.cl.textP, fontSize: 15, fontWeight: FontWeight.w600)),
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
                  style: TextStyle(color: context.cl.textP, fontSize: 15, fontWeight: FontWeight.w600)),
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
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.search_rounded, size: 44, color: context.cl.textM),
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

/// Les recherches récentes, gardées sur le téléphone : huit au plus, la plus
/// récente d'abord, sans doublon.
class RecherchesRecentes {
  RecherchesRecentes._();
  static const cle = 'recherches_recentes';
  static const max = 8;

  static Future<List<String>> lire() async {
    try {
      return (await SharedPreferences.getInstance()).getStringList(cle) ?? const [];
    } catch (_) {
      return const [];
    }
  }

  static Future<void> ajouter(String terme) async {
    final t = terme.trim();
    if (t.length < 2) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final liste = [t, ...(prefs.getStringList(cle) ?? const <String>[])
          .where((x) => x.toLowerCase() != t.toLowerCase())].take(max).toList();
      await prefs.setStringList(cle, liste);
    } catch (_) {}
  }

  static Future<void> effacer() async {
    try {
      await (await SharedPreferences.getInstance()).remove(cle);
    } catch (_) {}
  }
}

/// Le champ vide : recherches récentes, équipes suivies, grandes
/// compétitions — de quoi trouver sans taper, comme Sofascore.
class _Suggestions extends ConsumerWidget {
  final List<String> recentes;
  final ValueChanged<String> onChercher;
  final VoidCallback onEffacer;
  const _Suggestions({required this.recentes, required this.onChercher, required this.onEffacer});

  Widget _titre(BuildContext context, String texte, {Widget? action}) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
    child: Row(children: [
      Expanded(child: Text(texte.toUpperCase(),
        style: TextStyle(color: context.cl.textM, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.6))),
      ?action,
    ]),
  );

  Widget _puce(BuildContext context, {Key? key, required Widget avant, required String texte, required VoidCallback onTap}) =>
      ActionChip(
        key: key,
        avatar: avant,
        label: Text(texte, maxLines: 1, overflow: TextOverflow.ellipsis),
        labelStyle: TextStyle(color: context.cl.textP, fontSize: 13),
        backgroundColor: context.cl.surface,
        side: BorderSide(color: context.cl.border),
        onPressed: onTap,
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final equipes = ref.watch(favorisProvider).valueOrNull?.equipes ?? const <EquipeSuivie>[];
    return ListView(
      key: const Key('suggestions-recherche'),
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 40),
      children: [
        if (recentes.isNotEmpty) ...[
          _titre(context, tr(context, "Recherches récentes"), action: TextButton(
            key: const Key('effacer-recherches'),
            onPressed: onEffacer,
            style: TextButton.styleFrom(minimumSize: const Size(0, 32), padding: const EdgeInsets.symmetric(horizontal: 8)),
            child: Text(tr(context, "Effacer"), style: TextStyle(color: context.cl.accent, fontSize: 13)))),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final r in recentes)
              _puce(context, key: Key('recente-$r'), avant: Icon(Icons.history_rounded, size: 16, color: context.cl.textM),
                texte: r, onTap: () => onChercher(r)),
          ]),
        ],
        if (equipes.isNotEmpty) ...[
          _titre(context, tr(context, "Mes équipes")),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final e in equipes)
              _puce(context, avant: TeamLogoWidget(url: e.logo, size: 18), texte: e.nom,
                onTap: () => ouvrirFicheEquipe(context, nom: e.nom, logo: e.logo, competition: e.competition, id: e.id)),
          ]),
        ],
        _titre(context, tr(context, "Grandes compétitions")),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final c in grandesCompetitions)
            _puce(context, avant: Container(
                width: 20, height: 20, padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                child: TeamLogoWidget(url: c.logo, size: 16)),
              texte: tr(context, c.nom), onTap: () => context.push('/competitions/${c.code}')),
        ]),
        const SizedBox(height: 28),
        _EmptyPrompt(),
      ],
    );
  }
}

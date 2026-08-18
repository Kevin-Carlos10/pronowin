import 'dart:async';
import 'dart:ui';
import '../../../../core/utils/motion.dart';
import '../../../../shared/widgets/confidence_indicator.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../shared/utils/premium_nav.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/services/prono_share_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../bankroll/presentation/widgets/miser_dialog.dart';
import '../../../bankroll/presentation/providers/bankroll_provider.dart';
import '../../../../core/widgets/team_logo_widget.dart';
import '../../../../features/auth/presentation/providers/auth_provider.dart';
import '../../../../features/abonnement/presentation/providers/subscription_provider.dart';
import '../../domain/entities/match_entity.dart';
import '../providers/favorites_provider.dart';
import '../providers/pronostics_provider.dart';
import '../widgets/comments_section.dart';
import '../widgets/prono_share_card.dart';
import '../../../abonnement/presentation/providers/iap_provider.dart';

// Découpé en fichiers `part` : le fichier faisait 3 604 lignes pour une
// quarantaine de classes privées, dont le State d'un bouton situé 500
// lignes après le bouton lui-même.
part 'match_detail/partage.dart';
part 'match_detail/compositions.dart';
part 'match_detail/blessures.dart';
part 'match_detail/classements.dart';
part 'match_detail/face_a_face.dart';
part 'match_detail/analyse_ia.dart';
part 'match_detail/forme.dart';
part 'match_detail/miser.dart';
part 'match_detail/statistiques.dart';
part 'match_detail/analyse_modele.dart';

class MatchDetailPage extends ConsumerStatefulWidget {
  final String       matchId;
  final MatchEntity? preloaded;

  const MatchDetailPage({
    super.key,
    required this.matchId,
    this.preloaded,
  });

  @override
  ConsumerState<MatchDetailPage> createState() => _MatchDetailPageState();
}

class _MatchDetailPageState extends ConsumerState<MatchDetailPage>
    with TickerProviderStateMixin {
  Timer? _liveTimer;

  // ── Onglets à composition variable ──────────────────────────────────────────
  // Les onglets secondaires (compositions, blessures, classements, face-à-face,
  // statistiques) apparaissent au fur et à mesure que leur appel réseau répond.
  // La liste change donc en cours de vie de la page, ce qu'un TabController à
  // longueur fixe n'accepte pas : on le recrée à chaque changement de
  // composition, en reportant la sélection sur le même *libellé* plutôt que sur
  // le même index — sinon l'arrivée d'un onglet décalait celui qu'on lisait.
  TabController? _tabCtrl;
  List<String>   _tabLabels = const [];

  bool _memesOnglets(List<String> labels) {
    if (_tabLabels.length != labels.length) return false;
    for (var i = 0; i < labels.length; i++) {
      if (_tabLabels[i] != labels[i]) return false;
    }
    return true;
  }

  TabController _controleurPour(List<String> labels) {
    final actuel = _tabCtrl;
    if (actuel != null && _memesOnglets(labels)) return actuel;

    final ancien = actuel != null && actuel.index < _tabLabels.length
        ? _tabLabels[actuel.index]
        : null;
    final index = ancien == null ? -1 : labels.indexOf(ancien);

    // Jeter l'ancien dans la frame courante le ferait disposer alors que le
    // TabBar sortant le référence encore.
    if (actuel != null) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => actuel.dispose());
    }

    _tabLabels = labels;
    return _tabCtrl = TabController(
      length: labels.length,
      initialIndex: index < 0 ? 0 : index,
      vsync: this,
    );
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    _tabCtrl?.dispose();
    super.dispose();
  }

  /// Horodatage du dernier rafraîchissement du score, pour l'indicateur de
  /// fraîcheur. Initialisé à l'ouverture de la page : la première donnée
  /// affichée vient d'être chargée.
  DateTime _dernierRefresh = DateTime.now();

  void _startLivePolling() {
    _liveTimer?.cancel();
    _liveTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      ref.invalidate(liveScoreProvider(widget.matchId));
      if (mounted) setState(() => _dernierRefresh = DateTime.now());
    });
  }

  void _stopLivePolling() {
    _liveTimer?.cancel();
    _liveTimer = null;
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final isPremium = authState is AuthAuthenticated && authState.user.isPremium;

    // Utilise la donnée fraîche du provider, avec preloaded comme fallback
    final matchAsync = ref.watch(matchDetailProvider(widget.matchId));
    final match = matchAsync.valueOrNull ?? widget.preloaded;

    // Démarrer/arrêter le polling selon le statut du match
    if (match?.status == MatchStatus.live) {
      if (_liveTimer == null) _startLivePolling();
    } else {
      _stopLivePolling();
    }

    if (match == null) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            onPressed: () => context.pop()),
          title: Text('Détail du match')),
        body: matchAsync.isLoading
          ? Center(child: CircularProgressIndicator(color: AppColors.primary))
          : Center(child: Text('Match introuvable',
              style: TextStyle(color: context.cl.textS))));
    }

    // Le verdict du serveur prime sur le calcul local : c'est lui qui connaît
    // l'état réel de l'abonnement. Le calcul local reste le repli quand la
    // donnée vient du cache ou de l'écran précédent.
    final isLocked = match.isLocked || (match.isPremium && !isPremium);
    final isRefreshing = matchAsync.isLoading && match.status == MatchStatus.live;
    final isFav = ref.watch(favoritesProvider).matchIds.contains(match.id);

    // Onglets style Sofascore — surveillés ici (en plus des cartes elles-mêmes,
    // Riverpod dédoublonne l'appel) pour savoir lesquels construire : un onglet
    // sans donnée n'apparaît pas du tout, plutôt que d'afficher un message vide.
    final lineupsAsync   = ref.watch(lineupsProvider(match.id));
    final injuriesAsync  = ref.watch(injuriesProvider(match.id));
    final standingsAsync = ref.watch(standingsProvider(match.id));
    final h2hAsync       = ref.watch(h2hProvider(match.id));
    final statsAsync     = ref.watch(matchStatsProvider(match.id));

    // Les onglets restent visibles même sur un pronostic verrouillé : ils ne
    // servent que de la donnée de match (compositions, classements,
    // face-à-face...), qui n'a jamais fait partie de l'offre payante. Les
    // masquer ne protégeait rien et transformait la page en cul-de-sac pour
    // les invités comme pour les comptes gratuits.
    final showTabs = match.hasPronostic;

    // Un onglet dont l'appel est encore en vol n'est pas encore affichable —
    // mais il ne doit plus retenir toute la page. « Détails » porte la carte
    // Pronostic, c'est-à-dire la seule raison d'ouvrir cet écran : il s'affiche
    // immédiatement, et les onglets secondaires s'ajoutent à mesure. Avant, un
    // classement de championnat lent cachait le pronostic derrière un spinner
    // plein écran.
    final ongletsEnCours = showTabs && (
      lineupsAsync.isLoading || injuriesAsync.isLoading ||
      standingsAsync.isLoading || h2hAsync.isLoading ||
      statsAsync.isLoading);

    // Un 401 (invité) affiche quand même l'onglet — avec une invite à se
    // connecter à l'intérieur — plutôt que de le cacher comme s'il n'y avait
    // rien à voir.
    bool visibleOrPrompt(AsyncValue<Object?> async, bool Function() hasContent) {
      final status = _statusOf(async.error);
      if (status == 401) return true;
      if (async.isLoading) return false;
      if (async.hasError) return false;
      return hasContent();
    }

    final showCotes        = showTabs && match.status != MatchStatus.finished;
    final showStats        = showTabs && visibleOrPrompt(statsAsync,
      () => statsAsync.valueOrNull != null);
    // Les faits marquants vivent dans l'onglet Détails, pas dans Statistiques.
    final showEvents = showTabs &&
      _EventsList.hasNotable(statsAsync.valueOrNull?.events ?? const []);
    final showCompositions = showTabs && visibleOrPrompt(lineupsAsync,
      () => lineupsAsync.valueOrNull?.available == true);
    final showBlessures    = showTabs && visibleOrPrompt(injuriesAsync,
      () => injuriesAsync.valueOrNull?.isNotEmpty == true);
    // Même condition que la carte elle-même : un classement qui ne contient
    // aucune des deux équipes (tour qualificatif → tableau de la phase de
    // ligue) ne mérite pas son onglet.
    final showClassements  = showTabs && visibleOrPrompt(standingsAsync, () {
      final rows = standingsAsync.valueOrNull;
      return rows != null && rows.isNotEmpty && rows.any((r) =>
          _StandingsCard.memeEquipe(r.teamName, match.homeTeam) ||
          _StandingsCard.memeEquipe(r.teamName, match.awayTeam));
    });
    final showFaceAFace    = showTabs && visibleOrPrompt(h2hAsync,
      () => h2hAsync.valueOrNull?.matches.isNotEmpty == true);

    // Entrée en cascade : chaque carte apparaît légèrement après la précédente,
    // ce qui guide le regard de haut en bas au lieu d'afficher le bloc d'un
    // coup. Supprimée — pas seulement raccourcie — quand l'utilisateur a réduit
    // les animations : un glissement vertical répété sur 6 cartes est
    // précisément ce qui déclenche le mal des transports vestibulaire.
    Widget entree(Widget w, {int delaiMs = 0}) => context.animationsReduites
        ? w
        : w.animate(delay: delaiMs.ms)
            .fadeIn(duration: 350.ms)
            .slideY(begin: 0.06, end: 0, curve: Curves.easeOutCubic);

    // Deux enrobages, parce que le contexte diffère :
    //
    // * dans un NestedScrollView (cas normal, plusieurs onglets), il faut un
    //   CustomScrollView avec un SliverOverlapInjector — c'est lui qui réserve
    //   la place de la barre d'onglets épinglée et qui fait piloter le repli de
    //   l'en-tête par le défilement intérieur ;
    // * sans NestedScrollView (un seul onglet, pas d'en-tête repliable), le
    //   même injecteur lèverait une assertion faute d'ancêtre à qui demander
    //   le handle. Un SingleChildScrollView suffit.
    const rembourrage = EdgeInsets.fromLTRB(16, 16, 16, 24);

    Widget ongletImbrique(Widget child) => Builder(
      builder: (ctx) => CustomScrollView(
        slivers: [
          SliverOverlapInjector(
            handle: NestedScrollView.sliverOverlapAbsorberHandleFor(ctx)),
          SliverPadding(
            padding: rembourrage,
            sliver: SliverToBoxAdapter(child: child),
          ),
        ],
      ),
    );

    Widget ongletSeul(Widget child) =>
        SingleChildScrollView(padding: rembourrage, child: child);

    final tabs = <(String, Widget)>[
      if (showTabs) ('Détails', Column(children: [
        // Entrée en cascade : chaque carte apparaît légèrement après la
        // précédente, ce qui guide le regard de haut en bas au lieu d'afficher
        // le bloc d'un coup.
        if (match.hasPronostic) ...[
          entree(_PronosticCard(match: match, isLocked: isLocked)),
          const SizedBox(height: 16),
        ],
        if (showEvents) ...[
          entree(_MatchEventsCard(matchId: match.id, match: match),
              delaiMs: 90),
          const SizedBox(height: 16),
        ],
        if (match.homeFormPoints > 0 || match.awayFormPoints > 0) ...[
          entree(_FormCard(match: match), delaiMs: 140),
          const SizedBox(height: 16),
        ],
        entree(_AIAnalysisCard(matchId: match.id, status: match.status),
            delaiMs: 190),
        const SizedBox(height: 16),
        // Le « pourquoi » chiffré, juste sous l'analyse : c'est la question que
        // se pose l'utilisateur immédiatement après avoir lu le pronostic.
        entree(_AnalyseModele(matchId: match.id), delaiMs: 210),
        if (match.status == MatchStatus.live) ...[
          const SizedBox(height: 16),
          entree(_CotesEnDirect(matchId: match.id), delaiMs: 230),
        ],
        if (match.status == MatchStatus.finished) ...[
          const SizedBox(height: 16),
          entree(_NotesJoueurs(matchId: match.id), delaiMs: 230),
        ],
        const SizedBox(height: 16),
        if (match.status == MatchStatus.upcoming) ...[
          entree(_MiserButton(match: match), delaiMs: 240),
          const SizedBox(height: 16),
        ],
        if (match.analystNote?.isNotEmpty == true) ...[
          entree(_AnalystCard(match: match), delaiMs: 270),
          const SizedBox(height: 16),
        ],
        entree(CommentsSection(pronosticId: match.id), delaiMs: 310),
      ])),
      if (showCotes) ('Cotes', _OddsCard(match: match)),
      if (showStats) ('Statistiques', Column(children: [
        _MatchStatsCard(matchId: match.id),
        const SizedBox(height: 16),
        _ButsParTranche(matchId: match.id),
      ])),
      if (showCompositions) ('Compositions', _LineupsCard(matchId: match.id)),
      if (showBlessures) ('Blessures', _InjuriesCard(
        matchId: match.id,
        homeTeam: match.homeTeam,
        awayTeam: match.awayTeam,
        homeLogo: match.homeTeamLogo,
        awayLogo: match.awayTeamLogo)),
      if (showClassements) ('Classements', Column(children: [
        _StandingsCard(
          matchId: match.id,
          homeTeam: match.homeTeam,
          awayTeam: match.awayTeam),
        _MeilleursButeurs(leagueCode: match.leagueCountry),
      ])),
      if (showFaceAFace) ('Face à face', _H2HCard(
        matchId: match.id,
        homeLogo: match.homeTeamLogo,
        awayLogo: match.awayTeamLogo)),
    ];

    return Scaffold(
      backgroundColor: context.cl.bg,
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => context.pop()),
        title: Text(match.league,
          style: TextStyle(fontSize: 14, color: context.cl.textS)),
        centerTitle: true,
        actions: [
          // Bouton favori
          IconButton(
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Icon(
                isFav ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                key: ValueKey(isFav),
                size: 22,
                color: isFav ? AppColors.primary : context.cl.textS,
              ),
            ),
            tooltip: isFav ? 'Retirer des favoris' : 'Ajouter aux favoris',
            onPressed: () {
              HapticFeedback.selectionClick();
              // Le détail est ouvert aux invités, mais mettre en favori exige un
              // compte : on les emmène s'inscrire au moment du geste plutôt que
              // de laisser l'appel échouer en 401 sans rien dire.
              if (!ref.read(effectiveLoggedInProvider)) {
                context.push(
                  '/auth/email?from=${Uri.encodeComponent('/pronostics/${match.id}')}');
                return;
              }
              ref.read(favoritesProvider.notifier).toggleMatch(match.id);
            },
          ),
          // Fraîcheur de la donnée : l'écran se rafraîchit toutes les 30 s,
          // mais rien ne le disait. Un score figé et un score à jour avaient
          // exactement la même apparence.
          if (match.status == MatchStatus.live)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: _Fraicheur(enCours: isRefreshing, dernier: _dernierRefresh)),
          IconButton(
              icon: const Icon(Icons.share_rounded, size: 20),
              tooltip: 'Partager',
              onPressed: () {
                HapticFeedback.selectionClick();
                _showShareSheet(context, match);
              },
            ),
          if (match.isPremium)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(
                isPremium
                  ? Icons.workspace_premium_rounded
                  : Icons.lock_rounded,
                color: isPremium ? AppColors.warning : context.cl.textM,
                size: 20)),
        ],
      ),
      body: Column(children: [
        // Page sans barre d'onglets : l'en-tête reste fixe, il n'y a pas
        // d'espace à récupérer.
        if (!showTabs || (tabs.length <= 1 && !ongletsEnCours))
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: context.animationsReduites
              ? _MatchHeader(match: match)
              : _MatchHeader(match: match)
                  .animate().fadeIn(duration: 350.ms)
                  .slideY(begin: -0.04, end: 0, curve: Curves.easeOutCubic),
          ),
        if (!showTabs) ...[
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
              child: Column(children: [
                if (match.hasPronostic) ...[
                  entree(_PronosticCard(match: match, isLocked: isLocked),
                      delaiMs: 130),
                  const SizedBox(height: 16),
                ],
                if (match.status == MatchStatus.finished) ...[
                  entree(_MatchStatsCard(matchId: match.id), delaiMs: 170),
                  const SizedBox(height: 16),
                ],
                if (isLocked)
                  entree(_PremiumBanner(
                      onTap: () => goToPremium(context, ref)),
                      delaiMs: 200),
              ]),
            ),
          ),
        ] else if (tabs.length <= 1 && !ongletsEnCours) ...[
          Expanded(child: ongletSeul(tabs.first.$2)),
        ] else ...[
          // L'en-tête occupait ~23 % de la hauteur d'écran sur *chaque* onglet
          // sans jamais se replier : sur le classement, cela coûtait huit
          // lignes de tableau. NestedScrollView le fait fondre au défilement
          // vers un résumé d'une ligne, la barre d'onglets restant épinglée.
          Expanded(
            child: NestedScrollView(
              headerSliverBuilder: (ctx, _) => [
                SliverOverlapAbsorber(
                  handle: NestedScrollView.sliverOverlapAbsorberHandleFor(ctx),
                  sliver: SliverAppBar(
                    // Le Scaffold porte déjà une AppBar : celle-ci ne doit ni
                    // reprendre un bouton retour, ni réserver la barre d'état.
                    automaticallyImplyLeading: false,
                    primary: false,
                    pinned: true,
                    backgroundColor: context.cl.bg,
                    surfaceTintColor: Colors.transparent,
                    elevation: 0,
                    toolbarHeight: 44,
                    // `expandedHeight` inclut la hauteur de `bottom` : il faut
                    // donc 48 px de plus que la carte elle-même (~225 px) pour
                    // que la barre d'onglets ne la recouvre pas.
                    expandedHeight: 288,
                    titleSpacing: 16,
                    title: _EnTeteCompacte(match: match),
                    flexibleSpace: FlexibleSpaceBar(
                      background: SingleChildScrollView(
                        // Garde-fou : la hauteur de la carte dépend du nom des
                        // équipes (une ou deux lignes) et de la taille de police
                        // système. Un viewport non défilable la laisse prendre sa
                        // hauteur naturelle et la rogne, plutôt que de lever un
                        // débordement RenderFlex sur certains appareils.
                        physics: const NeverScrollableScrollPhysics(),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                          child: _MatchHeader(match: match),
                        ),
                      ),
                    ),
                    bottom: _BarreOnglets(
                      controller: _controleurPour([for (final t in tabs) t.$1]),
                      libelles: [for (final t in tabs) t.$1],
                      enCours: ongletsEnCours,
                    ),
                  ),
                ),
              ],
              body: TabBarView(
                controller: _controleurPour([for (final t in tabs) t.$1]),
                children: [for (final t in tabs) ongletImbrique(t.$2)],
              ),
            ),
          ),
        ],
      ]),
    );
  }
}

// ─── Barre d'onglets ─────────────────────────────────────────────────────────

/// Barre d'onglets epinglee sous l'en-tete repliable.
///
/// `PreferredSizeWidget` parce que `SliverAppBar.bottom` l'exige. Elle porte
/// aussi le fondu lateral et le temoin de chargement des onglets a venir.
class _BarreOnglets extends StatelessWidget implements PreferredSizeWidget {
  final TabController controller;
  final List<String>  libelles;
  final bool          enCours;
  const _BarreOnglets({
    required this.controller, required this.libelles, required this.enCours});

  @override
  Size get preferredSize => const Size.fromHeight(48);

  @override
  Widget build(BuildContext context) => Container(
    color: context.cl.bg,
    height: 48,
    child: Row(children: [
      Expanded(
        // Fondu aux deux bords : la barre se recentre sur l'onglet actif et
        // tronquait le precedent au milieu d'un mot (« ails » pour Details),
        // ce qui se lisait comme un defaut d'affichage plutot que comme
        // « il y en a d'autres a gauche ».
        child: ShaderMask(
          shaderCallback: (rect) => const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              Colors.transparent, Colors.black, Colors.black, Colors.transparent],
            stops: [0.0, 0.045, 0.955, 1.0],
          ).createShader(rect),
          blendMode: BlendMode.dstIn,
          child: TabBar(
            controller: controller,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: AppColors.primary,
            unselectedLabelColor: context.cl.textS,
            indicatorColor: AppColors.primary,
            dividerColor: Colors.transparent,
            labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            unselectedLabelStyle:
                const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            tabs: [for (final l in libelles) Tab(text: l)],
          ),
        ),
      ),
      if (enCours)
        Padding(
          padding: const EdgeInsets.only(left: 2, right: 14),
          child: SizedBox(
            width: 13, height: 13,
            child: CircularProgressIndicator(
              strokeWidth: 1.6, color: context.cl.textM)),
        ),
    ]),
  );
}

/// Resume du match sur une ligne, revele a mesure que l'en-tete se replie.
///
/// `FlexibleSpaceBar` ne sait pas masquer un titre a l'etat deplie : on calcule
/// l'opacite depuis la hauteur restante de la barre.
class _EnTeteCompacte extends ConsumerWidget {
  final MatchEntity match;
  const _EnTeteCompacte({required this.match});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reglages =
        context.dependOnInheritedWidgetOfExactType<FlexibleSpaceBarSettings>();
    final double t = reglages == null
        ? 1
        : ((reglages.maxExtent - reglages.currentExtent) /
                (reglages.maxExtent - reglages.minExtent))
            .clamp(0.0, 1.0);
    // Ne devient visible que sur le dernier tiers du repli, pour ne pas se
    // superposer a l'en-tete complete encore lisible.
    final opacite = ((t - 0.7) / 0.3).clamp(0.0, 1.0);
    if (opacite == 0) return const SizedBox.shrink();

    final live = match.status == MatchStatus.live
        ? ref.watch(liveScoreProvider(match.id)).valueOrNull
        : null;
    final home   = live?.homeScore ?? match.homeScore;
    final away   = live?.awayScore ?? match.awayScore;
    final aScore = match.status != MatchStatus.upcoming;

    return IgnorePointer(
      child: Opacity(
        opacity: opacite,
        child: Row(children: [
          _TeamLogo(url: match.homeTeamLogo ?? '', size: 22),
          const SizedBox(width: 7),
          Flexible(
            child: Text(match.homeTeam,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.cl.textP,
                fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              aScore ? '${home ?? 0} - ${away ?? 0}' : 'VS',
              style: TextStyle(
                color: match.status == MatchStatus.live
                    ? AppColors.success
                    : context.cl.textP,
                fontSize: 14, fontWeight: FontWeight.w800)),
          ),
          Flexible(
            child: Text(match.awayTeam,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: context.cl.textP,
                fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 7),
          _TeamLogo(url: match.awayTeamLogo ?? '', size: 22),
        ]),
      ),
    );
  }
}

// HEADER
class _MatchHeader extends ConsumerWidget {
  final MatchEntity match;
  const _MatchHeader({required this.match});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Écouter le score live si match en cours
    final liveAsync = match.status == MatchStatus.live
        ? ref.watch(liveScoreProvider(match.id))
        : null;
    final homeScore = liveAsync?.valueOrNull?.homeScore ?? match.homeScore;
    final awayScore = liveAsync?.valueOrNull?.awayScore ?? match.awayScore;
    final isRefreshingScore = liveAsync?.isLoading ?? false;
    final minute = liveAsync?.valueOrNull?.elapsed;

    final d = match.matchDate;
    final dateStr = '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/${d.year}';
    final heureStr = '${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';

    // Sur un match à venir, l'heure est déjà affichée en grand sous le « VS » :
    // la répéter dans la pastille donnait deux fois la même information à dix
    // pixels d'écart. Sur un match joué, il n'y a plus de bloc heure — la
    // pastille la porte donc seule.
    final dateTimeStr = match.status == MatchStatus.upcoming
        ? dateStr
        : '$dateStr · $heureStr';

    final etat = switch (match.status) {
      MatchStatus.live     => minute == null
                                ? 'en direct'
                                : 'en direct, ${minute}e minute',
      MatchStatus.finished => 'terminé',
      _                    => 'à venir',
    };
    final scoreParle = match.status == MatchStatus.upcoming
        ? 'contre'
        : '${homeScore ?? 0} à ${awayScore ?? 0} contre';

    return Semantics(
    label: '${match.league}. ${match.homeTeam} $scoreParle ${match.awayTeam}. '
           'Match $etat, le $dateStr à $heureStr.',
    excludeSemantics: true,
    child: Container(
    padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFF151B2E), Color(0xFF0D1220)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(
        color: match.status == MatchStatus.live
            ? AppColors.error.withValues(alpha: 0.5)
            : context.cl.border,
        width: match.status == MatchStatus.live ? 1.5 : 0.5,
      ),
      boxShadow: match.status == MatchStatus.live
          ? [BoxShadow(color: AppColors.error.withValues(alpha: 0.1), blurRadius: 20)]
          : [],
    ),
    child: Column(children: [
      // Pill date/heure centrée — la ligue est déjà dans l'AppBar, pas besoin de la répéter ici
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: context.cl.surfaceDeep,
          borderRadius: BorderRadius.circular(20)),
        child: Text(dateTimeStr,
          style: TextStyle(
            color: context.cl.textS, fontSize: 12.5, fontWeight: FontWeight.w600)),
      ),
      const SizedBox(height: 22),

      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Domicile
        Expanded(child: Column(children: [
          Hero(
            tag: 'team_home_${match.homeTeam}',
            child: _TeamLogo(url: match.homeTeamLogo ?? '', size: 64),
          ),
          SizedBox(height: 10),
          Text(match.homeTeam,
            style: TextStyle(color: context.cl.textP,
              fontSize: 14, fontWeight: FontWeight.w700),
            textAlign: TextAlign.center,
            maxLines: 2, overflow: TextOverflow.ellipsis),
        ])),

        // Score / statut central
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(children: [
            if (match.status == MatchStatus.finished) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: context.cl.surfaceDeep,
                  borderRadius: BorderRadius.circular(6)),
                child: Text('TERMINÉ',
                  style: TextStyle(
                    color: context.cl.textM, fontSize: 9,
                    fontWeight: FontWeight.w700, letterSpacing: 0.5)),
              ),
              const SizedBox(height: 8),
            ] else if (match.status == MatchStatus.live) ...[
              _LiveBadge(minute: minute),
              const SizedBox(height: 8),
            ],
            Container(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: match.status == MatchStatus.live
                  ? AppColors.success.withValues(alpha: 0.08)
                  : context.cl.surfaceDeep,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: match.status == MatchStatus.live
                    ? AppColors.success.withValues(alpha: 0.3)
                    : context.cl.borderSoft,
                  width: match.status == MatchStatus.live ? 1.5 : 0.5)),
              child: Text(
                match.status == MatchStatus.live || match.status == MatchStatus.finished
                  ? '${homeScore ?? 0} - ${awayScore ?? 0}'
                  : 'VS',
                style: TextStyle(
                  color: match.status == MatchStatus.live
                    ? AppColors.success
                    : context.cl.textP,
                  fontSize: 24, fontWeight: FontWeight.w800,
                  letterSpacing: 2))),
            if (isRefreshingScore) ...[
              const SizedBox(height: 6),
              SizedBox(width: 12, height: 12,
                child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.success)),
            ] else if (match.status == MatchStatus.upcoming) ...[
              const SizedBox(height: 6),
              Text(heureStr,
                style: TextStyle(
                  color: context.cl.textS,
                  fontSize: 14, fontWeight: FontWeight.w600)),
            ],
          ]),
        ),

        // Extérieur
        Expanded(child: Column(children: [
          Hero(
            tag: 'team_away_${match.awayTeam}',
            child: _TeamLogo(url: match.awayTeamLogo ?? '', size: 64),
          ),
          SizedBox(height: 10),
          Text(match.awayTeam,
            style: TextStyle(color: context.cl.textP,
              fontSize: 14, fontWeight: FontWeight.w700),
            textAlign: TextAlign.center,
            maxLines: 2, overflow: TextOverflow.ellipsis),
        ])),
      ]),
    ]),
  ));
  }
}

// PRONOSTIC
class _PronosticCard extends StatelessWidget {
  final MatchEntity match;
  final bool isLocked;
  const _PronosticCard({required this.match, required this.isLocked});

  /// Les libellés composés par le formulaire admin ont la forme
  /// "Marché : Choix" (ex. "Vainqueur du match : PSV Eindhoven"). On les coupe
  /// au premier ':' pour hiérarchiser l'affichage. Un libellé sans séparateur
  /// (ex. "Les deux équipes marquent") reste affiché tel quel comme choix.
  int get _sep => match.displayPredictionLabel.indexOf(':');

  String? get _market => _sep <= 0
      ? null
      : match.displayPredictionLabel.substring(0, _sep).trim();

  String get _pick => _sep <= 0
      ? match.displayPredictionLabel
      : match.displayPredictionLabel.substring(_sep + 1).trim();

  /// Ce que le lecteur d'écran annonce pour la carte entière. Lue widget par
  /// widget, elle donnait « PRONOSTIC », « TOTAL BUTS +/- », « Plus de 1.5 »,
  /// « COTE », « 1.18 », « CONFIANCE », « 95% », « Excellent » — huit fragments
  /// dont aucun ne dit qu'ils forment un même pari.
  String _annonce(BuildContext context) {
    if (isLocked) {
      return 'Pronostic réservé aux membres Premium.';
    }
    final marche = _market == null ? '' : '${_market!}, ';
    final cote = match.oddsRecommended > 0
        ? ' Cote recommandée ${match.oddsRecommended.toStringAsFixed(2)}.'
        : '';
    final verdict = switch (match.result) {
      PronosticResult.win  => ' Pronostic gagnant.',
      PronosticResult.loss => ' Pronostic perdant.',
      PronosticResult.push => ' Pronostic remboursé.',
      null                 => '',
    };
    return 'Pronostic : $marche$_pick.$cote '
        'Indice de confiance ${MatchEntity.percentForConfidence(match.confidenceScore)} '
        'pour cent, ${MatchEntity.labelForConfidence(match.confidenceScore)}.$verdict';
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: _annonce(context),
    excludeSemantics: true,
    child: Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      gradient: isLocked ? null : LinearGradient(
        colors: [Color(0xFF1A2040), Color(0xFF0D1530)],
        begin: Alignment.topLeft, end: Alignment.bottomRight),
      color: isLocked ? context.cl.surface : null,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: isLocked
          ? context.cl.border
          : AppColors.primary.withValues(alpha: 0.45),
        width: isLocked ? 0.5 : 1.2),
      // Halo discret : c'est la carte maîtresse de l'onglet, elle doit se
      // détacher des cartes d'information qui la suivent (toutes plates).
      boxShadow: isLocked ? null : [BoxShadow(
        color: AppColors.primary.withValues(alpha: 0.14),
        blurRadius: 20, offset: const Offset(0, 6))],
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('PRONOSTIC', style: TextStyle(
        color: context.cl.textM, fontSize: 11,
        fontWeight: FontWeight.w600, letterSpacing: 1)),
      SizedBox(height: 14),

      if (isLocked)
        Row(children: [
          Icon(Icons.lock_rounded, color: context.cl.textM, size: 20),
          SizedBox(width: 10),
          Expanded(child: Text('Contenu réservé aux membres Premium',
            style: TextStyle(color: context.cl.textM, fontSize: 14))),
        ])
      else ...[
        // Marché en surtitre + choix en gros : se lit comme un ticket de pari,
        // au lieu d'une longue phrase qui passe à la ligne.
        if (_market != null) ...[
          Text(_market!.toUpperCase(),
            style: const TextStyle(
              color: AppColors.primary,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8)),
          const SizedBox(height: 7),
        ],
        Text(_pick,
          style: TextStyle(
            color: context.cl.textP,
            fontSize: 22,
            fontWeight: FontWeight.w800,
            height: 1.2)),
        const SizedBox(height: 16),
        Container(height: 1, color: context.cl.borderSoft),
        const SizedBox(height: 14),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (match.oddsRecommended > 0) ...[
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('COTE',
                style: TextStyle(
                  color: context.cl.textM,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8)),
              const SizedBox(height: 7),
              Text(match.oddsRecommended.toStringAsFixed(2),
                style: TextStyle(
                  color: context.cl.textP,
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  height: 1)),
            ]),
            const SizedBox(width: 28),
          ],
          // Une fois le résultat connu, la confiance est rétrospective : elle
          // n'aide plus à décider, elle ne fait que documenter. Elle passe donc
          // d'une jauge pleine largeur à une mention discrète, et rend la place
          // au rendement, qui est l'information que le parieur cherche
          // vraiment sur un pronostic clos.
          if (match.result == null)
            Expanded(child: _DetailConfidenceBar(score: match.confidenceScore))
          else ...[
            if (match.oddsRecommended > 0)
              Expanded(child: _RendementBox(odds: match.oddsRecommended,
                  result: match.result!)),
            const SizedBox(width: 20),
            _ConfianceRappel(score: match.confidenceScore),
          ],
        ]),
      ],

      // Verdict intégré à la carte : le pronostic et son issue racontent la
      // même histoire, les séparer en deux blocs obligeait à répéter la cote.
      if (match.result != null) ...[
        const SizedBox(height: 16),
        _VerdictStrip(result: match.result!, pronosticId: match.id),
      ],
    ]),
  ));
}

/// Rendement d'un pronostic clos, exprimé pour une mise de référence.
///
/// « Cote 1.18 » et « Pronostic gagnant » sont deux faits que le parieur devait
/// multiplier de tête. Sur un marché à faible cote c'est précisément le calcul
/// qui décide si le pari valait la peine — autant le poser.
class _RendementBox extends StatelessWidget {
  final double odds;
  final PronosticResult result;
  const _RendementBox({required this.odds, required this.result});

  /// Mise de référence en FCFA. Volontairement ronde et non paramétrable : il
  /// s'agit d'illustrer un rendement, pas de simuler la bankroll de
  /// l'utilisateur — celle-ci a sa propre page, avec ses vrais montants.
  static const double _miseReference = 1000;

  @override
  Widget build(BuildContext context) {
    final (libelle, montant, couleur) = switch (result) {
      PronosticResult.win => (
        'AURAIT RAPPORTÉ',
        '+${((odds - 1) * _miseReference).round()}',
        AppColors.success,
      ),
      PronosticResult.loss => (
        'AURAIT COÛTÉ',
        '-${_miseReference.round()}',
        AppColors.error,
      ),
      PronosticResult.push => ('MISE RENDUE', '±0', AppColors.info),
    };

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(libelle,
        style: TextStyle(
          color: context.cl.textM,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8)),
      const SizedBox(height: 7),
      Row(crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Flexible(
            child: Text(montant,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: couleur, fontSize: 19,
                fontWeight: FontWeight.w800, height: 1)),
          ),
          const SizedBox(width: 4),
          Text('F  · mise ${_miseReference.round()}',
            style: TextStyle(color: context.cl.textM, fontSize: 10)),
        ]),
    ]);
  }
}

/// Rappel discret de la confiance annoncée avant le coup d'envoi, une fois le
/// résultat connu. La jauge pleine largeur laisse la place au rendement.
class _ConfianceRappel extends StatelessWidget {
  final int score;
  const _ConfianceRappel({required this.score});

  @override
  Widget build(BuildContext context) {
    final couleur = ConfidenceIndicator.colorFor(score);
    return Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
      Text('CONFIANCE ANNONCÉE',
        style: TextStyle(
          color: context.cl.textM,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8)),
      const SizedBox(height: 7),
      Text('${MatchEntity.percentForConfidence(score)} %',
        style: TextStyle(
          color: couleur.withValues(alpha: 0.75),
          fontSize: 15,
          fontWeight: FontWeight.w700,
          height: 1.2)),
    ]);
  }
}

/// Bandeau d'issue affiché au pied de la carte Pronostic. La cote n'y figure
/// pas : elle est déjà juste au-dessus dans la même carte.
class _VerdictStrip extends StatefulWidget {
  final PronosticResult result;
  final String pronosticId;
  const _VerdictStrip({required this.result, required this.pronosticId});

  @override
  State<_VerdictStrip> createState() => _VerdictStripState();
}

class _VerdictStripState extends State<_VerdictStrip>
    with SingleTickerProviderStateMixin {
  static const _prefKey = 'celebrated_win_';

  /// Un seul contrôleur pilote toute la chorégraphie : les quatre gestes
  /// doivent être calés les uns sur les autres à la milliseconde près, ce que
  /// quatre contrôleurs indépendants ne garantissent pas.
  late final AnimationController _c = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 1150));

  /// Le bandeau se pose : 0,94 → 1 avec un léger dépassement. `easeOutBack`
  /// et non un rebond — on veut un objet qui se stabilise, pas qui saute.
  late final Animation<double> _pose = CurvedAnimation(
      parent: _c, curve: const Interval(0.00, 0.40, curve: Curves.easeOutBack));

  /// La coche arrive après le bandeau, jamais en même temps : l'œil se pose
  /// d'abord sur la forme, puis lit la confirmation.
  late final Animation<double> _coche = CurvedAnimation(
      parent: _c, curve: const Interval(0.14, 0.54, curve: Curves.easeOutBack));

  /// Halo qui éclôt puis retombe à son niveau de repos. C'est ce qui remplace
  /// les confettis : signaler par la lumière plutôt que par des objets qui
  /// jaillissent d'un point où rien n'a explosé.
  late final Animation<double> _halo = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0)
        .chain(CurveTween(curve: Curves.easeOutCubic)), weight: 35),
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.30)
        .chain(CurveTween(curve: Curves.easeInOutCubic)), weight: 65),
  ]).animate(CurvedAnimation(
      parent: _c, curve: const Interval(0.06, 1.00)));

  /// Balayage spéculaire : une bande de lumière traverse le bandeau **une
  /// fois**. C'est le signal « objet de qualité » — du métal ou du verre qui
  /// accroche la lumière. En boucle, il deviendrait un gyrophare.
  late final Animation<double> _reflet = CurvedAnimation(
      parent: _c, curve: const Interval(0.34, 0.86, curve: Curves.easeInOutCubic));

  @override
  void initState() {
    super.initState();
    if (widget.result == PronosticResult.win) _peutEtreCelebrer();
  }

  /// La célébration ne se joue qu'à la première consultation d'un pronostic
  /// gagnant — y revenir ne la rejoue pas.
  Future<void> _peutEtreCelebrer() async {
    final prefs = await SharedPreferences.getInstance();
    final cle   = '$_prefKey${widget.pronosticId}';
    if ((prefs.getBool(cle) ?? false) || !mounted) return;

    // Marqué comme vu dans tous les cas, y compris en animations réduites :
    // sinon la célébration se déclencherait au premier changement de réglage,
    // sur un pronostic vieux de trois semaines.
    await prefs.setBool(cle, true);
    if (!mounted || context.animationsReduites) return;

    await Future.delayed(const Duration(milliseconds: 160));
    if (!mounted) return;

    // `mediumImpact` et non `vibrate` : une frappe nette, calée sur l'arrivée
    // de la coche. `vibrate` est un bourdonnement de notification — le retour
    // le plus grossier de la plateforme.
    HapticFeedback.mediumImpact();
    _c.forward();
  }

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final isWin  = widget.result == PronosticResult.win;
    final isPush = widget.result == PronosticResult.push;
    final color  = isWin ? AppColors.success : isPush ? AppColors.info : AppColors.error;
    final icon   = isWin  ? Icons.check_circle_rounded
                 : isPush ? Icons.replay_rounded
                 : Icons.cancel_rounded;
    final label  = isWin  ? 'Pronostic gagnant'
                 : isPush ? 'Pronostic remboursé'
                 : 'Pronostic perdant';

    // Hors victoire — ou en animations réduites — le bandeau est simplement
    // affiché. Une défaite ne se met pas en scène.
    if (!isWin || context.animationsReduites) {
      return _bandeau(context, color, icon, label, echelle: 1, coche: 1);
    }

    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final halo = _halo.value;
        return Transform.scale(
          scale: 0.94 + 0.06 * _pose.value,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(
                color: color.withValues(alpha: 0.34 * halo),
                blurRadius: 10 + 22 * halo,
                spreadRadius: 1 + 2 * halo,
              )],
            ),
            child: _bandeau(context, color, icon, label,
                echelle: _pose.value, coche: _coche.value, reflet: _reflet.value),
          ),
        );
      },
    );
  }

  Widget _bandeau(
    BuildContext context, Color color, IconData icon, String label, {
    required double echelle,
    required double coche,
    double? reflet,
  }) {
    final contenu = Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 1)),
      child: Row(children: [
        Transform.scale(
          scale: 0.55 + 0.45 * coche,
          child: Opacity(opacity: coche.clamp(0.0, 1.0),
            child: Icon(icon, color: color, size: 20)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Opacity(
            opacity: echelle.clamp(0.0, 1.0),
            child: Text(label,
              style: TextStyle(
                color: color, fontSize: 14, fontWeight: FontWeight.w800)),
          ),
        ),
      ]),
    );

    if (reflet == null) return contenu;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(children: [
        contenu,
        // La bande traverse de −1,4 à 1,4 en largeur relative : elle entre et
        // sort complètement du cadre, sans jamais s'arrêter au milieu.
        Positioned.fill(
          child: IgnorePointer(
            child: FractionallySizedBox(
              widthFactor: 0.45,
              alignment: Alignment(-1.4 + 2.8 * reflet, 0),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white.withValues(alpha: 0),
                      Colors.white.withValues(alpha: 0.16),
                      Colors.white.withValues(alpha: 0),
                    ],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

// COTES
class _OddsCard extends StatelessWidget {
  final MatchEntity match;
  const _OddsCard({required this.match});

  bool get _hasOdds =>
    match.oddsHome > 0 || match.oddsDraw > 0 || match.oddsAway > 0;

  @override
  Widget build(BuildContext context) {
    if (!_hasOdds) return const SizedBox.shrink();

    // La pastille verte ne signale la cote recommandée que si le pronostic
    // porte sur le marché « vainqueur ». Sur un « Double chance » ou un
    // « Total buts », les trois cotes 1/X/2 n'ont aucun rapport avec le
    // pronostic, et la seule cote qui compte n'apparaissait nulle part.
    final surMarcheVainqueur = match.predictionType == PredictionType.win1 ||
                               match.predictionType == PredictionType.draw ||
                               match.predictionType == PredictionType.win2;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (match.oddsRecommended > 0 && !surMarcheVainqueur) ...[
        _CoteRecommandee(match: match),
        const SizedBox(height: 12),
      ],
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: context.cl.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.cl.border, width: 0.5)),
        child: Row(children: [
          // Le marché est nommé : « COTES » seul laissait croire que ces trois
          // valeurs étaient celles du pronostic.
          Flexible(
            child: Text('VAINQUEUR DU MATCH',
              maxLines: 2,
              style: TextStyle(
                color: context.cl.textM, fontSize: 9.5,
                fontWeight: FontWeight.w700, letterSpacing: 0.6)),
          ),
          const SizedBox(width: 10),
          _OddPill(label: '1', value: match.oddsHome,
            isRecommended: match.predictionType == PredictionType.win1),
          const SizedBox(width: 8),
          _OddPill(label: 'X', value: match.oddsDraw,
            isRecommended: match.predictionType == PredictionType.draw),
          const SizedBox(width: 8),
          _OddPill(label: '2', value: match.oddsAway,
            isRecommended: match.predictionType == PredictionType.win2),
        ]),
      ),
      if (match.status == MatchStatus.live) ...[
        const SizedBox(height: 10),
        Row(children: [
          Icon(Icons.info_outline_rounded, size: 13, color: context.cl.textM),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              "Cotes d'ouverture — elles ne suivent pas le match en cours.",
              style: TextStyle(color: context.cl.textM, fontSize: 11, height: 1.3)),
          ),
        ]),
      ],
    ]);
  }
}

/// La cote du pronostic, mise en avant au-dessus du marché « vainqueur ».
///
/// Ne s'affiche que lorsque le pronostic ne porte PAS sur le 1X2 : sinon la
/// pastille verte du marché fait déjà le travail, et deux fois la même valeur
/// à quelques pixels d'écart est du bruit.
class _CoteRecommandee extends StatelessWidget {
  final MatchEntity match;
  const _CoteRecommandee({required this.match});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    decoration: BoxDecoration(
      color: AppColors.success.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: AppColors.success.withValues(alpha: 0.35), width: 1.2)),
    child: Row(children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('COTE DU PRONOSTIC',
            style: TextStyle(
              color: context.cl.textM, fontSize: 9.5,
              fontWeight: FontWeight.w700, letterSpacing: 0.6)),
          const SizedBox(height: 5),
          Text(match.displayPredictionLabel,
            maxLines: 2, overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: context.cl.textP, fontSize: 13,
              fontWeight: FontWeight.w700, height: 1.25)),
        ]),
      ),
      const SizedBox(width: 12),
      Text(match.oddsRecommended.toStringAsFixed(2),
        style: const TextStyle(
          color: AppColors.success, fontSize: 22,
          fontWeight: FontWeight.w800, height: 1)),
    ]),
  );
}

class _OddPill extends StatelessWidget {
  final String label;
  final double value;
  final bool isRecommended;
  const _OddPill({required this.label, required this.value, this.isRecommended = false});

  @override
  Widget build(BuildContext context) => Container(
    width: 48,
    padding: const EdgeInsets.symmetric(vertical: 6),
    decoration: BoxDecoration(
      color: isRecommended
        ? AppColors.success.withValues(alpha: 0.12)
        : context.cl.surfaceDeep,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(
        color: isRecommended
          ? AppColors.success.withValues(alpha: 0.4)
          : context.cl.borderSoft,
        width: isRecommended ? 1.2 : 0.5)),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(label, style: TextStyle(
          color: isRecommended ? AppColors.success : context.cl.textM,
          fontSize: 9, fontWeight: FontWeight.w700)),
        if (isRecommended) ...[
          const SizedBox(width: 2),
          const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 9),
        ],
      ]),
      Text(value > 0 ? value.toStringAsFixed(2) : '—',
        style: TextStyle(
          color: isRecommended ? AppColors.success : context.cl.textP,
          fontSize: 14, fontWeight: FontWeight.w800)),
    ]),
  );
}

// NOTE ANALYSTE
class _AnalystCard extends StatelessWidget {
  final MatchEntity match;
  const _AnalystCard({required this.match});

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: context.cl.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: context.cl.border, width: 0.5)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(
          width: 38, height: 38,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.12),
            shape: BoxShape.circle),
          child: Icon(Icons.person_rounded, color: AppColors.primary, size: 20)),
        SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('ANALYSE DE L\'EXPERT', style: TextStyle(
            color: context.cl.textM, fontSize: 11,
            fontWeight: FontWeight.w600, letterSpacing: 1)),
          Text('Notre Analyste', style: TextStyle(
            color: context.cl.textS, fontSize: 12)),
        ]),
      ]),
      SizedBox(height: 14),
      Text(match.analystNote!, style: TextStyle(
        color: context.cl.textS, fontSize: 14, height: 1.7)),
    ]),
  );
}

// BANNIERE PREMIUM
class _PremiumBanner extends ConsumerStatefulWidget {
  final VoidCallback onTap;
  const _PremiumBanner({required this.onTap});
  @override
  ConsumerState<_PremiumBanner> createState() => _PremiumBannerState();
}

class _PremiumBannerState extends ConsumerState<_PremiumBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _pressCtrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _pressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 85),
      reverseDuration: const Duration(milliseconds: 150),
    );
    _scale = Tween(begin: 1.0, end: 0.97).animate(
      CurvedAnimation(parent: _pressCtrl, curve: Curves.easeOut));
  }

  @override
  void dispose() { _pressCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final sub = ref.watch(currentSubscriptionProvider).valueOrNull ?? const {};
    // Sur un build store le tarif est majoré (commission Apple/Google) :
    // annoncer le prix Mobile Money afficherait moins que le montant débité.
    final priceLabel = '${premiumMonthlyPriceLabel(ref, sub)}/mois';
    return GestureDetector(
    onTapDown: (_) => _pressCtrl.forward(),
    onTapUp: (_) { _pressCtrl.reverse(); HapticFeedback.lightImpact(); widget.onTap(); },
    onTapCancel: () => _pressCtrl.reverse(),
    child: ScaleTransition(scale: _scale, child: Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A2040), Color(0xFF0D1530)],
          begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.4), width: 1)),
      child: Row(children: [
        Container(
          width: 50, height: 50,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(14)),
          child: const Icon(Icons.workspace_premium_rounded,
            color: AppColors.primaryLight, size: 28)),
        SizedBox(width: 14),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Accès Premium requis', style: TextStyle(
            color: context.cl.textP, fontSize: 15,
            fontWeight: FontWeight.w700)),
          SizedBox(height: 3),
          Text('Pronostic, cotes et analyse complète',
            style: TextStyle(color: context.cl.textS, fontSize: 12)),
        ])),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(20)),
          child: Text(priceLabel, style: const TextStyle(
            color: Colors.white, fontSize: 12,
            fontWeight: FontWeight.w700)))
          .animate(onPlay: (c) {
            if (!context.animationsReduites) c.repeat();
          })
          .shimmer(duration: 2000.ms, delay: 600.ms, color: Colors.white30),
      ]),
    )),
  );
  }
}

// WIDGETS UTILITAIRES
class _TeamLogo extends StatelessWidget {
  final String url;
  final double size;
  const _TeamLogo({required this.url, this.size = 40});
  @override
  Widget build(BuildContext context) =>
      TeamLogoWidget(url: url.isEmpty ? null : url, size: size);
}

/// Âge de la donnée en direct, dans la barre de titre.
///
/// Un rond qui tourne pendant l'appel, puis « il y a 12 s » qui vieillit en
/// continu. Sans lui, un score gelé par une panne réseau était indiscernable
/// d'un score à jour.
class _Fraicheur extends StatefulWidget {
  final bool     enCours;
  final DateTime dernier;
  const _Fraicheur({required this.enCours, required this.dernier});

  @override
  State<_Fraicheur> createState() => _FraicheurState();
}

class _FraicheurState extends State<_Fraicheur> {
  Timer? _tic;

  @override
  void initState() {
    super.initState();
    // Une seconde suffit : le libellé ne change qu'à la seconde près.
    _tic = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() { _tic?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    if (widget.enCours) {
      return const Padding(
        padding: EdgeInsets.only(right: 8),
        child: SizedBox(width: 16, height: 16,
          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.error)),
      );
    }

    final secondes = DateTime.now().difference(widget.dernier).inSeconds;
    final libelle  = secondes < 5
        ? 'à jour'
        : secondes < 60
          ? 'il y a ${secondes}s'
          : 'il y a ${(secondes / 60).floor()} min';

    return Semantics(
      label: 'Score mis à jour $libelle',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.sync_rounded, size: 12, color: context.cl.textM),
          const SizedBox(width: 4),
          Text(libelle,
            style: TextStyle(color: context.cl.textM, fontSize: 10.5)),
        ]),
      ),
    );
  }
}

class _LiveBadge extends StatefulWidget {
  /// Minute de jeu. Null tant que la source ne l'a pas fournie : on retombe
  /// alors sur le libellé seul plutôt que d'inventer un chiffre.
  final int? minute;
  const _LiveBadge({this.minute});

  @override
  State<_LiveBadge> createState() => _LiveBadgeState();
}

class _LiveBadgeState extends State<_LiveBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _pulse = Tween<double>(begin: 0.4, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Une pastille qui clignote sans fin est exactement le mouvement que le
    // réglage « réduire les animations » vise. Sans pulsation, le point reste
    // rouge plein : l'information « en direct » est intacte.
    if (context.animationsReduites) {
      _ctrl.stop();
      _ctrl.value = 1;
    } else if (!_ctrl.isAnimating) {
      _ctrl.repeat(reverse: true);
    }
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: widget.minute == null
        ? 'Match en direct'
        : 'Match en direct, ${widget.minute}e minute',
    excludeSemantics: true,
    child: Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: AppColors.error.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: AppColors.error.withValues(alpha: 0.4), width: 0.5),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      AnimatedBuilder(
        animation: _pulse,
        builder: (_, _) => Container(
          width: 7, height: 7,
          decoration: BoxDecoration(
            color: AppColors.error.withValues(alpha: _pulse.value),
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(
              color: AppColors.error.withValues(alpha: _pulse.value * 0.6),
              blurRadius: 4,
            )],
          ),
        ),
      ),
      const SizedBox(width: 6),
      Text(widget.minute == null ? 'EN DIRECT' : "${widget.minute}'",
        style: const TextStyle(
          color: AppColors.error, fontSize: 11,
          fontWeight: FontWeight.w700, letterSpacing: 0.5)),
    ])));
}

class _DetailConfidenceBar extends StatelessWidget {
  final int score;
  const _DetailConfidenceBar({required this.score});

  /// Couleur et libellé viennent tous deux de la source unique. Cette classe
  /// avait sa propre échelle à 5 couleurs là où le reste de l'app en utilise 3 :
  /// un score de 4 s'affichait vert-lime ici et vert ailleurs, pour la même
  /// donnée sur deux écrans voisins.
  Color get _color => ConfidenceIndicator.colorFor(score);

  String get _label => MatchEntity.labelForConfidence(score);

  @override
  Widget build(BuildContext context) {
    final percent = MatchEntity.percentForConfidence(score);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text('CONFIANCE',
              style: TextStyle(
                  color: context.cl.textM,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8)),
          const Spacer(),
          TweenAnimationBuilder<int>(
            tween: IntTween(begin: 0, end: percent),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (_, val, child) => Text('$val%',
                style: TextStyle(
                    color: _color, fontSize: 15, fontWeight: FontWeight.w800,
                    height: 1)),
          ),
        ]),
        const SizedBox(height: 7),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: percent / 100),
          duration: const Duration(milliseconds: 900),
          curve: Curves.easeOutCubic,
          builder: (_, val, child) => ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: val,
              minHeight: 6,
              backgroundColor: context.cl.borderSoft,
              valueColor: AlwaysStoppedAnimation<Color>(_color),
            ),
          ),
        ),
        const SizedBox(height: 5),
        Text(_label,
            style: TextStyle(
                color: _color, fontSize: 10.5, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

// ─── PARTAGE ─────────────────────────────────────────────────────────────────

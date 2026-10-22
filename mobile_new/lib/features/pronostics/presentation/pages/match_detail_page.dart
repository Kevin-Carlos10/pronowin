import 'package:pronowin/l10n/football_labels.dart';
import 'package:pronowin/l10n/app_strings.dart';
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
import '../../../../core/config/distribution_channel.dart';
import '../../../../shared/utils/montant.dart';
import '../../../../shared/utils/premium_nav.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/services/prono_share_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/utils/verrou_pronostic.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../bankroll/presentation/widgets/miser_dialog.dart';
import '../../../bankroll/presentation/providers/bankroll_provider.dart';
import '../../../../core/widgets/image_distante.dart';
import '../../../../core/widgets/team_logo_widget.dart';
import '../../../../shared/providers/favoris_provider.dart';
import '../../../../shared/widgets/suivre_match.dart';
import '../../../../features/auth/presentation/providers/auth_provider.dart';
import '../../../../features/abonnement/presentation/providers/subscription_provider.dart';
import '../../domain/entities/match_entity.dart';
import '../../domain/chrono_match.dart';
import '../providers/pronostics_provider.dart';
import '../providers/match_info_provider.dart';
import '../providers/fiche_match_provider.dart';
import '../widgets/comments_section.dart';
import '../widgets/fil_evenements.dart';
import '../widgets/infos_joueurs.dart';
import '../widgets/prono_share_card.dart';
import '../../../abonnement/presentation/providers/iap_provider.dart';
import 'match_detail/bookmaker_cotes.dart';
import '../../../joueurs/presentation/pages/fiche_joueur_page.dart';
import '../../../equipes/presentation/pages/fiche_equipe_page.dart';
import '../../../../core/utils/noms_equipes.dart';
import '../../domain/entities/avis_compares.dart';
import '../../domain/entities/verdict_comparaison.dart';
import '../../../../shared/utils/retour.dart';
import '../../../../core/config/bookmaker_affiliation.dart';
import '../../../../core/services/analyse_usage.dart';
import '../../../../core/network/failures.dart';
import '../../../../shared/widgets/erreur_chargement.dart';
import '../../../../shared/utils/messages.dart';
import '../../../../shared/widgets/logo_marque.dart';
import 'package:pronowin/core/config/sans_pari.dart';


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
part 'match_detail/informations.dart';
part 'match_detail/analyse_modele.dart';
part 'match_detail/toutes_cotes.dart';

/// La carte des palmarès d'une compétition, seule, pour les bancs d'essai.
@visibleForTesting
Widget palmaresCompetitionSeul(String leagueCode) => _MeilleursButeurs(leagueCode: leagueCode);

/// « Pourquoi ce pronostic » seul, pour les bancs d'essai.
@visibleForTesting
Widget analyseModeleSeule(String matchId) => _AnalyseModele(matchId: matchId);


@visibleForTesting
Widget formeRecenteSeule(MatchEntity match) => _FormeRecente(match: match);

/// Ou revenir quand la page a ete ouverte sans historique —
/// par un lien profond de notification, qui remplace la pile.
const _repli = '/pronostics';

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
    with TickerProviderStateMixin, WidgetsBindingObserver {
  Timer? _liveTimer;
  bool _releveEnCours = false;
  String? _statutDuFlux;
  DateTime? _dernieresStats;
  DateTime? _dernieresCotes;
  DateTime? _dernieresCompositions;

  /// L'application est-elle au premier plan ?
  bool _premierPlan = true;

  /// La bulle qui présente la cloche, une fois par appareil (22 octobre
  /// 2026) : les alertes des matchs suivis — buts, mi-temps, cartons rouges,
  /// compositions, résumé — ne touchaient que quatre personnes. La cloche
  /// passait inaperçue.
  static const cleAstuceSuivi = 'astuce_suivre_match_vue';
  final _cleCloche = GlobalKey();
  bool _bulleSuivi = false;
  bool _bulleNotee = false;
  /// Abscisse du centre de la cloche : la pointe de la bulle la vise.
  double? _centreCloche;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AnalyseUsage.pronosticOuvert(premium: widget.preloaded?.isPremium ?? false);
    _preparerBulleSuivi();
  }

  Future<void> _preparerBulleSuivi() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted || (prefs.getBool(cleAstuceSuivi) ?? false)) return;
    setState(() => _bulleSuivi = true);
  }

  /// La bulle est à l'écran : notée comme vue, et la cloche mesurée pour que
  /// la pointe la vise.
  void _bulleMontree() {
    if (!_bulleNotee) {
      _bulleNotee = true;
      SharedPreferences.getInstance().then((p) => p.setBool(cleAstuceSuivi, true));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final boite = _cleCloche.currentContext?.findRenderObject() as RenderBox?;
      if (boite == null || !boite.hasSize) return;
      final centre = boite.localToGlobal(boite.size.center(Offset.zero)).dx;
      if (centre != _centreCloche) setState(() => _centreCloche = centre);
    });
  }

  void _fermerBulle() {
    if (_bulleSuivi) setState(() => _bulleSuivi = false);
  }

  /// Suivre le match, ou ne plus le suivre — depuis la cloche ou la bulle.
  void _basculerSuivi(MatchEntity match) {
    HapticFeedback.selectionClick();
    // Le détail est ouvert aux invités, mais suivre exige un compte : on les
    // emmène s'inscrire au moment du geste.
    if (!ref.read(effectiveLoggedInProvider)) {
      context.push('/auth/email?from=${Uri.encodeComponent('/pronostics/${match.id}')}');
      return;
    }
    basculerSuivi(context, match.id, termine: match.status == MatchStatus.finished);
  }

  /// Le suivi du score s'arrête quand l'application passe en arrière-plan.
  ///
  /// La minuterie de 30 secondes tournait sans condition : application fermée
  /// ou page recouverte par une autre, le téléphone continuait d'interroger
  /// l'API (constat M12 de l'audit du 24 septembre 2026) — ce que l'accueil,
  /// lui, ne fait plus depuis longtemps.
  @override
  void didChangeAppLifecycleState(AppLifecycleState etat) {
    final avant = _premierPlan;
    _premierPlan = etat == AppLifecycleState.resumed;
    if (_premierPlan && !avant && _liveTimer != null) {
      // De retour : un relevé tout de suite plutôt qu'au prochain tic.
      _releverScore();
    }
  }

  /// Relève le score, sauf si personne ne le regarde : application en
  /// arrière-plan, ou page recouverte par une autre.
  Future<void> _releverScore() async {
    if (!mounted || !_premierPlan || _releveEnCours) return;
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    final match = ref.read(matchDetailProvider(widget.matchId)).valueOrNull ?? widget.preloaded;
    if (match == null) return;
    _releveEnCours = true;
    try {
      ref.invalidate(liveScoreProvider(match.id));
      final score = await ref.read(liveScoreProvider(match.id).future);
      if (!mounted) return;
      setState(() {
        _dernierRefresh = DateTime.now();
        _statutDuFlux = score.status;
      });
      final attendu = switch (match.status) {
        MatchStatus.upcoming => 'SCHEDULED',
        MatchStatus.live => 'LIVE',
        MatchStatus.finished => 'FINISHED',
      };
      final transition = score.status != attendu;
      if (transition) ref.invalidate(matchDetailProvider(widget.matchId));
      ref.invalidate(matchInfoProvider(match.id));
      final now = DateTime.now();
      if ((score.status == 'LIVE' || score.status == 'FINISHED') &&
          (transition || _dernieresStats == null || now.difference(_dernieresStats!).inSeconds >= 60)) {
        _dernieresStats = now;
        ref.invalidate(matchStatsProvider(match.id));
      }
      if (score.status == 'LIVE' &&
          (_dernieresCotes == null || now.difference(_dernieresCotes!).inSeconds >= 120)) {
        _dernieresCotes = now;
        ref.invalidate(liveOddsProvider(match.id));
      }
      if (_dernieresCompositions == null || now.difference(_dernieresCompositions!).inSeconds >= 120) {
        _dernieresCompositions = now;
        ref.invalidate(lineupsProvider(match.id));
        // Notes des joueurs en direct (compositions) : même rythme que le
        // cache du serveur.
        if (score.status == 'LIVE') ref.invalidate(playerRatingsProvider(match.id));
      }
      if (transition && score.status == 'FINISHED') {
        ref.invalidate(playerRatingsProvider(match.id));
        ref.invalidate(standingsProvider(match.id));
      }
    } catch (_) {
      // Garder le dernier relevé et sa date jusqu'à une réponse réussie.
    } finally {
      _releveEnCours = false;
    }
  }

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
    WidgetsBinding.instance.removeObserver(this);
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
    // 10 s : la lecture du score interroge notre serveur, pas API-Football
    // — elle ne coûte rien au quota (rythme adaptatif, 18 octobre 2026). Le
    // serveur relève lui-même un match suivi toutes les 15 s.
    _liveTimer = Timer.periodic(const Duration(seconds: 10), (_) => _releverScore());
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
    // Sur iPhone, la rencontre arrive sans cote : chaque carte de la fiche
    // masque déjà une cote nulle (voir `sansPariProvider`).
    final matchBrut = matchAsync.valueOrNull ?? widget.preloaded;
    final match = ref.watch(sansPariProvider) ? matchBrut?.sansCotes() : matchBrut;

    // Démarrer/arrêter le polling selon le statut du match
    final procheDuCoupEnvoi = match?.status == MatchStatus.upcoming &&
        match!.matchDate.difference(DateTime.now()).inMinutes <= 60;
    final fluxActif = _statutDuFlux == null || const {'LIVE', 'SCHEDULED'}.contains(_statutDuFlux);
    if (fluxActif && (match?.status == MatchStatus.live || procheDuCoupEnvoi)) {
      if (_liveTimer == null) _startLivePolling();
    } else {
      _stopLivePolling();
    }

    if (match == null) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            onPressed: () => retourOuAller(context, repli: _repli)),
          title: Text(tr(context, "Détail du match"))),
        // Trois situations, trois écrans. « Match introuvable » n'est vrai
        // que sur un 404 : une coupure réseau l'affichait aussi, sans rien
        // proposer, alors qu'il suffisait de réessayer.
        body: matchAsync.isLoading
          ? Center(child: CircularProgressIndicator(color: AppColors.primary))
          : matchAsync.error is NotFoundFailure || !matchAsync.hasError
            ? Center(child: Text(tr(context, "Match introuvable"),
                style: TextStyle(color: context.cl.textS)))
            : ErreurChargement(
                erreur: matchAsync.error,
                quoi: tr(context, "ce match"),
                onRetry: () => ref.invalidate(matchDetailProvider(widget.matchId)),
              ));
    }

    // Le verdict du serveur prime sur le calcul local : c'est lui qui connaît
    // l'état réel de l'abonnement. Le calcul local reste le repli quand la
    // donnée vient du cache ou de l'écran précédent.
    // `match.isLocked` vient du serveur, `match.isPremium` du cache ou de
    // l'écran précédent : l'un comme l'autre signalent un contenu payant, d'où
    // le « ou ». Mais ce « ou » donnait toujours raison à celui qui verrouille,
    // et aucun des deux ne regardait le statut du match — la correction serveur
    // (« plus rien à protéger après le coup de sifflet ») ne pouvait donc pas
    // atteindre cet ecran.
    //
    // La règle partagée tranche : payant, avant comme après le match
    // (décision de l'utilisateur du 17 octobre 2026).
    final isLocked = estVerrouille(
      contenuMasque: match.isLocked,
      estPremium:         match.isPremium || match.isLocked,
      utilisateurPremium: isPremium,
    );
    final isFav = ref.watch(favorisProvider).valueOrNull
            ?.matchIds.contains(match.id) ??
        false;

    // Onglets style Sofascore — surveillés ici (en plus des cartes elles-mêmes,
    // Riverpod dédoublonne l'appel) pour savoir lesquels construire : un onglet
    // sans donnée n'apparaît pas du tout, plutôt que d'afficher un message vide.
    final lineupsAsync   = ref.watch(lineupsProvider(match.id));
    final injuriesAsync  = ref.watch(injuriesProvider(match.id));
    final standingsAsync = ref.watch(standingsProvider(match.id));
    final h2hAsync       = ref.watch(h2hProvider(match.id));
    final statsAsync     = ref.watch(matchStatsProvider(match.id));
    // Les cotes de tous les marchés n'existent qu'avant le coup d'envoi.
    final avantMatch     = match.status == MatchStatus.upcoming;
    final cotesAsync     = avantMatch && !ref.watch(sansPariProvider)
        ? ref.watch(cotesMarchesProvider(match.id)) : null;

    // Les onglets restent visibles même sur un pronostic verrouillé : ils ne
    // servent que de la donnée de match (compositions, classements,
    // face-à-face...), qui n'a jamais fait partie de l'offre payante. Les
    // masquer ne protégeait rien et transformait la page en cul-de-sac pour
    // les invités comme pour les comptes gratuits.
    // Les onglets football sont aussi accessibles sans pronostic.

    // Un onglet dont l'appel est encore en vol n'est pas encore affichable —
    // mais il ne doit plus retenir toute la page. « Détails » porte la carte
    // Pronostic, c'est-à-dire la seule raison d'ouvrir cet écran : il s'affiche
    // immédiatement, et les onglets secondaires s'ajoutent à mesure. Avant, un
    // classement de championnat lent cachait le pronostic derrière un spinner
    // plein écran.
    final ongletsEnCours = (
      lineupsAsync.isLoading || injuriesAsync.isLoading ||
      standingsAsync.isLoading || h2hAsync.isLoading ||
      statsAsync.isLoading || (cotesAsync?.isLoading ?? false));

    // Un 401 (invité) affiche quand même l'onglet — avec une invite à se
    // connecter à l'intérieur — plutôt que de le cacher comme s'il n'y avait
    // rien à voir.
    bool visibleOrPrompt(AsyncValue<Object?> async, bool Function() hasContent) {
      final status = _statusOf(async.error);
      if (status == 401) return true;
      if (async.hasValue && hasContent()) return true;
      if (async.isLoading) return false;
      if (async.hasError) return false;
      return hasContent();
    }

    // Le bandeau 1X2 du pronostic, au-dessus des autres marchés.
    final bandeau1x2 = match.oddsHome > 0 || match.oddsDraw > 0 || match.oddsAway > 0;
    // Un match sans pronostic a aussi son onglet, dès qu'un marché est coté :
    // comme les autres onglets football, c'est de la donnée, pas l'offre.
    // Pas d'onglet Cotes sur iPhone (`sansPariProvider`).
    final showCotes = !ref.watch(sansPariProvider) && (
      (match.hasPronostic && match.status != MatchStatus.finished) ||
      _marchesAffichables(cotesAsync?.valueOrNull ?? const [], match,
        langue: AppStrings.of(context).locale.languageCode,
        sans1x2: bandeau1x2).isNotEmpty);
    final showStats = match.status != MatchStatus.upcoming;
    // L'onglet reste stable pendant le rafraîchissement et les coupures réseau.
    // Les faits marquants vivent dans l'onglet Détails, pas dans Statistiques.
    final showEvents = match.status != MatchStatus.upcoming;
    final showCompositions = visibleOrPrompt(lineupsAsync,
      () => lineupsAsync.valueOrNull?.available == true);
    final showBlessures    = visibleOrPrompt(injuriesAsync,
      () => injuriesAsync.valueOrNull?.isNotEmpty == true);
    // Stable even when the provider is temporarily unavailable.
    const showClassements = true;
    final showFaceAFace    = visibleOrPrompt(h2hAsync,
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


    final tabs = <(String, Widget)>[
      (tr(context, "Détails"), Column(children: [
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
        // Sous le fil des événements, comme sur Sofascore. Porte sa propre
        // marge : sans information à montrer, elle ne laisse pas de trou.
        _MatchInformationCard(matchId: match.id),
        // Porte sa propre marge : absente, elle ne laisse pas de trou.
        entree(_FormeRecente(match: match), delaiMs: 140),
        if (match.hasPronostic) ...[
        entree(_AIAnalysisCard(matchId: match.id, status: match.status,
                confianceAnalyste: match.pourcentageConfiance,
                equipes: [match.homeTeam, match.awayTeam]),
            delaiMs: 190),
        const SizedBox(height: 16),
        // Le « pourquoi » chiffré, juste sous l'analyse : c'est la question que
        // se pose l'utilisateur immédiatement après avoir lu le pronostic.
        entree(_AnalyseModele(matchId: match.id, pari: match.predictionType), delaiMs: 210),
        ],
        if (!match.hasPronostic) Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(tr(context, "Aucun pronostic publié pour ce match."),
            style: TextStyle(color: context.cl.textS))),
        if (match.status == MatchStatus.live && !ref.watch(sansPariProvider)) ...[
          const SizedBox(height: 16),
          entree(_CotesEnDirect(matchId: match.id), delaiMs: 230),
        ],
        if (match.status == MatchStatus.finished) ...[
          const SizedBox(height: 16),
          entree(_NotesJoueurs(matchId: match.id), delaiMs: 230),
        ],
        const SizedBox(height: 16),
        // Enregistrer une sélection dans la bankroll : pas sur iPhone.
        if (match.hasPronostic && match.status == MatchStatus.upcoming
            && !ref.watch(sansPariProvider)) ...[
          entree(_MiserButton(match: match), delaiMs: 240),
          const SizedBox(height: 16),
        ],
        if (match.analystNote?.isNotEmpty == true) ...[
          entree(_AnalystCard(match: match), delaiMs: 270),
          const SizedBox(height: 16),
        ],
        if (match.hasPronostic)
          entree(CommentsSection(pronosticId: match.id), delaiMs: 310),
      ])),
      if (showCotes) (tr(context, "Cotes"), Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _OddsCard(match: match),
        if (avantMatch) _ToutesLesCotes(match: match, sans1x2: bandeau1x2),
      ])),
      if (showStats) (tr(context, "Statistiques"), Column(children: [
        _MatchStatsCard(matchId: match.id),
        const SizedBox(height: 16),
        if (match.hasPronostic) _ButsParTranche(matchId: match.id),
      ])),
      // « Classements », toujours présent, vient avant les onglets qui
      // attendent leur réponse réseau (compositions, blessures, face-à-face) :
      // ceux-là s'ajoutent ainsi au bout de la barre, sans décaler ceux qu'on
      // voit déjà. « Face à face » arrivait au milieu de la rangée après
      // l'ouverture (vidéo du 5 octobre 2026).
      if (showClassements) (tr(context, "Classements"), Column(children: [
        _StandingsCard(
          matchId: match.id,
          homeTeam: match.homeTeam,
          awayTeam: match.awayTeam),
        _MeilleursButeurs(leagueCode: match.leagueCountry),
      ])),
      if (showCompositions) (tr(context, "Compositions"), _LineupsCard(match: match)),
      if (showBlessures) (tr(context, "Blessures"), _InjuriesCard(
        matchId: match.id,
        homeTeam: match.homeTeam,
        awayTeam: match.awayTeam,
        homeLogo: match.homeTeamLogo,
        awayLogo: match.awayTeamLogo)),
      if (showFaceAFace) (tr(context, "Face à face"), Column(children: [
        _H2HCard(
          matchId: match.id,
          homeLogo: match.homeTeamLogo,
          awayLogo: match.awayTeamLogo),
        const SizedBox(height: 14),
        // Les confrontations remontent parfois à deux ou trois ans, avec des
        // effectifs entièrement renouvelés — un 2-0 de mai 2025 ne dit plus
        // grand-chose. La saison en cours dit ce que valent les deux équipes
        // *aujourd'hui*, et ces chiffres étaient déjà disponibles sans être lus.
        if (match.hasPronostic) _SaisonEnCours(match: match),
      ])),
    ];

    // Avec plusieurs onglets, la barre d'onglets se range sous l'en-tête et
    // reste épinglée ; avec un seul, il n'y en a pas.
    final avecOnglets = tabs.length > 1 || ongletsEnCours;
    // Ce qu'occupent les actions à droite : l'en-tête replié se centre dans
    // l'espace qui reste, comme chez Sofascore.
    final retard = match.status == MatchStatus.live
        && DateTime.now().difference(_dernierRefresh) > delaiScoreNonActualise;
    final reserveActions = 48.0 + 48 + (match.isPremium ? 24 : 0) + (retard ? 110 : 0) + 8;
    // La bulle de la cloche : ni pour un match terminé, ni pour un match déjà
    // suivi. Le premier toucher, n'importe où, la ferme.
    final bulle = _bulleSuivi && match.status != MatchStatus.finished && !isFav;
    if (bulle) _bulleMontree();

    return Scaffold(
      backgroundColor: context.cl.bg,
      // La saisie d'un commentaire se fait dans une feuille au-dessus du
      // clavier : la page n'a pas à rétrécir pendant qu'il monte — c'est ce
      // qui la faisait trembler (20 octobre 2026).
      resizeToAvoidBottomInset: false,
      body: Stack(children: [
        Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: bulle ? (_) => _fermerBulle() : null,
        child: NestedScrollView(
        headerSliverBuilder: (ctx, _) => [
          SliverOverlapAbsorber(
            handle: NestedScrollView.sliverOverlapAbsorberHandleFor(ctx),
            // L'en-tête est sombre dans les deux thèmes, comme chez Sofascore :
            // ses icônes et ses textes lisent le thème sombre.
            sliver: Theme(data: AppTheme.dark, child: Builder(builder: (sombre) => SliverAppBar(
              pinned: true,
              automaticallyImplyLeading: false,
              backgroundColor: _fondEnTete.last,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              systemOverlayStyle: const SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: Brightness.light,
                statusBarBrightness: Brightness.dark),
              toolbarHeight: _hauteurBarre,
              expandedHeight: _hauteurBarre + _hauteurEnTete + (avecOnglets ? 48 : 0),
              leading: IconButton(
                tooltip: tr(sombre, "Retour"),
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                onPressed: () => retourOuAller(context, repli: _repli)),
              title: _TitreLigue(ligue: match.league),
              centerTitle: true,
              actions: [
                // Suivre le match : coup d'envoi, buts et résultat en
                // notification (suivre_match.dart).
                KeyedSubtree(key: _cleCloche, child: IconButton(
                  key: const Key('suivre-match'),
                  icon: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      iconeSuivi(isFav),
                      key: ValueKey(isFav),
                      size: 22,
                      color: isFav ? AppColors.primary : sombre.cl.textP,
                    ),
                  ),
                  tooltip: libelleSuivi(sombre, isFav),
                  onPressed: () => _basculerSuivi(match),
                )),
                // Rien sur la fraîcheur du score, sauf s'il n'arrive plus.
                if (match.status == MatchStatus.live)
                  _ScoreNonActualise(dernier: _dernierRefresh),
                IconButton(
                  icon: const Icon(Icons.share_rounded, size: 20),
                  tooltip: tr(sombre, "Partager"),
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    _showShareSheet(context, match);
                  },
                ),
                if (match.isPremium)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(
                      isPremium ? Icons.workspace_premium_rounded : Icons.lock_rounded,
                      color: isPremium ? sombre.cl.warning : sombre.cl.textM,
                      size: 20)),
              ],
              flexibleSpace: _EnTeteRepliable(
                match: match,
                hauteurOnglets: avecOnglets ? 48 : 0,
                reserveActions: reserveActions,
              ),
              bottom: avecOnglets
                  ? _BarreOnglets(
                      controller: _controleurPour([for (final t in tabs) t.$1]),
                      libelles: [for (final t in tabs) t.$1],
                      enCours: ongletsEnCours,
                    )
                  : null,
            ))),
          ),
        ],
        body: avecOnglets
            ? TabBarView(
                controller: _controleurPour([for (final t in tabs) t.$1]),
                children: [for (final t in tabs) ongletImbrique(t.$2)],
              )
            : ongletImbrique(tabs.first.$2),
      )),
        if (bulle && _centreCloche != null)
          Positioned(
            top: MediaQuery.paddingOf(context).top + _hauteurBarre - 6,
            right: 8,
            child: _BulleSuivi(
              pointe: MediaQuery.sizeOf(context).width - 8 - _centreCloche!,
              onSuivre: () { _fermerBulle(); _basculerSuivi(match); },
              onFermer: _fermerBulle,
            ),
          ),
      ]),
    );
  }
}

// ─── Bulle de la cloche ──────────────────────────────────────────────────────

/// La bulle posée sous la cloche, la première fois qu'on ouvre une fiche
/// (22 octobre 2026). Compacte : elle tient dans l'en-tête, au-dessus de la
/// barre d'onglets, quelle que soit la taille du texte. La toucher la ferme.
class _BulleSuivi extends StatelessWidget {
  /// Distance entre le bord droit de la bulle et le centre de la cloche.
  final double pointe;
  final VoidCallback onSuivre, onFermer;
  const _BulleSuivi({required this.pointe, required this.onSuivre, required this.onFermer});

  @override
  Widget build(BuildContext context) {
    final largeur = (MediaQuery.sizeOf(context).width - 16).clamp(0.0, 300.0);
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.15,
      child: SizedBox(
        key: const Key('bulle-suivi'),
        width: largeur,
        child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: EdgeInsets.only(right: (pointe - 8).clamp(8.0, largeur - 24)),
            child: CustomPaint(size: const Size(16, 8), painter: _PointeBulle(AppColors.primary)),
          ),
          Material(
            color: AppColors.primary,
            elevation: 6,
            shadowColor: Colors.black54,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: onFermer,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
                child: Row(children: [
                  const Icon(Icons.notifications_active_rounded, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: Text(
                    tr(context, "Sois alerté des buts, de la mi-temps et du résumé."),
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 12.5, height: 1.3, fontWeight: FontWeight.w600))),
                  TextButton(
                    key: const Key('bulle-suivi-suivre'),
                    style: TextButton.styleFrom(foregroundColor: Colors.white,
                      visualDensity: VisualDensity.compact,
                      textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                    onPressed: onSuivre,
                    child: Text(tr(context, "Suivre")),
                  ),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// La pointe de la bulle, vers le haut.
class _PointeBulle extends CustomPainter {
  final Color couleur;
  const _PointeBulle(this.couleur);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      Path()..moveTo(0, size.height)..lineTo(size.width / 2, 0)..lineTo(size.width, size.height)..close(),
      Paint()..color = couleur);
  }

  @override
  bool shouldRepaint(_PointeBulle ancienne) => ancienne.couleur != couleur;
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
            labelColor: context.cl.accent,
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

// ─── En-tête du match, au modèle de Sofascore ───────────────────────────────
//
// Demande du 20 octobre 2026, d'après la vidéo du 17 (Sofascore, 0:00-0:06).
// La carte d'en-tête faisait environ 225 pt de haut — trois fois celle de
// Sofascore, qui tient en ~85 pt sous la barre : logo et nom de chaque équipe
// sur les côtés, le score au centre, le chrono dessous, sur un fond sombre.
// Au défilement, l'en-tête se replie au rythme du doigt : les logos
// rétrécissent et remontent dans la barre, de part et d'autre du score, et les
// noms s'effacent ; la barre d'onglets reste épinglée dessous.
//
// Chaque position est une interpolation entre l'état déplié et l'état replié,
// calculée depuis la hauteur restante de la barre (FlexibleSpaceBarSettings) :
// pas d'animation minutée, le mouvement suit le défilement.

const double _hauteurBarre = 56;
const double _hauteurEnTete = 96;
const List<Color> _fondEnTete = [Color(0xFF151B2E), Color(0xFF0D1220)];

/// 1 = en-tête déplié, 0 = replié.
double _deplie(BuildContext context) {
  final r = context.dependOnInheritedWidgetOfExactType<FlexibleSpaceBarSettings>();
  if (r == null || r.maxExtent <= r.minExtent) return 1;
  return ((r.currentExtent - r.minExtent) / (r.maxExtent - r.minExtent)).clamp(0.0, 1.0);
}

/// La compétition dans la barre, tant que l'en-tête est déplié : les logos et
/// le score prennent sa place au repli.
class _TitreLigue extends StatelessWidget {
  final String ligue;
  const _TitreLigue({required this.ligue});

  @override
  Widget build(BuildContext context) {
    final opacite = ((_deplie(context) - 0.45) / 0.55).clamp(0.0, 1.0);
    if (opacite == 0) return const SizedBox.shrink();
    return Opacity(
      opacity: opacite,
      child: Text(ligue,
        maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
        style: TextStyle(fontSize: 13.5, height: 1.15, color: context.cl.textS)),
    );
  }
}

class _EnTeteRepliable extends ConsumerWidget {
  final MatchEntity match;
  final double hauteurOnglets;
  /// Largeur des actions à droite de la barre : l'en-tête replié se centre
  /// dans ce qui reste.
  final double reserveActions;
  const _EnTeteRepliable({
    required this.match, required this.hauteurOnglets, required this.reserveActions});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reglages = context.dependOnInheritedWidgetOfExactType<FlexibleSpaceBarSettings>();
    final r = Curves.easeInOut.transform(1 - _deplie(context));
    // La barre d'état : ce que la barre compte en plus de ses hauteurs fixes.
    final haut = reglages == null
        ? MediaQuery.paddingOf(context).top
        : (reglages.maxExtent - (_hauteurBarre + _hauteurEnTete + hauteurOnglets)).clamp(0.0, 200.0);

    final live = match.status == MatchStatus.live
        ? ref.watch(liveScoreProvider(match.id)).valueOrNull : null;
    final info = match.status == MatchStatus.live
        ? ref.watch(matchInfoProvider(match.id)).valueOrNull : null;
    final dom = live?.homeScore ?? match.homeScore;
    final ext = live?.awayScore ?? match.awayScore;

    final d = match.matchDate;
    final dateStr = '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    final heureStr = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    final etat = switch (match.status) {
      MatchStatus.live     => live?.elapsed == null
                                ? tr(context, "en direct")
                                : tr(context, "en direct, {arg0}e minute", [live!.elapsed]),
      MatchStatus.finished => tr(context, "terminé"),
      _                    => tr(context, "à venir"),
    };
    final scoreParle = match.status == MatchStatus.upcoming
        ? tr(context, "contre")
        : tr(context, "{arg0} à {arg1} contre", [dom ?? 0, ext ?? 0]);

    return Semantics(
      label: tr(context, "{arg0}. {arg1} {arg2} {arg3}. Match {arg4}, le {arg5} à {arg6}.",
          [match.league, match.homeTeam, scoreParle, match.awayTeam, etat, dateStr, heureStr]),
      container: true,
      child: MediaQuery.withClampedTextScaling(
        // L'en-tête a une hauteur fixe, comme chez Sofascore : le texte y
        // grandit, mais pas au point de chevaucher les logos.
        maxScaleFactor: 1.25,
        child: DecoratedBox(
          decoration: const BoxDecoration(gradient: LinearGradient(
            colors: _fondEnTete, begin: Alignment.topLeft, end: Alignment.bottomRight)),
          child: LayoutBuilder(builder: (context, c) {
            final w = c.maxWidth;
            double l(double a, double b) => a + (b - a) * r;
            final yBarre = haut + _hauteurBarre / 2;
            final yLogo = l(haut + _hauteurBarre + 28, yBarre);
            final taille = l(52, 26);
            final centreReplie = (56 + w - reserveActions) / 2;
            final xDom = l(w * 0.18, centreReplie - 54);
            final xExt = l(w * 0.82, centreReplie + 54);
            final xScore = l(w / 2, centreReplie);
            final yScore = l(haut + _hauteurBarre + 26, yBarre);
            // Les noms s'effacent dans le premier quart du repli, en remontant :
            // la barre d'onglets qui monte ne doit jamais les rogner.
            final opaciteNoms = (1 - r * 4).clamp(0.0, 1.0);
            final largeurNom = w * 0.28;

            Widget logo(String nom, String? url, String tag, double x) => Positioned(
              left: x - taille / 2, top: yLogo - taille / 2, width: taille, height: taille,
              child: IgnorePointer(
                // Replié, le logo n'est plus une cible : il est trop petit.
                ignoring: r > 0.5,
                child: LienEquipe(nom: nom, logo: url, competition: match.leagueCountry,
                  child: Hero(tag: tag, child: _TeamLogo(url: url ?? '', size: taille))),
              ),
            );
            Widget nom(String texte, double x) => Positioned(
              left: x - largeurNom / 2, width: largeurNom,
              top: haut + _hauteurBarre + 60 - r * 48,
              child: IgnorePointer(child: Opacity(opacity: opaciteNoms, child: Text(texte,
                maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
                style: TextStyle(color: context.cl.textP, fontSize: 13, fontWeight: FontWeight.w600)))),
            );

            return ExcludeSemantics(child: Stack(clipBehavior: Clip.hardEdge, children: [
              if (opaciteNoms > 0) ...[
                nom(match.homeTeam, xDom),
                nom(match.awayTeam, xExt),
              ],
              logo(match.homeTeam, match.homeTeamLogo, 'team_home_${match.homeTeam}', xDom),
              logo(match.awayTeam, match.awayTeamLogo, 'team_away_${match.awayTeam}', xExt),
              Positioned(
                left: xScore - 80, width: 160,
                top: yScore - l(25, 15),
                child: IgnorePointer(child: _BlocScore(
                  match: match, dom: dom, ext: ext, minute: live?.elapsed, info: info,
                  repli: r, heure: heureStr, date: dateStr)),
              ),
            ]));
          }),
        ),
      ),
    );
  }
}

/// Le centre de l'en-tête : le score (ou l'heure du coup d'envoi) et, dessous,
/// le chrono du direct, « Terminé » ou la date.
class _BlocScore extends StatelessWidget {
  final MatchEntity match;
  final int? dom, ext, minute;
  final MatchInfo? info;
  final double repli;
  final String heure, date;
  const _BlocScore({required this.match, required this.dom, required this.ext,
    required this.minute, required this.info, required this.repli,
    required this.heure, required this.date});

  @override
  Widget build(BuildContext context) {
    double l(double a, double b) => a + (b - a) * repli;
    final enDirect = match.status == MatchStatus.live;
    final principal = match.status == MatchStatus.upcoming ? heure : '${dom ?? 0} - ${ext ?? 0}';
    final taillePrincipal = l(match.status == MatchStatus.upcoming ? 26 : 30, 17);
    final tailleSecond = l(12, 9.5);

    final Widget second = switch (match.status) {
      MatchStatus.live => _ChronoEnDirect(
        info: info,
        minuteSecours: minute,
        builder: (context, chrono) => Row(mainAxisSize: MainAxisSize.min, children: [
          Text(_texteChrono(context, chrono),
            key: const Key('chrono-direct'),
            style: TextStyle(color: context.cl.error, fontSize: tailleSecond, fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()])),
          if (chrono.additionnel != null) ...[
            const SizedBox(width: 4),
            Text("+${chrono.additionnel}'",
              key: const Key('chrono-additionnel'),
              style: TextStyle(color: context.cl.error.withValues(alpha: 0.75),
                fontSize: tailleSecond - 1, fontWeight: FontWeight.w600)),
          ],
        ]),
      ),
      MatchStatus.finished => Text(tr(context, "Terminé"),
        style: TextStyle(color: context.cl.textS, fontSize: tailleSecond, fontWeight: FontWeight.w600)),
      _ => Opacity(
        opacity: (1 - repli * 1.6).clamp(0.0, 1.0),
        child: Text(date, style: TextStyle(color: context.cl.textS, fontSize: tailleSecond, fontWeight: FontWeight.w600))),
    };

    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(principal,
        maxLines: 1,
        style: TextStyle(
          color: enDirect ? context.cl.success : context.cl.textP,
          fontSize: taillePrincipal, fontWeight: FontWeight.w800, height: 1.1,
          fontFeatures: const [FontFeature.tabularFigures()])),
      SizedBox(height: l(3, 1)),
      second,
    ]);
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
      return tr(context, "Pronostic réservé aux membres Premium.");
    }
    final marche = _market == null ? '' : '${_market!}, ';
    final cote = match.oddsRecommended > 0
        ? tr(context, " Cote recommandée {arg0}.", [match.oddsRecommended.toStringAsFixed(2)])
        : '';
    final verdict = switch (match.result) {
      PronosticResult.win  => tr(context, " Pronostic gagnant."),
      PronosticResult.loss => tr(context, " Pronostic perdant."),
      PronosticResult.push => tr(context, " Pronostic remboursé."),
      null                 => '',
    };
    return tr(context, "Pronostic : {arg0}{arg1}.{arg2} Indice de confiance de l’analyste {arg3}, {arg4}.{arg5}", [marche, _pick, cote, MatchEntity.affichageConfiance(match.pourcentageConfiance), MatchEntity.labelForConfidence(match.confidenceScore), verdict]);
  }

  @override
  Widget build(BuildContext context) {
    // Déverrouillé, l'encadré est bleu nuit dans les deux thèmes : son
    // contenu doit lire le thème sombre.
    if (!isLocked && !context.isDark) return SurfaceSombre(builder: _carte);
    return _carte(context);
  }

  Widget _carte(BuildContext context) => Semantics(
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
      Text(tr(context, "PRONOSTIC"), style: TextStyle(
        color: context.cl.textM, fontSize: 11,
        fontWeight: FontWeight.w600, letterSpacing: 1)),
      SizedBox(height: 14),

      if (isLocked)
        Row(children: [
          Icon(Icons.lock_rounded, color: context.cl.textM, size: 20),
          SizedBox(width: 10),
          Expanded(child: Text(tr(context, "Contenu réservé aux membres Premium"),
            style: TextStyle(color: context.cl.textM, fontSize: 14))),
        ])
      else ...[
        // Marché en surtitre + choix en gros : se lit comme un ticket de pari,
        // au lieu d'une longue phrase qui passe à la ligne.
        if (_market != null) ...[
          Text(_market!.toUpperCase(),
            style: TextStyle(
              color: context.cl.accent,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8)),
          const SizedBox(height: 7),
        ],
        Text(_pick,
          style: TextStyle(
            color: context.cl.textP,
            fontSize: 22,
            fontWeight: FontWeight.w700,
            height: 1.2)),
        const SizedBox(height: 16),
        Container(height: 1, color: context.cl.borderSoft),
        const SizedBox(height: 14),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (match.oddsRecommended > 0) ...[
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr(context, "COTE"),
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
                  fontWeight: FontWeight.w700,
                  height: 1)),
            ]),
            const SizedBox(width: 28),
          ],
          // Une fois le résultat connu, la confiance est rétrospective : elle
          // n'aide plus à décider, elle ne fait que documenter. Elle passe donc
          // d'une jauge pleine largeur à une mention discrète.
          //
          // La place libérée accueillait un rendement — « AURAIT RAPPORTÉ
          // +790 F », calculé sur une mise de référence de 1 000 F. Le montant
          // était donc vrai pour une mise que personne n'a posée : celui qui
          // avait misé 200 F lisait un gain quatre fois trop grand, celui qui
          // n'avait pas misé du tout lisait un gain tout court.
          //
          // Un gain n'a de sens que rapporté à une bankroll, et la bankroll a
          // son propre écran, avec les vrais montants et les paris réellement
          // enregistrés. La fiche de match dit ce qui s'est passé ; elle n'a
          // pas à chiffrer ce qui aurait pu arriver.
          if (match.result == null)
            Expanded(child: _DetailConfidenceBar(pourcentage: match.pourcentageConfiance))
          else ...[
            const Spacer(),
            _ConfianceRappel(pourcentage: match.pourcentageConfiance),
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


/// Rappel discret de la confiance annoncée avant le coup d'envoi, une fois le
/// résultat connu — la jauge pleine largeur n'a plus lieu d'être.
class _ConfianceRappel extends StatelessWidget {
  final int pourcentage;
  const _ConfianceRappel({required this.pourcentage});

  @override
  Widget build(BuildContext context) {
    final couleur = ConfidenceIndicator.colorFor(
        context, MatchEntity.niveauDepuisPourcentage(pourcentage));
    return Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
      Text(tr(context, "CONFIANCE ANNONCÉE"),
        style: TextStyle(
          color: context.cl.textM,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8)),
      const SizedBox(height: 7),
      Text(MatchEntity.affichageConfiance(pourcentage),
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
    final color  = isWin ? context.cl.success : isPush ? context.cl.info : context.cl.error;
    final icon   = isWin  ? Icons.check_circle_rounded
                 : isPush ? Icons.replay_rounded
                 : Icons.cancel_rounded;
    final label  = isWin  ? tr(context, "Pronostic gagnant")
                 : isPush ? tr(context, "Pronostic remboursé")
                 : tr(context, "Pronostic perdant");

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
                color: color, fontSize: 14, fontWeight: FontWeight.w700)),
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
class _OddsCard extends ConsumerWidget {
  final MatchEntity match;
  const _OddsCard({required this.match});

  bool get _hasOdds =>
    match.oddsHome > 0 || match.oddsDraw > 0 || match.oddsAway > 0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!_hasOdds) return const SizedBox.shrink();

    // La pastille verte ne signale la cote recommandée que si le pronostic
    // porte sur le marché « vainqueur ». Sur un « Double chance » ou un
    // « Total buts », les trois cotes 1/X/2 n'ont aucun rapport avec le
    // pronostic, et la seule cote qui compte n'apparaissait nulle part.
    final surMarcheVainqueur = match.predictionType == PredictionType.win1 ||
                               match.predictionType == PredictionType.draw ||
                               match.predictionType == PredictionType.win2;

    final marche = tr(context, "VAINQUEUR DU MATCH");
    final indiceRecommande = switch (match.predictionType) {
      PredictionType.win1  => 0,
      PredictionType.draw  => 1,
      PredictionType.win2  => 2,
      _                    => null,
    };

    // Un seul bandeau, décidé par le canal. Les deux étaient empilés : mêmes
    // valeurs, à quarante pixels d'écart, et celui du haut portait les cotes
    // du même bookmaker sans son logo ni la mention « 18+ ».
    final bandeau = bandeauCotes(
      estStore: ref.watch(isStoreBuildProvider),
      partenaireDisponible: BookmakerAffiliation.disponible,
    );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (match.oddsRecommended > 0 && !surMarcheVainqueur) ...[
        _CoteRecommandee(match: match),
        const SizedBox(height: 12),
      ],

      if (bandeau == BandeauCotes.partenaire)
        BookmakerCotes(
          marche:        marche,
          coteDomicile:  match.oddsHome,
          coteNul:       match.oddsDraw,
          coteExterieur: match.oddsAway,
          indiceRecommande: indiceRecommande,
        )
      else
        // Sans partenaire affichable — paquet des boutiques, ou partenariat non
        // configuré —, les cotes restent visibles, en lecture seule. C'est le
        // lien vers le bookmaker qui n'a pas sa place partout, pas la donnée.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: context.cl.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.cl.border, width: 0.5)),
          child: Row(children: [
            Flexible(
              child: Text(marche,
                maxLines: 2,
                style: TextStyle(
                  color: context.cl.textM, fontSize: 9.5,
                  fontWeight: FontWeight.w700, letterSpacing: 0.6)),
            ),
            const SizedBox(width: 10),
            _OddPill(label: '1', value: match.oddsHome,
              isRecommended: indiceRecommande == 0),
            const SizedBox(width: 8),
            _OddPill(label: 'X', value: match.oddsDraw,
              isRecommended: indiceRecommande == 1),
            const SizedBox(width: 8),
            _OddPill(label: '2', value: match.oddsAway,
              isRecommended: indiceRecommande == 2),
          ]),
        ),

      if (match.status == MatchStatus.live) ...[
        const SizedBox(height: 10),
        Row(children: [
          Icon(Icons.info_outline_rounded, size: 13, color: context.cl.textM),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              tr(context, "Cotes d'ouverture — elles ne suivent pas le match en cours."),
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
      color: context.cl.success.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: context.cl.success.withValues(alpha: 0.35), width: 1.2)),
    child: Row(children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr(context, "COTE DU PRONOSTIC"),
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
        style: TextStyle(
          color: context.cl.success, fontSize: 22,
          fontWeight: FontWeight.w700, height: 1)),
    ]),
  );
}

class _OddPill extends StatelessWidget {
  final String label;
  final double value;
  final bool isRecommended;
  const _OddPill({required this.label, required this.value, this.isRecommended = false});

  @override
  Widget build(BuildContext context) => Semantics(
    // La coche disparaît de l'écran, l'information reste pour qui n'y voit
    // rien : sans elle, un lecteur d'écran annonçait « 1, 1.34 » à l'identique
    // pour la cote recommandée et les deux autres — la couleur ne s'entend pas.
    label: isRecommended
      ? tr(context, "{arg0}, cote {arg1}, recommandée", [label, value.toStringAsFixed(2)])
      : tr(context, "{arg0}, cote {arg1}", [label, value > 0 ? value.toStringAsFixed(2) : tr(context, "indisponible")]),
    excludeSemantics: true,
    child: Container(
      width: 48,
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: isRecommended
          ? context.cl.success.withValues(alpha: 0.12)
          : context.cl.surfaceDeep,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isRecommended
            ? context.cl.success.withValues(alpha: 0.4)
            : context.cl.borderSoft,
          width: isRecommended ? 1.2 : 0.5)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // La pastille verte, sa bordure et le chiffre coloré disent déjà que
        // cette cote est celle du pronostic. Une coche de neuf pixels collée
        // au « 1 » ajoutait un quatrième signal pour la même information, et
        // se lisait comme une scorie plutôt que comme un repère.
        Text(label, style: TextStyle(
          color: isRecommended ? context.cl.success : context.cl.textM,
          fontSize: 9, fontWeight: FontWeight.w700)),
        Text(value > 0 ? value.toStringAsFixed(2) : '—',
          style: TextStyle(
            color: isRecommended ? context.cl.success : context.cl.textP,
            fontSize: 14, fontWeight: FontWeight.w700)),
      ]),
    ),
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
          Text(tr(context, "ANALYSE DE L'EXPERT"), style: TextStyle(
            color: context.cl.textM, fontSize: 11,
            fontWeight: FontWeight.w600, letterSpacing: 1)),
          Text(tr(context, "Notre Analyste"), style: TextStyle(
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
    // Google Play sans abonnement en vente : pas de prix (`premiumIndisponibleSurPlay`).
    final priceLabel = premiumIndisponibleSurPlay(ref)
        ? tr(context, "Débloquer")
        : tr(context, "{arg0}/mois", [premiumMonthlyPriceLabel(ref, sub)]);
    // Carte toujours sombre : son contenu lit le thème sombre, sinon les
    // couleurs d'état et les gris passent à leurs variantes pour fond blanc.
    return SurfaceSombre(builder: (context) => GestureDetector(
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
          Text(tr(context, "Accès Premium requis"), style: TextStyle(
            color: context.cl.textP, fontSize: 15,
            fontWeight: FontWeight.w700)),
          SizedBox(height: 3),
          Text(ref.watch(sansPariProvider)
              ? tr(context, "Pronostic et analyse complète")
              : tr(context, "Pronostic, cotes et analyse complète"),
            style: TextStyle(color: context.cl.textS, fontSize: 12)),
        ])),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.primaryBouton,
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
  ));
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

/// Délai sans relevé réussi au-delà duquel le score est signalé comme ancien :
/// trois relevés de 30 s manqués.
const delaiScoreNonActualise = Duration(seconds: 90);

/// Mention « Score non actualisé », dans la barre de titre, seulement quand le
/// score en direct n'arrive plus depuis [delaiScoreNonActualise].
///
/// Elle remplace le compteur « il y a 12 s » affiché en permanence. Le
/// compteur avait une raison d'être, qu'on garde : un score gelé par une panne
/// réseau ne doit pas passer pour un score à jour. Mais tant que tout va bien,
/// rien ne s'affiche.
class _ScoreNonActualise extends StatefulWidget {
  final DateTime dernier;
  const _ScoreNonActualise({required this.dernier});

  @override
  State<_ScoreNonActualise> createState() => _ScoreNonActualiseState();
}

class _ScoreNonActualiseState extends State<_ScoreNonActualise> {
  Timer? _tic;

  @override
  void initState() {
    super.initState();
    // Le relevé réussi reconstruit déjà la page ; ce tic ne sert qu'à faire
    // apparaître la mention quand plus rien n'arrive.
    _tic = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() { _tic?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final ecart = DateTime.now().difference(widget.dernier);
    if (ecart < delaiScoreNonActualise) return const SizedBox.shrink();
    return Semantics(
      label: tr(context, "Score non actualisé depuis {arg0} min", [ecart.inMinutes]),
      excludeSemantics: true,
      child: Padding(
        key: const Key('score-non-actualise'),
        padding: const EdgeInsets.only(right: 8),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.cloud_off_rounded, size: 13, color: context.cl.textM),
          const SizedBox(width: 4),
          Text(tr(context, "Score non actualisé"),
            style: TextStyle(color: context.cl.textM, fontSize: 10.5)),
        ]),
      ),
    );
  }
}

/// Texte du chrono : « 67:23 », « 67' », « MI-TEMPS »…, suivi du temps
/// additionnel (« +7' ») si [avecAdditionnel].
String _texteChrono(BuildContext context, ChronoMatch c, {bool avecAdditionnel = false}) {
  final base = switch (c.etat) {
    EtatChrono.aLaSeconde => c.texteSecondes,
    EtatChrono.aLaMinute  => "${c.minute}'",
    EtatChrono.miTemps    => tr(context, "MI-TEMPS"),
    EtatChrono.pause      => tr(context, "PAUSE"),
    EtatChrono.tirsAuBut  => tr(context, "TIRS AU BUT"),
    EtatChrono.interrompu => tr(context, "INTERROMPU"),
    EtatChrono.inconnu    => tr(context, "EN DIRECT"),
  };
  return avecAdditionnel && c.additionnel != null ? "$base +${c.additionnel}'" : base;
}

/// Fait avancer le chrono du direct chaque seconde, entre deux relevés.
///
/// Les relevés (score toutes les 30 s, informations de match) disent où en
/// est le match ; ce widget recalcule le temps de jeu à la seconde à partir
/// du début de la mi-temps (`chrono_match.dart`). Il ne se reconstruit que
/// quand le texte affiché change.
class _ChronoEnDirect extends StatefulWidget {
  final MatchInfo? info;
  /// Minute du relevé de score, si les informations de match manquent.
  final int? minuteSecours;
  final Widget Function(BuildContext context, ChronoMatch chrono) builder;
  const _ChronoEnDirect({required this.info, this.minuteSecours, required this.builder});

  @override
  State<_ChronoEnDirect> createState() => _ChronoEnDirectState();
}

class _ChronoEnDirectState extends State<_ChronoEnDirect> {
  Timer? _tic;
  late ChronoMatch _chrono = _calculer();

  ChronoMatch _calculer() {
    final i = widget.info;
    return chronoMatch(
      phase:   i?.phase,
      elapsed: i?.elapsed ?? widget.minuteSecours,
      extra:   i?.extra,
      debut1:  i?.debutPremiereMiTemps,
      debut2:  i?.debutSecondeMiTemps,
      maintenant: DateTime.now(),
    );
  }

  @override
  void initState() {
    super.initState();
    _tic = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final c = _calculer();
      if (c != _chrono) setState(() => _chrono = c);
    });
  }

  @override
  void didUpdateWidget(covariant _ChronoEnDirect ancien) {
    super.didUpdateWidget(ancien);
    _chrono = _calculer();
  }

  @override
  void dispose() { _tic?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) => widget.builder(context, _chrono);
}

class _DetailConfidenceBar extends StatelessWidget {
  /// Indice de confiance de l'analyste, en pourcentage.
  final int pourcentage;
  const _DetailConfidenceBar({required this.pourcentage});

  int get score => MatchEntity.niveauDepuisPourcentage(pourcentage);

  /// Couleur et libellé viennent tous deux de la source unique. Cette classe
  /// avait sa propre échelle à 5 couleurs là où le reste de l'app en utilise 3 :
  /// un score de 4 s'affichait vert-lime ici et vert ailleurs, pour la même
  /// donnée sur deux écrans voisins.
  Color _color(BuildContext context) => ConfidenceIndicator.colorFor(context, score);

  String get _label => MatchEntity.labelForConfidence(score);

  @override
  Widget build(BuildContext context) {
    final pct = pourcentage.clamp(0, 99);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          // Le libellé cède la place au chiffre : « INDICE DE CONFIANCE »
          // passe sur deux lignes à 180 % au lieu de déborder.
          // « de l'analyste » : un pourcentage sans auteur se confondait avec
          // la « probabilité de succès » calculée plus bas.
          Expanded(child: Text(tr(context, "CONFIANCE DE L'ANALYSTE"),
              style: TextStyle(
                  color: context.cl.textM,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8))),
          const SizedBox(width: 8),
          TweenAnimationBuilder<int>(
            tween: IntTween(begin: pct, end: pct),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (_, val, child) => Text(MatchEntity.affichageConfiance(val),
                style: TextStyle(
                    color: _color(context), fontSize: 15, fontWeight: FontWeight.w700,
                    height: 1)),
          ),
        ]),
        const SizedBox(height: 7),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: pct / 100),
          duration: const Duration(milliseconds: 900),
          curve: Curves.easeOutCubic,
          builder: (_, val, child) => ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: val,
              minHeight: 6,
              backgroundColor: context.cl.borderSoft,
              valueColor: AlwaysStoppedAnimation<Color>(_color(context)),
            ),
          ),
        ),
        const SizedBox(height: 5),
        Text(_label,
            style: TextStyle(
                color: _color(context), fontSize: 10.5, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

// ─── PARTAGE ─────────────────────────────────────────────────────────────────

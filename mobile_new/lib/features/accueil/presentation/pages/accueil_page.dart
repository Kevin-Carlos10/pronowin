import '../../../../shared/widgets/entete_onglet.dart';
import 'package:pronowin/l10n/editorial_text.dart';
import 'package:pronowin/l10n/app_strings.dart';
import 'dart:async';
import 'dart:ui';
import '../../../../core/utils/motion.dart';
import '../../../../shared/widgets/confidence_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/chiffres_ios.dart';
import '../../../../core/widgets/image_distante.dart';
import '../../../../core/widgets/team_logo_widget.dart';
import '../../../../features/auth/presentation/providers/auth_provider.dart';
import '../../../../features/abonnement/presentation/providers/subscription_provider.dart';
import '../../../../shared/utils/premium_nav.dart';
import '../../../../shared/widgets/premium_gate_sheet.dart';
import '../../../../features/notifications/presentation/providers/notification_service.dart';
import '../../../../core/network/connectivity_provider.dart';
import '../../../pronostics/domain/entities/match_entity.dart' show MatchEntity;
import '../../../bankroll/presentation/widgets/miser_dialog.dart';
import '../providers/accueil_provider.dart';
import '../../../bankroll/presentation/providers/bankroll_provider.dart';
import '../../../../shared/widgets/bottom_nav_metrics.dart';
import '../../../../shared/widgets/logotype_pronowin.dart';
import '../../../../shared/widgets/pile_onglets_paresseuse.dart';
import '../../../../shared/utils/devise.dart';
import '../../../../shared/utils/bilan_paris.dart';
import '../../../../shared/providers/favoris_provider.dart';
import '../../../../shared/widgets/suivre_match.dart';
import '../../../actualites/actualites.dart';
import '../../../actualites/page_actus.dart' show ouvrirActu;
import '../../../../shared/utils/verrou_pari.dart';
import '../../../../shared/utils/verrou_pronostic.dart';
import '../../../../shared/utils/rafraichir.dart';
import '../providers/carte_vedette.dart';
import 'package:pronowin/core/utils/noms_equipes.dart';
import 'package:pronowin/shared/utils/initiale.dart';
import 'package:pronowin/core/config/sans_pari.dart';
import '../../../../shared/widgets/code_promo.dart';
import '../../../pronostics/presentation/widgets/minute_direct.dart';
import '../../../pronostics/presentation/widgets/pastille_autres_pronostics.dart';
import '../../../competitions/competitions.dart';
import '../../../notifications/presentation/demande_notifications.dart';

// Découpé en fichiers `part` : le fichier faisait 4 406 lignes pour une
// cinquantaine de classes privées — plus gros que match_detail_page avant
// sa propre découpe.
part 'accueil/entete.dart';
part 'accueil/carrousels.dart';
part 'accueil/preuve.dart';
part 'accueil/carte_prono.dart';
part 'accueil/actualites.dart';
part 'accueil/squelettes.dart';
part 'accueil/compte_a_rebours.dart';
part 'accueil/encarts.dart';
part 'accueil/mon_activite.dart';

/// Entrées animées à la première visite seulement (motion.dart).
double? get _apparitionAccueil => PremiereApparition.valeur('accueil');

/// Libellé de pronostic (réponse API brute) avec "Domicile"/"Extérieur"
/// remplacés par le nom réel de l'équipe — voir [MatchEntity.applyTeamNames].
/// Hauteur commune aux carrousels de l'accueil (pronostics du jour, en
/// direct). Une seule source : les deux sections ne peuvent pas diverger.
///
/// 186 à taille de texte normale. C'était une constante, et la carte
/// débordait de 52 px à 180 % : la hauteur suit maintenant le réglage de
/// texte du téléphone (mesuré par `accueil_texte_agrandi_test.dart`).
double _hauteurCarrousel(BuildContext context) =>
    186 + (MediaQuery.textScalerOf(context).scale(100) / 100 - 1) * 70;

/// Vrai si le nom affiché est un pseudo auto-généré du type « Parieur_5TQQC ».
bool _estPseudoGenere(String? nom) =>
    nom == null || nom.isEmpty || RegExp(r'^Parieur_').hasMatch(nom);

String _teamLabel(Map<String, dynamic> p) => MatchEntity.applyTeamNames(
      p['prediction_label'] as String? ?? '',
      homeTeam: nomEquipe(p['home_team'] as String? ?? ''),
      awayTeam: nomEquipe(p['away_team'] as String? ?? ''),
    );

class AccueilPage extends ConsumerStatefulWidget {
  const AccueilPage({super.key});

  @override
  ConsumerState<AccueilPage> createState() => _AccueilPageState();
}

/// Faut-il redemander les pronostics du jour ?
///
/// ── Ce que le minuteur ne regardait pas ───────────────────────────────────
///
/// Il ne posait qu'une question : y a-t-il un match en direct ? Si oui, il
/// rechargeait la liste, toutes les 45 secondes, sans fin.
///
/// Or `AccueilPage` reste vivante quand on passe à un autre onglet, et un
/// minuteur Dart continue quand l'application part en arrière-plan. Un match
/// en cours pendant que le téléphone est dans une poche, c'est donc une
/// requête toutes les 45 secondes — 80 par heure — pour rafraîchir un écran
/// que personne ne regarde.
///
/// ── Ce qu'il regarde maintenant ───────────────────────────────────────────
///
/// Les trois conditions doivent tenir ensemble : il y a quelque chose à
/// suivre, l'onglet est celui qu'on affiche, et l'application est au premier
/// plan. `resumed` est le seul état vraiment visible ; `inactive` couvre aussi
/// les instants où un appel arrive ou où l'on tire le volet des réglages.
///
/// ── Ce que les journaux montrent, et ne montrent pas ──────────────────────
///
/// Aucune trace de ce trafic dans les journaux nginx du jour, pour une raison
/// simple : aucun pronostic n'était publié, donc `enDirect` était faux partout.
/// Le correctif est préventif — il porte sur les jours où il y a du contenu en
/// direct, qui sont précisément ceux où l'application sert à quelque chose.
/// Le haut de l'accueil peut-il s'afficher ? Oui quand chaque réponse
/// attendue est arrivée, données ou erreur ; `null` : une réponse que ce
/// compte n'attend pas.
///
/// ── Pourquoi attendre ─────────────────────────────────────────────────────
///
/// Au démarrage, chaque bloc attend sa propre réponse, et elles arrivent dans
/// n'importe quel ordre. Le haut de l'écran se construisait bloc par bloc, et
/// chaque arrivée poussait ce qu'on lisait déjà (27 novembre 2026, mesuré par
/// `accueil_sans_saut_test.dart`) :
///
///   * la carte « Top du jour » remplaçait un squelette de 280 px par ~370 px,
///     et le code promo descendait d'autant ;
///   * pour un abonné, la bande « 30 derniers pronostics » apparaissait tout
///     en haut et poussait l'écran entier ;
///   * les blocs fixes du bas (« Grandes compétitions ») se montraient sous le
///     squelette, puis étaient chassés hors de l'écran.
///
/// Les squelettes bloc par bloc ne pouvaient pas suffire : un bloc qui n'a
/// rien à montrer (pas de bilan hier) ne peut tenir sa place qu'en la rendant
/// ensuite, ce qui fait sauter dans l'autre sens.
@visibleForTesting
bool hautDeLAccueilPret(Iterable<AsyncValue<Object?>?> attendus) =>
    attendus.every((v) => v == null || v.hasValue || v.hasError);

/// Au-delà, l'accueil s'affiche avec ce qu'il a : sur un réseau lent, mieux
/// vaut un écran qui bouge qu'un squelette sans fin.
const attenteHautMax = Duration(seconds: 4);

@visibleForTesting
bool doitRafraichirEnDirect({
  required bool enDirect,
  required bool ongletVisible,
  required AppLifecycleState cycle,
}) =>
    enDirect && ongletVisible && cycle == AppLifecycleState.resumed;

class _AccueilPageState extends ConsumerState<AccueilPage>
    with WidgetsBindingObserver {
  Timer? _liveTimer;
  String? _selectedLeague; // null = tous
  AppLifecycleState _cycle = AppLifecycleState.resumed;
  bool _ongletVisible = true;

  /// Le haut de l'accueil est affiché : il ne revient plus au squelette, même
  /// quand un rafraîchissement relance ses requêtes.
  bool _hautAffiche = false;
  Timer? _attenteHaut;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _attenteHaut = Timer(attenteHautMax, () {
      if (mounted && !_hautAffiche) setState(() => _hautAffiche = true);
    });
    // « Être notifié » : une fois, à partir de la deuxième ouverture, si le
    // téléphone n'a jamais posé la question (demande_notifications.dart).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) DemandeNotifications.proposerALAccueil(context);
    });
    _liveTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      final pronostics = ref.read(pronosticsJourProvider).valueOrNull;
      final hasLive = pronostics?.any(
        (p) => (p as Map<String, dynamic>)['status'] == 'live',
      ) ?? false;
      if (doitRafraichirEnDirect(
        enDirect:      hasLive,
        ongletVisible: _ongletVisible,
        cycle:         _cycle,
      )) {
        ref.invalidate(pronosticsJourProvider);
      }
      // Le direct des grandes compétitions, au même rythme.
      if (doitRafraichirEnDirect(
        enDirect:      ref.read(directGrandesCompetitionsProvider).valueOrNull?.isNotEmpty ?? false,
        ongletVisible: _ongletVisible,
        cycle:         _cycle,
      )) {
        ref.invalidate(directGrandesCompetitionsProvider);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState etat) {
    super.didChangeAppLifecycleState(etat);
    _cycle = etat;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _liveTimer?.cancel();
    _attenteHaut?.cancel();
    super.dispose();
  }

  // Tri : live → upcoming → finished
  List<Map<String, dynamic>> _sorted(List<dynamic> list) {
    int order(String s) => s == 'live' ? 0 : s == 'upcoming' ? 1 : 2;
    final maps = list.map((e) => e as Map<String, dynamic>).toList();
    maps.sort((a, b) {
      final so = order(a['status'] as String? ?? '').compareTo(
                 order(b['status'] as String? ?? ''));
      if (so != 0) return so;
      final da = DateTime.tryParse(a['match_date'] as String? ?? '') ?? DateTime(2099);
      final db = DateTime.tryParse(b['match_date'] as String? ?? '') ?? DateTime(2099);
      return da.compareTo(db);
    });
    return maps;
  }

  @override
  Widget build(BuildContext context) {
    // Lu ici, et pas ailleurs : `dependOnInheritedWidgetOfExactType` crée la
    // dépendance qui ramène cette page quand la pile change d'onglet. Le
    // minuteur lit ensuite le champ, sans avoir besoin d'un `BuildContext`.
    _ongletVisible = OngletVisible.de(context);

    final authState  = ref.watch(authProvider);
    final pronostics = ref.watch(pronosticsJourProvider);
    final actualites = ref.watch(actualitesProvider);
    final subAsync   = ref.watch(currentSubscriptionProvider);

    final user      = authState is AuthAuthenticated ? authState.user : null;
    final isPremium = user?.isPremium ?? false;

    // Ce que le haut de l'écran attend avant de s'afficher d'un bloc.
    if (!_hautAffiche) {
      final favoris = ref.watch(favorisProvider);
      final dejaSuivis = favoris.valueOrNull?.matchIds.isNotEmpty ?? false;
      _hautAffiche = hautDeLAccueilPret([
        pronostics,
        ref.watch(nextPronosticProvider),
        ref.watch(hierProvider),
        ref.watch(promoPartenaireProvider),
        favoris,
        // Les matchs suivis, seulement quand il y en a : sinon le bloc reste
        // vide, et sa réponse ne change rien à l'écran.
        dejaSuivis ? ref.watch(favoritesListProvider) : null,
        // La bande de preuve, réservée aux abonnés.
        isPremium ? ref.watch(performance30Provider) : null,
      ]);
      if (_hautAffiche) _attenteHaut?.cancel();
    }

    return Scaffold(
      body: RefreshIndicator(
        color: AppColors.primary,
        backgroundColor: context.cl.surface,
        onRefresh: () async {
          ref.invalidate(pronosticsJourProvider);
          ref.invalidate(actualitesProvider);
          ref.invalidate(favoritesListProvider);
          ref.invalidate(statsJourProvider);
          ref.invalidate(nextPronosticProvider);
          ref.invalidate(currentSubscriptionProvider);
          // L'indicateur reste affiché jusqu'au retour des données, au lieu
          // de se refermer avant la première réponse.
          await attendreChargements([
            ref.read(pronosticsJourProvider.future),
            ref.read(actualitesProvider.future),
            ref.read(favoritesListProvider.future),
            ref.read(statsJourProvider.future),
            ref.read(nextPronosticProvider.future),
            ref.read(currentSubscriptionProvider.future),
          ]);
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [

            // ─── HEADER COLLAPSIBLE ─────────────────────────────────────────
            _SliverHeader(user: user, isPremium: isPremium),

            // ─── BANNIÈRE HORS LIGNE ─────────────────────────────────────────
            const _SliverOfflineBanner(),

            // ─── EN ATTENDANT LE HAUT DE L'ÉCRAN ─────────────────────────────
            // Les squelettes seuls : les blocs fixes du bas n'y sont pas, sans
            // quoi ils se montreraient sous le squelette avant d'être chassés
            // hors de l'écran.
            if (!_hautAffiche)
              SliverPadding(
                padding: EdgeInsets.fromLTRB(margeEcran, 0, margeEcran, bottomNavSpace(context)),
                sliver: SliverList(
                  key: const Key('accueil-chargement'),
                  delegate: SliverChildListDelegate([
                    const _BandeauHierSquelette(),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: _NextMatchSkeleton(),
                    ),
                    const _PronosticsShimmer(),
                  ]),
                ),
              )
            else
            SliverPadding(
              padding: EdgeInsets.fromLTRB(margeEcran, 0, margeEcran, bottomNavSpace(context)),
              sliver: SliverList(
                delegate: SliverChildListDelegate([

                  // ─── PREUVE & BILAN D'HIER ────────────────────────────────
                  // Avant de proposer quoi que ce soit, montrer ce que valent
                  // les pronostics passés.
                  const _ProofBand(),
                  const _YesterdayRecap(),

                  // ─── MES FAVORIS ──────────────────────────────────────────
                  const _FavoritesSection()
                    .animate(value: _apparitionAccueil)
                    .fadeIn(duration: 400.ms)
                    .slideY(begin: 0.08, end: 0, duration: 350.ms,
                        curve: Curves.easeOutCubic),

                  // ─── COUNTDOWN PROCHAIN MATCH ─────────────────────────────
                  const _NextMatchCountdown()
                    .animate(value: _apparitionAccueil)
                    .fadeIn(duration: 500.ms)
                    .slideY(begin: 0.08, end: 0, duration: 400.ms,
                        curve: Curves.easeOutCubic),

                  // ─── CODE PROMO DU PARTENAIRE (7 novembre 2026) ───────────
                  const CarteCodePromo(),

                  // ─── MATCHS EN LIVE ───────────────────────────────────────
                  pronostics.when(
                    loading: () => const SizedBox.shrink(),
                    error:   (_, _) => const SizedBox.shrink(),
                    data: (list) {
                      final live = list.where(
                        (p) => (p as Map<String, dynamic>)['status'] == 'live'
                      ).toList();
                      if (live.isEmpty) return const SizedBox.shrink();
                      return Column(children: [
                        _SectionHeader(
                          title: tr(context, "En direct"),
                          leading: const _LivePulseDot(size: 9),
                          showBadge: live.length,
                          onMore: () => context.go('/pronostics'),
                        ),
                        const SizedBox(height: 12),
                        _LiveMatchesCarousel(matches: live, isPremium: isPremium),
                        const SizedBox(height: 24),
                      ]);
                    },
                  ),

                  // « Top prono du jour » avait sa propre grande carte ici. Elle
                  // montrait souvent le même match que la carte du compte à
                  // rebours : les deux sont fusionnées (carte_vedette.dart).

                  // ─── BANNIÈRE PREMIUM ─────────────────────────────────────
                  // Placée après le contenu (top prono) : l'app montre d'abord
                  // sa valeur avant de proposer l'abonnement.
                  if (!isPremium) ...[
                    _PremiumBanner(
                      // Toujours naviguer. `whenData` ne rappelait qu'une fois
                      // l'abonnement chargé : pendant le chargement ou après
                      // une erreur, le toucher ne faisait rien. Le paywall
                      // charge lui-même ce qui lui manque.
                      onTap: () => goToPremium(context, ref,
                          extra: subAsync.valueOrNull),
                    )
                      .animate(value: _apparitionAccueil)
                      .fadeIn(duration: 500.ms, delay: 200.ms)
                      .slideY(begin: 0.08, end: 0, duration: 400.ms,
                          curve: Curves.easeOutCubic),
                    const SizedBox(height: 24),
                  ],

                  // ─── PRONOSTICS DU JOUR (filtrés + triés) ────────────────
                  pronostics.when(
                    // Rien pendant le chargement : la carte « Top du jour »
                    // porte déjà le squelette de l'écran. Cette section en
                    // affichait un second, qui disparaissait ensuite quand le
                    // jour ne comptait qu'un pronostic — déjà en vedette.
                    loading: () => const SizedBox.shrink(),
                    error: (_, _) => _ErrorCard(
                        onRetry: () => ref.invalidate(pronosticsJourProvider)),
                    data: (list) {
                      if (list.isEmpty) return const _EmptyPronostics();

                      // La section « En direct » juste au-dessus affiche déjà
                      // tous les matchs en cours : les répéter ici mettait deux
                      // fois la même carte à quelques centimètres d'écart.
                      // La carte vedette est déjà en haut de l'écran : la
                      // répéter ici la montrait une deuxième fois.
                      final idVedette = choisirVedette(
                        duJour:   list,
                        prochain: ref.watch(nextPronosticProvider).valueOrNull,
                      )?.prono['id'];
                      final aVenir = list
                          .where((p) =>
                              (p as Map<String, dynamic>)['status'] != 'live' &&
                              p['id'] != idVedette)
                          .toList();
                      // Tout est en direct : il n'y a rien à ajouter.
                      if (aVenir.isEmpty) return const SizedBox.shrink();

                      final allSorted = _sorted(aVenir);

                      // Ligues uniques pour les chips
                      final leagues = <String>[];
                      for (final p in allSorted) {
                        final l = p['league'] as String? ?? '';
                        if (l.isNotEmpty && !leagues.contains(l)) leagues.add(l);
                      }

                      // Filtrage par ligue sélectionnée
                      final filtered = _selectedLeague == null
                          ? allSorted
                          : allSorted.where((p) => p['league'] == _selectedLeague).toList();

                      // Teaser d'accueil : 5 max en vue par défaut ("Voir tout"
                      // renvoie vers l'onglet Pronos pour le reste). Une fois
                      // qu'une ligue précise est sélectionnée via les chips,
                      // on montre tous ses matchs — l'utilisateur a explicitement
                      // demandé à en voir plus.
                      final displayed = _selectedLeague == null
                          ? filtered.take(5).toList()
                          : filtered;

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _SectionHeader(title: tr(context, "Pronostics du jour"),
                              onMore: () => context.go('/pronostics')),
                          const SizedBox(height: 10),

                          // ── Filtre par ligue ──────────────────────────────
                          if (leagues.length > 1)
                            _LeagueFilterChips(
                              leagues: leagues,
                              selected: _selectedLeague,
                              onSelect: (l) =>
                                  setState(() => _selectedLeague = l),
                            ),
                          const SizedBox(height: 12),

                          // ── Carrousel ──────────────────────────────────────
                          // La carte détaillée coûte cher en vertical ; en
                          // horizontal elle ne le coûte qu'une fois. La carte
                          // suivante dépasse volontairement du bord : c'est ce
                          // qui signale qu'on peut faire défiler.
                          SizedBox(
                            height: _hauteurCarrousel(context),
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              padding: EdgeInsets.zero,
                              itemCount: displayed.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(width: 10),
                              itemBuilder: (context, i) {
                                final p = displayed[i];
                                return SizedBox(
                                  width: MediaQuery.of(context).size.width * 0.84,
                                  child: _PronosticCard(
                                    prono: p,
                                    isPremium: isPremium,
                                    compact: true,
                                    onTap: () => context.push(
                                        '/pronostics/${p['id']}', extra: null),
                                  ),
                                );
                              },
                            ),
                          )
                            .animate(value: _apparitionAccueil)
                            .fadeIn(duration: 300.ms)
                            .slideY(begin: 0.06, end: 0,
                                duration: 280.ms, curve: Curves.easeOutCubic),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 28),

                  // ─── GRANDES COMPÉTITIONS (8 novembre 2026, 1xBet) ───────
                  // Après les pronostics du jour : la question posée en
                  // ouvrant l'app passe avant les raccourcis.
                  const GrandesCompetitions(),
                  // Leurs matchs en direct, pronostiqués ou non (1xBet).
                  const DirectGrandesCompetitions(),

                  // ─── MON ACTIVITÉ ─────────────────────────────────────────
                  // Ces blocs parlent de l'utilisateur, pas des matchs du
                  // jour : ils occupaient le haut de l'écran alors que la
                  // question posée en ouvrant l'app est « sur quoi je parie
                  // aujourd'hui ? ».
                  // ─── NUDGE PSEUDO ─────────────────────────────────────────
                  // Invite à personnaliser le pseudo auto-généré (Parieur_XXX).
                  _PseudoNudge(user: user)
                    .animate(value: _apparitionAccueil)
                    .fadeIn(duration: 400.ms, delay: 140.ms),

                  // La bankroll, les chiffres des pronostics et la méthode, en
                  // une carte repliable (9 novembre 2026, accueil/mon_activite.dart).
                  // Le bandeau « Streak » a été retiré auparavant : il
                  // récompensait l'ouverture quotidienne de l'application, le
                  // motif même que les stores et les régulateurs examinent.
                  _MonActivite(isPremium: isPremium, avecBankroll: !ref.watch(sansPariProvider))
                    .animate(value: _apparitionAccueil)
                    .fadeIn(duration: 400.ms, delay: 100.ms),

                  // ─── ACTUALITÉS ───────────────────────────────────────────
                  actualites.when(
                    loading: () => const _NewsShimmer(),
                    error:   (_, _) => const SizedBox.shrink(),
                    data: (news) {
                      if (news.isEmpty) return const SizedBox.shrink();
                      return _NewsSection(items: news.cast<Map<String, dynamic>>());
                    },
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════'
// SLIVER HEADER
// ══════════════════════════════════════════════════════════════════════════════'
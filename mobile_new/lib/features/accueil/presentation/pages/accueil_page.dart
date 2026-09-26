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
import '../../../../shared/widgets/pile_onglets_paresseuse.dart';
import '../../../../shared/utils/devise.dart';
import '../../../../shared/utils/bilan_paris.dart';
import '../../../../shared/providers/favoris_provider.dart';
import '../../../../shared/utils/verrou_pari.dart';
import '../../../../shared/utils/verrou_pronostic.dart';

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

/// Libellé de pronostic (réponse API brute) avec "Domicile"/"Extérieur"
/// remplacés par le nom réel de l'équipe — voir [MatchEntity.applyTeamNames].
/// Hauteur commune aux carrousels de l'accueil (pronostics du jour, en
/// direct). Une seule constante : les deux sections ne peuvent pas diverger.
const double _kCarouselCardHeight = 186;

/// Vrai si le nom affiché est un pseudo auto-généré du type « Parieur_5TQQC ».
bool _estPseudoGenere(String? nom) =>
    nom == null || nom.isEmpty || RegExp(r'^Parieur_').hasMatch(nom);

String _teamLabel(Map<String, dynamic> p) => MatchEntity.applyTeamNames(
      p['prediction_label'] as String? ?? '',
      homeTeam: p['home_team'] as String? ?? '',
      awayTeam: p['away_team'] as String? ?? '',
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [

            // ─── HEADER COLLAPSIBLE ─────────────────────────────────────────
            _SliverHeader(user: user, isPremium: isPremium),

            // ─── BANNIÈRE HORS LIGNE ─────────────────────────────────────────
            const _SliverOfflineBanner(),

            SliverPadding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, bottomNavSpace(context)),
              sliver: SliverList(
                delegate: SliverChildListDelegate([

                  // ─── PREUVE & BILAN D'HIER ────────────────────────────────
                  // Avant de proposer quoi que ce soit, montrer ce que valent
                  // les pronostics passés.
                  const _ProofBand(),
                  const _YesterdayRecap(),

                  // ─── MES FAVORIS ──────────────────────────────────────────
                  const _FavoritesSection()
                    .animate()
                    .fadeIn(duration: 400.ms)
                    .slideY(begin: 0.08, end: 0, duration: 350.ms,
                        curve: Curves.easeOutCubic),

                  // ─── COUNTDOWN PROCHAIN MATCH ─────────────────────────────
                  const _NextMatchCountdown()
                    .animate()
                    .fadeIn(duration: 500.ms)
                    .slideY(begin: 0.08, end: 0, duration: 400.ms,
                        curve: Curves.easeOutCubic),

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
                          title: 'En direct',
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

                  // ─── TOP PRONO DU JOUR ────────────────────────────────────
                  pronostics.when(
                    loading: () => const SizedBox.shrink(),
                    error:   (_, _) => const SizedBox.shrink(),
                    data: (list) {
                      if (list.isEmpty) return const SizedBox.shrink();
                      // Exclure les matchs terminés et ceux dont l'heure est dépassée
                      final candidates = list
                          .map((e) => e as Map<String, dynamic>)
                          .where((p) {
                            final status = p['status'] as String? ?? '';
                            if (status == 'finished') return false;
                            // Les matchs en cours ont leur propre section juste
                            // au-dessus : les remonter ici affichait deux fois
                            // la même rencontre à un écran d'intervalle.
                            if (status == 'live') return false;
                            final dateStr = p['match_date'] as String?;
                            if (dateStr != null) {
                              final date = DateTime.tryParse(dateStr);
                              if (date != null && date.isBefore(DateTime.now())) return false;
                            }
                            return true;
                          })
                          .toList()
                        ..sort((a, b) => ((b['confidence_score'] as num? ?? 0)
                            .compareTo(a['confidence_score'] as num? ?? 0)));
                      if (candidates.isEmpty) return const SizedBox.shrink();
                      final top = candidates.first;
                      final isLocked = (top['is_premium'] as bool? ?? false) && !isPremium;
                      // Verrouillé : on montre le match en teaser (équipes +
                      // confiance) au lieu de le cacher — le tap mène à Premium.
                      return Column(children: [
                        const _SectionHeader(title: 'Top prono du jour'),
                        const SizedBox(height: 12),
                        _HeroPronoCard(
                          prono: top,
                          locked: isLocked,
                          onTap: isLocked
                              ? () => subAsync.whenData(
                                  (sub) => goToPremium(context, ref, extra: sub))
                              : () => context.push('/pronostics/${top['id']}',
                                  extra: null),
                        ),
                        const SizedBox(height: 24),
                      ]);
                    },
                  ),

                  // ─── BANNIÈRE PREMIUM ─────────────────────────────────────
                  // Placée après le contenu (top prono) : l'app montre d'abord
                  // sa valeur avant de proposer l'abonnement.
                  if (!isPremium) ...[
                    _PremiumBanner(
                      onTap: () => subAsync.whenData(
                          (sub) => goToPremium(context, ref, extra: sub)),
                    )
                      .animate()
                      .fadeIn(duration: 500.ms, delay: 200.ms)
                      .slideY(begin: 0.08, end: 0, duration: 400.ms,
                          curve: Curves.easeOutCubic),
                    const SizedBox(height: 24),
                  ],

                  // ─── PRONOSTICS DU JOUR (filtrés + triés) ────────────────
                  pronostics.when(
                    loading: () => Column(children: [
                      _SectionHeader(title: 'Pronostics du jour',
                          onMore: () => context.go('/pronostics')),
                      const SizedBox(height: 12),
                      const _PronosticsShimmer(),
                    ]),
                    error: (_, _) => _ErrorCard(
                        onRetry: () => ref.invalidate(pronosticsJourProvider)),
                    data: (list) {
                      if (list.isEmpty) return const _EmptyPronostics();

                      // La section « En direct » juste au-dessus affiche déjà
                      // tous les matchs en cours : les répéter ici mettait deux
                      // fois la même carte à quelques centimètres d'écart.
                      final aVenir = list
                          .where((p) =>
                              (p as Map<String, dynamic>)['status'] != 'live')
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
                          _SectionHeader(title: 'Pronostics du jour',
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
                            height: _kCarouselCardHeight,
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
                            .animate()
                            .fadeIn(duration: 300.ms)
                            .slideY(begin: 0.06, end: 0,
                                duration: 280.ms, curve: Curves.easeOutCubic),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 28),

                  // ─── MON ACTIVITÉ ─────────────────────────────────────────
                  // Ces blocs parlent de l'utilisateur, pas des matchs du
                  // jour : ils occupaient le haut de l'écran alors que la
                  // question posée en ouvrant l'app est « sur quoi je parie
                  // aujourd'hui ? ».
                  // ─── BANKROLL MINI-WIDGET ─────────────────────────────────
                  const _BankrollMiniWidget()
                    .animate()
                    .fadeIn(duration: 400.ms, delay: 80.ms)
                    .slideY(begin: 0.08, end: 0, duration: 350.ms,
                        curve: Curves.easeOutCubic),

                  // Le bandeau « Streak » a été retiré. Il récompensait
                  // l'ouverture quotidienne de l'application — un mécanisme qui
                  // ne rendait personne meilleur en pronostics, et dont l'XP
                  // n'était consommé nulle part. Surtout, récompenser le retour
                  // quotidien dans une application liée aux paris est le motif
                  // même que les stores et les régulateurs examinent.
                  // La bankroll, juste au-dessus, occupe désormais la place.

                  // ─── NUDGE PSEUDO ─────────────────────────────────────────
                  // Invite à personnaliser le pseudo auto-généré (Parieur_XXX).
                  _PseudoNudge(user: user)
                    .animate()
                    .fadeIn(duration: 400.ms, delay: 140.ms),

                  // ─── STATS RAPIDES ────────────────────────────────────────
                  _QuickStats(isPremium: isPremium)
                    .animate()
                    .fadeIn(duration: 400.ms, delay: 100.ms)
                    .slideY(begin: 0.1, end: 0, duration: 400.ms,
                        curve: Curves.easeOutCubic),
                  const SizedBox(height: 24),

                  // ─── BANNIÈRE TUTORIELS ───────────────────────────────────
                  _TutorielsBanner()
                    .animate(delay: 200.ms)
                    .fadeIn(duration: 350.ms)
                    .slideY(begin: 0.05, end: 0),
                  const SizedBox(height: 24),

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
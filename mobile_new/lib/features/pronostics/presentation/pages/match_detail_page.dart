import 'dart:async';
import 'dart:ui';
import 'package:confetti/confetti.dart';
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

class _MatchDetailPageState extends ConsumerState<MatchDetailPage> {
  Timer? _liveTimer;

  @override
  void dispose() {
    _liveTimer?.cancel();
    super.dispose();
  }

  void _startLivePolling() {
    _liveTimer?.cancel();
    _liveTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      ref.invalidate(liveScoreProvider(widget.matchId));
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
    final tabsDataLoading = showTabs && (
      lineupsAsync.isLoading || injuriesAsync.isLoading ||
      standingsAsync.isLoading || h2hAsync.isLoading ||
      statsAsync.isLoading);

    // Un 401 (invité) affiche quand même l'onglet — avec une invite à se
    // connecter à l'intérieur — plutôt que de le cacher comme s'il n'y avait
    // rien à voir.
    bool visibleOrPrompt(AsyncValue<Object?> async, bool Function() hasContent) {
      final status = _statusOf(async.error);
      if (status == 401) return true;
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
    final showClassements  = showTabs && visibleOrPrompt(standingsAsync,
      () => standingsAsync.valueOrNull?.isNotEmpty == true);
    final showFaceAFace    = showTabs && visibleOrPrompt(h2hAsync,
      () => h2hAsync.valueOrNull?.matches.isNotEmpty == true);

    Widget scrollTab(Widget child) => SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: child,
    );

    final tabs = <(String, Widget)>[
      if (showTabs) ('Détails', scrollTab(Column(children: [
        // Entrée en cascade : chaque carte apparaît légèrement après la
        // précédente, ce qui guide le regard de haut en bas au lieu d'afficher
        // le bloc d'un coup.
        if (match.hasPronostic) ...[
          _PronosticCard(match: match, isLocked: isLocked)
            .animate().fadeIn(duration: 350.ms)
            .slideY(begin: 0.06, end: 0, curve: Curves.easeOutCubic),
          const SizedBox(height: 16),
        ],
        if (showEvents) ...[
          _MatchEventsCard(matchId: match.id, match: match)
            .animate(delay: 90.ms).fadeIn(duration: 350.ms)
            .slideY(begin: 0.06, end: 0, curve: Curves.easeOutCubic),
          const SizedBox(height: 16),
        ],
        if (match.homeFormPoints > 0 || match.awayFormPoints > 0) ...[
          _FormCard(match: match)
            .animate(delay: 140.ms).fadeIn(duration: 350.ms)
            .slideY(begin: 0.06, end: 0, curve: Curves.easeOutCubic),
          const SizedBox(height: 16),
        ],
        _AIAnalysisCard(matchId: match.id, status: match.status)
          .animate(delay: 190.ms).fadeIn(duration: 350.ms)
          .slideY(begin: 0.06, end: 0, curve: Curves.easeOutCubic),
        const SizedBox(height: 16),
        if (match.status == MatchStatus.upcoming) ...[
          _MiserButton(match: match)
            .animate(delay: 240.ms).fadeIn(duration: 350.ms)
            .slideY(begin: 0.06, end: 0, curve: Curves.easeOutCubic),
          const SizedBox(height: 16),
        ],
        if (match.analystNote?.isNotEmpty == true) ...[
          _AnalystCard(match: match)
            .animate(delay: 270.ms).fadeIn(duration: 350.ms)
            .slideY(begin: 0.06, end: 0, curve: Curves.easeOutCubic),
          const SizedBox(height: 16),
        ],
        CommentsSection(pronosticId: match.id)
          .animate(delay: 310.ms).fadeIn(duration: 350.ms)
          .slideY(begin: 0.06, end: 0, curve: Curves.easeOutCubic),
      ]))),
      if (showCotes) ('Cotes', scrollTab(_OddsCard(match: match))),
      if (showStats) ('Statistiques', scrollTab(_MatchStatsCard(matchId: match.id))),
      if (showCompositions) ('Compositions', scrollTab(_LineupsCard(matchId: match.id))),
      if (showBlessures) ('Blessures', scrollTab(_InjuriesCard(
        matchId: match.id,
        homeTeam: match.homeTeam,
        awayTeam: match.awayTeam,
        homeLogo: match.homeTeamLogo,
        awayLogo: match.awayTeamLogo))),
      if (showClassements) ('Classements', scrollTab(_StandingsCard(matchId: match.id))),
      if (showFaceAFace) ('Face à face', scrollTab(_H2HCard(
        matchId: match.id,
        homeLogo: match.homeTeamLogo,
        awayLogo: match.awayTeamLogo))),
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
          // Spinner discret pendant le refresh live
          if (isRefreshing)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: SizedBox(
                width: 16, height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.error))),
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
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: _MatchHeader(match: match)
            .animate().fadeIn(duration: 350.ms)
            .slideY(begin: -0.04, end: 0, curve: Curves.easeOutCubic),
        ),
        if (!showTabs) ...[
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
              child: Column(children: [
                if (match.hasPronostic) ...[
                  _PronosticCard(match: match, isLocked: isLocked)
                    .animate(delay: 130.ms).fadeIn(duration: 350.ms)
                    .slideY(begin: 0.06, end: 0, curve: Curves.easeOutCubic),
                  const SizedBox(height: 16),
                ],
                if (match.status == MatchStatus.finished) ...[
                  _MatchStatsCard(matchId: match.id)
                    .animate(delay: 170.ms).fadeIn(duration: 350.ms)
                    .slideY(begin: 0.06, end: 0, curve: Curves.easeOutCubic),
                  const SizedBox(height: 16),
                ],
                if (isLocked)
                  _PremiumBanner(
                    onTap: () => goToPremium(context, ref))
                    .animate(delay: 200.ms).fadeIn(duration: 400.ms)
                    .scale(begin: const Offset(0.95, 0.95), end: const Offset(1, 1),
                      curve: Curves.easeOutBack),
              ]),
            ),
          ),
        ] else if (tabsDataLoading) ...[
          const Expanded(child: Center(child: CircularProgressIndicator())),
        ] else if (tabs.length <= 1) ...[
          Expanded(child: tabs.first.$2),
        ] else ...[
          const SizedBox(height: 4),
          Expanded(
            child: DefaultTabController(
              length: tabs.length,
              child: Column(children: [
                TabBar(
                  isScrollable: true,
                  labelColor: AppColors.primary,
                  unselectedLabelColor: context.cl.textS,
                  indicatorColor: AppColors.primary,
                  labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  tabs: [for (final t in tabs) Tab(text: t.$1)],
                ),
                Expanded(
                  child: TabBarView(
                    children: [for (final t in tabs) t.$2],
                  ),
                ),
              ]),
            ),
          ),
        ],
      ]),
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

    final d = match.matchDate;
    final dateTimeStr =
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/'
      '${d.year} · '
      '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';

    return Container(
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
              _LiveBadge(),
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
              Text(
                '${match.matchDate.hour.toString().padLeft(2, '0')}:'
                '${match.matchDate.minute.toString().padLeft(2, '0')}',
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
  );
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

  @override
  Widget build(BuildContext context) => Container(
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
          Expanded(child: _DetailConfidenceBar(score: match.confidenceScore)),
        ]),
      ],

      // Verdict intégré à la carte : le pronostic et son issue racontent la
      // même histoire, les séparer en deux blocs obligeait à répéter la cote.
      if (match.result != null) ...[
        const SizedBox(height: 16),
        _VerdictStrip(result: match.result!, pronosticId: match.id),
      ],
    ]),
  );
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

class _VerdictStripState extends State<_VerdictStrip> {
  late final ConfettiController _confetti;

  static const _prefKey = 'celebrated_win_';

  @override
  void initState() {
    super.initState();
    _confetti = ConfettiController(duration: const Duration(milliseconds: 1500));
    if (widget.result == PronosticResult.win) _maybeCelebrate();
  }

  /// Les confettis ne se déclenchent qu'à la première consultation d'un
  /// pronostic gagnant — revenir sur la page ne les rejoue pas.
  Future<void> _maybeCelebrate() async {
    final prefs   = await SharedPreferences.getInstance();
    final key     = '$_prefKey${widget.pronosticId}';
    final already = prefs.getBool(key) ?? false;
    if (already || !mounted) return;

    await prefs.setBool(key, true);

    Future.delayed(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      HapticFeedback.vibrate();
      _confetti.play();
    });
  }

  @override
  void dispose() {
    _confetti.dispose();
    super.dispose();
  }

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

    return Stack(alignment: Alignment.topCenter, children: [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.35), width: 1)),
        child: Row(children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label,
              style: TextStyle(
                color: color, fontSize: 14, fontWeight: FontWeight.w800))),
        ]),
      ),
      if (isWin)
        ConfettiWidget(
          confettiController: _confetti,
          blastDirectionality: BlastDirectionality.explosive,
          numberOfParticles: 18,
          maxBlastForce: 12,
          minBlastForce: 4,
          gravity: 0.3,
          colors: const [
            AppColors.success,
            AppColors.warning,
            AppColors.primary,
            Color(0xFFFFFFFF),
          ],
          shouldLoop: false,
        ),
    ]);
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

    // Une seule ligne : le pastille verte indique déjà la cote recommandée,
    // pas besoin d'un second bloc en dessous qui répète la même valeur.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: context.cl.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.cl.border, width: 0.5)),
      child: Row(children: [
        Text('COTES', style: TextStyle(
          color: context.cl.textM, fontSize: 11,
          fontWeight: FontWeight.w600, letterSpacing: 1)),
        const Spacer(),
        _OddPill(label: '1', value: match.oddsHome,
          isRecommended: match.predictionType == PredictionType.win1),
        const SizedBox(width: 8),
        _OddPill(label: 'X', value: match.oddsDraw,
          isRecommended: match.predictionType == PredictionType.draw),
        const SizedBox(width: 8),
        _OddPill(label: '2', value: match.oddsAway,
          isRecommended: match.predictionType == PredictionType.win2),
      ]),
    );
  }
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
          .animate(onPlay: (c) => c.repeat())
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

class _LiveBadge extends StatefulWidget {
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
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.4, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
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
      const Text('EN DIRECT', style: TextStyle(
        color: AppColors.error, fontSize: 11,
        fontWeight: FontWeight.w700, letterSpacing: 0.5)),
    ]));
}

class _DetailConfidenceBar extends StatelessWidget {
  final int score;
  const _DetailConfidenceBar({required this.score});

  Color get _color {
    if (score >= 5) return AppColors.success;
    if (score >= 4) return const Color(0xFF84CC16);
    if (score >= 3) return AppColors.warning;
    if (score >= 2) return const Color(0xFFF97316);
    return AppColors.error;
  }

  String get _label {
    if (score >= 5) return 'Excellent';
    if (score >= 4) return 'Bon';
    if (score >= 3) return 'Moyen';
    if (score >= 2) return 'Faible';
    return 'Risqué';
  }

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

String _buildShareText(MatchEntity match) {
  final date   = DateFormat('dd/MM/yyyy à HH:mm', 'fr_FR').format(match.matchDate);
  final link   = 'https://pronowin.app/pronostics/${match.id}';
  return '⚽ *PronoWin — Pronostic*\n\n'
      '🏟️ ${match.homeTeam} vs ${match.awayTeam}\n'
      '🏆 ${match.league}\n'
      '📅 $date\n\n'
      '🔮 *Pronostic :* ${match.displayPredictionLabel}\n'
      '📊 Confiance : ${match.confidencePercent}%\n'
      '💰 Cote recommandée : ${match.oddsRecommended.toStringAsFixed(2)}\n\n'
      '📲 Voir le pronostic complet : $link\n'
      '⬇️ Télécharge PronoWin pour tous les pronos !';
}

Future<void> _launchShare(String url) async {
  final uri = Uri.parse(url);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

void _showShareSheet(BuildContext context, MatchEntity match) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _ShareSheet(match: match),
  );
}

class _ShareSheet extends StatefulWidget {
  final MatchEntity match;
  const _ShareSheet({required this.match});
  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  final _cardKey = GlobalKey();
  bool _capturing = false;

  Future<void> _shareImage() async {
    if (_capturing) return;
    setState(() => _capturing = true);
    try {
      final text = _buildShareText(widget.match);
      await PronoShareService.captureAndShare(
        repaintKey: _cardKey,
        shareText:  text,
        pixelRatio: 3.0,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erreur de capture : $e'),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = _buildShareText(widget.match);

    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize:     0.5,
      maxChildSize:     0.95,
      builder: (_, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color:        context.cl.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border:       Border.all(color: context.cl.border, width: 0.5),
        ),
        child: ListView(
          controller: scrollCtrl,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          children: [

            // ── Handle ──────────────────────────────────────────────────────
            Center(
              child: Container(
                width: 36, height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: context.cl.borderS,
                  borderRadius: BorderRadius.circular(2)),
              ),
            ),

            Text('Partager ce pronostic',
              style: TextStyle(
                color: context.cl.textP, fontSize: 15,
                fontWeight: FontWeight.w700),
              textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text('${widget.match.homeTeam} vs ${widget.match.awayTeam}',
              style: TextStyle(color: context.cl.textS, fontSize: 12),
              textAlign: TextAlign.center),
            const SizedBox(height: 20),

            // ── Prévisualisation de la carte ─────────────────────────────────
            Center(
              child: RepaintBoundary(
                key: _cardKey,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: PronoShareCard(match: widget.match),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // ── Bouton principal : Partager l'image ──────────────────────────
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _capturing ? null : _shareImage,
                icon: _capturing
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.image_rounded, size: 18),
                label: Text(_capturing ? 'Génération…' : 'Partager l\'image'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                  textStyle: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // ── Boutons alternatifs ──────────────────────────────────────────
            Row(children: [
              Expanded(child: _ShareBtn(
                fallbackIcon: Icons.chat_rounded,
                label: 'WhatsApp',
                color: const Color(0xFF25D366),
                onTap: () async {
                  final encoded = Uri.encodeComponent(text);
                  await _launchShare('https://wa.me/?text=$encoded');
                  if (context.mounted) Navigator.pop(context);
                },
              )),
              const SizedBox(width: 10),
              Expanded(child: _ShareBtn(
                fallbackIcon: Icons.send_rounded,
                label: 'Telegram',
                color: const Color(0xFF0088CC),
                onTap: () async {
                  final encoded = Uri.encodeComponent(text);
                  await _launchShare('https://t.me/share/url?url=https://pronowin.app&text=$encoded');
                  if (context.mounted) Navigator.pop(context);
                },
              )),
              const SizedBox(width: 10),
              Expanded(child: _ShareBtn(
                fallbackIcon: Icons.copy_rounded,
                label: 'Copier',
                color: AppColors.primary,
                onTap: () {
                  Clipboard.setData(ClipboardData(text: text));
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Pronostic copié !'),
                    behavior: SnackBarBehavior.floating,
                    duration: Duration(seconds: 2),
                  ));
                },
              )),
            ]),
          ],
        ),
      ),
    );
  }
}

class _ShareBtn extends StatelessWidget {
  final IconData fallbackIcon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ShareBtn({
    required this.fallbackIcon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () { HapticFeedback.lightImpact(); onTap(); },
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 0.5)),
      child: Column(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            shape: BoxShape.circle),
          child: Center(child: Icon(fallbackIcon, color: color, size: 20)),
        ),
        const SizedBox(height: 8),
        Text(label, style: TextStyle(
          color: color, fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
    ),
  );
}

// ─── COMPOSITIONS D'ÉQUIPE ──────────────────────────────────────────────────────

/// Code HTTP d'une erreur Dio, ou null si ce n'en est pas une — utilisé pour
/// distinguer un invité non connecté (401) d'une vraie panne réseau/serveur.
int? _statusOf(Object? error) =>
    error is DioException ? error.response?.statusCode : null;

/// Message compact affiché à la place du contenu d'une carte (Compositions,
/// Blessures, Classement, H2H) quand elle exige une connexion — plutôt que de
/// faire disparaître silencieusement la carte, ce qui donne l'impression que
/// le match n'a aucune donnée alors qu'il suffit de se connecter.
class _CardLoginPrompt extends StatelessWidget {
  final String message;
  const _CardLoginPrompt({required this.message});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => context.push('/auth/email?from=${Uri.encodeComponent('/pronostics')}'),
    child: Row(children: [
      Icon(Icons.login_rounded, color: AppColors.primary, size: 16),
      const SizedBox(width: 8),
      Expanded(
        child: Text(message,
          style: TextStyle(color: context.cl.textM, fontSize: 12))),
      Icon(Icons.chevron_right_rounded, color: AppColors.primary, size: 18),
    ]),
  );
}

class _LineupsCard extends ConsumerWidget {
  final String matchId;
  const _LineupsCard({required this.matchId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lineupsAsync = ref.watch(lineupsProvider(matchId));
    final status = _statusOf(lineupsAsync.error);

    // Vraie erreur réseau/serveur (pas juste un invité non connecté) → pas de
    // carte plutôt qu'un message alarmant.
    if (lineupsAsync.hasError && status != 401) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cl.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.cl.borderSoft, width: 0.8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.groups_rounded, color: AppColors.primary, size: 16),
          ),
          const SizedBox(width: 10),
          Text('Compositions',
            style: TextStyle(
              color: context.cl.textP,
              fontSize: 13,
              fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 14),
        status == 401
          ? const _CardLoginPrompt(message: 'Connecte-toi pour voir les compositions.')
          : lineupsAsync.when(
              loading: () => _H2HLoading(),
              error: (_, __) => const SizedBox.shrink(),
              data: (lineups) => !lineups.available
                ? _LineupsPending()
                : _LineupsContent(lineups: lineups),
            ),
      ]),
    );
  }
}

class _LineupsPending extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(Icons.schedule_rounded, color: context.cl.textM, size: 16),
    const SizedBox(width: 8),
    Expanded(
      child: Text('Compositions pas encore annoncées — publiées ~1h avant le coup d\'envoi.',
        style: TextStyle(color: context.cl.textM, fontSize: 12))),
  ]);
}

class _LineupsContent extends StatelessWidget {
  final LineupsData lineups;
  const _LineupsContent({required this.lineups});

  /// Le terrain n'a de sens que si l'API a placé les joueurs (champ `grid`).
  /// Certaines compétitions mineures ne le renseignent pas — on retombe alors
  /// sur la liste en pastilles, qui reste lisible sans coordonnées.
  bool _placeable(TeamLineup? t) =>
    t != null && t.startXI.isNotEmpty && t.startXI.every((p) => p.gridRow != null);

  @override
  Widget build(BuildContext context) {
    final home = lineups.home, away = lineups.away;

    if (_placeable(home) || _placeable(away)) {
      return Column(children: [
        _PitchView(home: home, away: away),
        const SizedBox(height: 14),
        if (home != null) _TeamCoachRow(team: home, color: AppColors.success),
        if (home != null && away != null) const SizedBox(height: 6),
        if (away != null) _TeamCoachRow(team: away, color: AppColors.error),
      ]);
    }

    return Column(children: [
      if (home != null) _TeamLineupBlock(team: home, color: AppColors.success),
      if (home != null && away != null) const SizedBox(height: 16),
      if (away != null) _TeamLineupBlock(team: away, color: AppColors.error),
    ]);
  }
}

/// Terrain vu du dessus : l'équipe à domicile occupe la moitié haute (gardien
/// tout en haut), l'équipe visiteuse la moitié basse en miroir.
class _PitchView extends StatelessWidget {
  final TeamLineup? home;
  final TeamLineup? away;
  const _PitchView({this.home, this.away});

  static const _grass     = Color(0xFF14532D);
  static const _grassAlt  = Color(0xFF166534);
  static const _lineColor = Color(0x59FFFFFF);

  /// Regroupe les titulaires par ligne (1 = gardien) en respectant l'ordre de
  /// colonne renvoyé par l'API.
  static List<List<LineupPlayer>> _rows(TeamLineup t) {
    final byRow = <int, List<LineupPlayer>>{};
    for (final p in t.startXI) {
      final r = p.gridRow;
      if (r != null) (byRow[r] ??= []).add(p);
    }
    final keys = byRow.keys.toList()..sort();
    return [
      for (final k in keys)
        byRow[k]!..sort((a, b) => (a.gridCol ?? 0).compareTo(b.gridCol ?? 0)),
    ];
  }

  @override
  Widget build(BuildContext context) => AspectRatio(
    // Assez haut pour qu'un 4-2-3-1 (5 lignes par moitié) garde des photos
    // lisibles sans que _HalfPitch ait à les rétrécir.
    aspectRatio: 0.62,
    child: Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_grass, _grassAlt, _grass],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Stack(children: [
        Positioned.fill(child: CustomPaint(painter: _PitchLinesPainter())),
        Column(children: [
          Expanded(
            child: home == null
              ? const SizedBox.shrink()
              : _HalfPitch(rows: _rows(home!), color: AppColors.success),
          ),
          Expanded(
            child: away == null
              ? const SizedBox.shrink()
              // Miroir complet : lignes inversées (le gardien visiteur passe en
              // bas) et colonnes inversées, pour que les deux équipes se fassent
              // face comme sur un vrai terrain.
              : _HalfPitch(
                  rows: [
                    for (final r in _rows(away!).reversed) r.reversed.toList(),
                  ],
                  color: AppColors.error),
          ),
        ]),
      ]),
    ),
  );
}

class _HalfPitch extends StatelessWidget {
  final List<List<LineupPlayer>> rows;
  final Color color;
  const _HalfPitch({required this.rows, required this.color});

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();

    // Le nombre de lignes dépend de la formation (4 pour un 4-4-2, 5 pour un
    // 4-2-3-1…) : on répartit d'abord la hauteur disponible, puis on en déduit
    // la taille des photos. Avec une taille fixe, les formations les plus
    // profondes débordaient du terrain.
    return LayoutBuilder(builder: (context, constraints) {
      final rowHeight = constraints.maxHeight / rows.length;
      // ~20px sont pris par le nom sous la photo et l'espacement.
      final avatar = (rowHeight - 20).clamp(18.0, 34.0);

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(children: [
          for (final row in rows)
            SizedBox(
              height: rowHeight,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final p in row)
                    _PitchPlayer(player: p, color: color, size: avatar),
                ],
              ),
            ),
        ]),
      );
    });
  }
}

class _PitchPlayer extends StatelessWidget {
  final LineupPlayer player;
  final Color color;
  final double size;
  const _PitchPlayer({required this.player, required this.color, required this.size});

  @override
  Widget build(BuildContext context) => Flexible(
    // Dernier filet : si la ligne est vraiment trop basse (petit écran, 5
    // lignes), l'ensemble photo+nom est réduit au lieu de déborder.
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Stack(clipBehavior: Clip.none, children: [
          Container(
            width: size, height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black26,
              border: Border.all(color: color, width: 1.5),
            ),
            child: ClipOval(
              child: player.photoUrl == null
                ? Icon(Icons.person_rounded, color: Colors.white70, size: size * 0.55)
                : Image.network(
                    player.photoUrl!,
                    fit: BoxFit.cover,
                    // Le CDN peut renvoyer un 404 pour un joueur sans photo :
                    // on retombe sur l'icône générique plutôt que sur une erreur.
                    errorBuilder: (_, e, s) =>
                      Icon(Icons.person_rounded, color: Colors.white70, size: size * 0.55),
                  ),
            ),
          ),
          if (player.number != null)
            Positioned(
              bottom: -3, right: -3,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('${player.number}',
                  style: const TextStyle(
                    color: Colors.white, fontSize: 8.5, fontWeight: FontWeight.w900)),
              ),
            ),
        ]),
        const SizedBox(height: 4),
        Text(player.shortName,
          maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white, fontSize: 8.5, fontWeight: FontWeight.w600,
            shadows: [Shadow(color: Colors.black87, blurRadius: 3)])),
      ]),
    ),
  );
}

/// Lignes du terrain (touches, rond central, surfaces) tracées par-dessus la
/// pelouse — purement décoratif, aucune donnée.
class _PitchLinesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _PitchView._lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    final r = Rect.fromLTWH(6, 6, size.width - 12, size.height - 12);
    canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(8)), paint);

    // Ligne médiane + rond central
    canvas.drawLine(
      Offset(r.left, size.height / 2), Offset(r.right, size.height / 2), paint);
    canvas.drawCircle(Offset(size.width / 2, size.height / 2), size.width * 0.13, paint);

    // Surfaces de réparation, haut et bas
    final boxW = size.width * 0.46, boxH = size.height * 0.13;
    for (final top in [r.top, r.bottom - boxH]) {
      canvas.drawRect(
        Rect.fromLTWH((size.width - boxW) / 2, top, boxW, boxH), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Formation + entraîneur, sous le terrain.
class _TeamCoachRow extends StatelessWidget {
  final TeamLineup team;
  final Color color;
  const _TeamCoachRow({required this.team, required this.color});

  @override
  Widget build(BuildContext context) => Row(children: [
    if (team.formation != null) ...[
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6)),
        child: Text(team.formation!,
          style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800)),
      ),
      const SizedBox(width: 8),
    ],
    if (team.coach != null)
      Expanded(
        child: Text('Entraîneur : ${team.coach}',
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(color: context.cl.textM, fontSize: 11))),
  ]);
}

/// Repli quand l'API ne fournit pas les coordonnées `grid` : liste en pastilles.
class _TeamLineupBlock extends StatelessWidget {
  final TeamLineup team;
  final Color color;
  const _TeamLineupBlock({required this.team, required this.color});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _TeamCoachRow(team: team, color: color),
      const SizedBox(height: 8),
      Wrap(
        spacing: 6, runSpacing: 6,
        children: team.startXI.map((p) => _PlayerChip(player: p, color: color)).toList(),
      ),
    ],
  );
}

class _PlayerChip extends StatelessWidget {
  final LineupPlayer player;
  final Color color;
  const _PlayerChip({required this.player, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: context.cl.surfaceD,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: context.cl.border, width: 0.5)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      if (player.number != null) ...[
        Text('${player.number}',
          style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800)),
        const SizedBox(width: 4),
      ],
      Text(player.name,
        style: TextStyle(color: context.cl.textS, fontSize: 11)),
    ]),
  );
}

// ─── BLESSURES / SUSPENSIONS ────────────────────────────────────────────────────

class _InjuriesCard extends ConsumerWidget {
  final String matchId;
  final String homeTeam;
  final String awayTeam;
  final String? homeLogo;
  final String? awayLogo;
  const _InjuriesCard({
    required this.matchId,
    this.homeTeam = '',
    this.awayTeam = '',
    this.homeLogo,
    this.awayLogo,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final injuriesAsync = ref.watch(injuriesProvider(matchId));
    final status = _statusOf(injuriesAsync.error);

    // Vraie erreur, ou pas de blessés → pas de carte (rien à signaler)
    if (injuriesAsync.hasError && status != 401) return const SizedBox.shrink();
    if (status == null && injuriesAsync.valueOrNull?.isEmpty == true) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cl.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.cl.borderSoft, width: 0.8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.medical_services_rounded, color: AppColors.warning, size: 16),
          ),
          const SizedBox(width: 10),
          Text('Absences',
            style: TextStyle(
              color: context.cl.textP,
              fontSize: 13,
              fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 12),
        status == 401
          ? const _CardLoginPrompt(message: 'Connecte-toi pour voir les absences.')
          : injuriesAsync.when(
              loading: () => _H2HLoading(),
              error: (_, __) => const SizedBox.shrink(),
              data: (list) {
                final home = list.where((p) => p.isHome).toList();
                final away = list.where((p) => !p.isHome).toList();
                return Column(children: [
                  if (home.isNotEmpty)
                    _InjuryTeamBlock(
                      team: homeTeam, logo: homeLogo,
                      players: home, color: AppColors.success),
                  if (home.isNotEmpty && away.isNotEmpty) const SizedBox(height: 18),
                  if (away.isNotEmpty)
                    _InjuryTeamBlock(
                      team: awayTeam, logo: awayLogo,
                      players: away, color: AppColors.error),
                ]);
              },
            ),
      ]),
    );
  }
}

/// Absences d'une équipe, regroupées sous son nom et son logo — plus lisible
/// que l'ancienne liste à plat où chaque ligne portait une pastille DOM/EXT.
class _InjuryTeamBlock extends StatelessWidget {
  final String team;
  final String? logo;
  final List<InjuredPlayer> players;
  final Color color;
  const _InjuryTeamBlock({
    required this.team,
    required this.players,
    required this.color,
    this.logo,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(children: [
        _TeamLogo(url: logo ?? '', size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(team.isEmpty ? 'Équipe' : team,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color, fontSize: 12, fontWeight: FontWeight.w700))),
        Text('${players.length}',
          style: TextStyle(
            color: context.cl.textM, fontSize: 11, fontWeight: FontWeight.w700)),
      ]),
      const SizedBox(height: 10),
      ...players.map((p) => _InjuryRow(player: p)),
    ],
  );
}

class _InjuryRow extends StatelessWidget {
  final InjuredPlayer player;
  const _InjuryRow({required this.player});

  /// API-Football renvoie les motifs en anglais et en vrac. On traduit les
  /// valeurs courantes ; tout motif inconnu est affiché tel quel plutôt que
  /// masqué, pour ne pas perdre d'information.
  static const _reasons = {
    'yellow cards':    'Suspendu (cartons jaunes)',
    'yellow card':     'Suspendu (carton jaune)',
    'red card':        'Suspendu (carton rouge)',
    'suspended':       'Suspendu',
    'inactive':        'Indisponible',
    'injury':          'Blessé',
    'knee injury':     'Blessure au genou',
    'ankle injury':    'Blessure à la cheville',
    'thigh injury':    'Blessure à la cuisse',
    'hamstring':       'Ischio-jambiers',
    'muscle injury':   'Blessure musculaire',
    'calf injury':     'Blessure au mollet',
    'groin injury':    'Blessure à l\'aine',
    'back injury':     'Blessure au dos',
    'shoulder injury': 'Blessure à l\'épaule',
    'foot injury':     'Blessure au pied',
    'illness':         'Maladie',
    'personal reasons':'Raisons personnelles',
    'national team':   'Sélection nationale',
    'coach decision':  'Choix de l\'entraîneur',
    'rest':            'Au repos',
    'broken leg':      'Jambe cassée',
  };

  /// true pour une suspension (carton), false pour une indisponibilité
  /// physique — l'icône change en conséquence.
  bool get _isSuspension {
    final r = player.reason.toLowerCase();
    return r.contains('card') || r.contains('suspend');
  }

  String get _label {
    final raw = player.reason.trim().isNotEmpty ? player.reason.trim() : player.type;
    return _reasons[raw.toLowerCase()] ?? raw;
  }

  @override
  Widget build(BuildContext context) {
    final isRed = player.reason.toLowerCase().contains('red');
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(children: [
        SizedBox(
          width: 18,
          child: Center(
            child: _isSuspension
              ? Container(
                  width: 10, height: 13,
                  decoration: BoxDecoration(
                    color: isRed ? AppColors.error : AppColors.warning,
                    borderRadius: BorderRadius.circular(2)),
                )
              : Icon(Icons.healing_rounded, color: context.cl.textM, size: 14),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(player.name,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(color: context.cl.textP, fontSize: 12.5))),
        const SizedBox(width: 10),
        Flexible(
          child: Text(_label,
            textAlign: TextAlign.right,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(color: context.cl.textM, fontSize: 11)),
        ),
      ]),
    );
  }
}

// ─── CLASSEMENT ──────────────────────────────────────────────────────────────

class _StandingsCard extends ConsumerWidget {
  final String matchId;
  const _StandingsCard({required this.matchId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final standingsAsync = ref.watch(standingsProvider(matchId));
    final status = _statusOf(standingsAsync.error);

    // Bloqué sur le plan gratuit (ou match sans classement, ex. amical) → rien
    if (standingsAsync.hasError && status != 401) return const SizedBox.shrink();
    if (status == null && standingsAsync.valueOrNull?.isEmpty == true) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cl.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.cl.borderSoft, width: 0.8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: AppColors.info.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.leaderboard_rounded, color: AppColors.info, size: 16),
          ),
          const SizedBox(width: 10),
          Text('Classement',
            style: TextStyle(
              color: context.cl.textP,
              fontSize: 13,
              fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 12),
        status == 401
          ? const _CardLoginPrompt(message: 'Connecte-toi pour voir le classement.')
          : standingsAsync.when(
              loading: () => _H2HLoading(),
              error: (_, __) => const SizedBox.shrink(),
              data: (rows) => _StandingsTable(rows: rows),
            ),
      ]),
    );
  }
}

class _StandingsTable extends StatelessWidget {
  final List<StandingRow> rows;
  const _StandingsTable({required this.rows});

  @override
  Widget build(BuildContext context) => Column(children: [
    Row(children: [
      const SizedBox(width: 22),
      Expanded(child: Text('Équipe',
        style: TextStyle(color: context.cl.textM, fontSize: 10, fontWeight: FontWeight.w600))),
      _StandingsHeaderCell('J'),
      _StandingsHeaderCell('V'),
      _StandingsHeaderCell('N'),
      _StandingsHeaderCell('D'),
      _StandingsHeaderCell('+/-'),
      _StandingsHeaderCell('Pts'),
    ]),
    const SizedBox(height: 6),
    Divider(height: 1, color: context.cl.border),
    const SizedBox(height: 4),
    ...rows.map((r) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        SizedBox(width: 22, child: Text('${r.rank}',
          style: TextStyle(color: context.cl.textM, fontSize: 11, fontWeight: FontWeight.w700))),
        Expanded(child: Text(r.teamName,
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(color: context.cl.textS, fontSize: 11.5))),
        _StandingsCell('${r.played}'),
        _StandingsCell('${r.win}'),
        _StandingsCell('${r.draw}'),
        _StandingsCell('${r.lose}'),
        _StandingsCell(r.goalsDiff > 0 ? '+${r.goalsDiff}' : '${r.goalsDiff}'),
        SizedBox(width: 28, child: Text('${r.points}', textAlign: TextAlign.center,
          style: TextStyle(color: context.cl.textP, fontSize: 11.5, fontWeight: FontWeight.w800))),
      ]),
    )),
  ]);
}

class _StandingsHeaderCell extends StatelessWidget {
  final String label;
  const _StandingsHeaderCell(this.label);
  @override
  Widget build(BuildContext context) => SizedBox(width: 24,
    child: Text(label, textAlign: TextAlign.center,
      style: TextStyle(color: context.cl.textM, fontSize: 10, fontWeight: FontWeight.w600)));
}

class _StandingsCell extends StatelessWidget {
  final String value;
  const _StandingsCell(this.value);
  @override
  Widget build(BuildContext context) => SizedBox(width: 24,
    child: Text(value, textAlign: TextAlign.center,
      style: TextStyle(color: context.cl.textS, fontSize: 11)));
}

// ─── H2H ─────────────────────────────────────────────────────────────────────

class _H2HCard extends ConsumerWidget {
  final String matchId;
  /// Logos du match courant — les confrontations passées opposent les mêmes
  /// deux équipes, on les réutilise donc pour illustrer chaque ligne.
  final String? homeLogo;
  final String? awayLogo;
  const _H2HCard({required this.matchId, this.homeLogo, this.awayLogo});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final h2hAsync = ref.watch(h2hProvider(matchId));
    final status = _statusOf(h2hAsync.error);

    // Pas de données, ou vraie erreur → on n'affiche rien
    if (status == null && h2hAsync.valueOrNull?.matches.isEmpty == true) return const SizedBox.shrink();
    if (h2hAsync.hasError && status != 401) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cl.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.cl.borderSoft, width: 0.8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.history_rounded, color: AppColors.primary, size: 16),
          ),
          const SizedBox(width: 10),
          Text('Confrontations directes',
            style: TextStyle(
              color: context.cl.textP,
              fontSize: 13,
              fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 14),
        status == 401
          ? const _CardLoginPrompt(message: 'Connecte-toi pour voir les confrontations directes.')
          : h2hAsync.when(
              loading: () => _H2HLoading(),
              error: (_, __) => const SizedBox.shrink(),
              data: (h2h) => _H2HContent(
                h2h: h2h, homeLogo: homeLogo, awayLogo: awayLogo),
            ),
      ]),
    );
  }
}

class _H2HContent extends StatelessWidget {
  final H2HData h2h;
  final String? homeLogo;
  final String? awayLogo;
  const _H2HContent({required this.h2h, this.homeLogo, this.awayLogo});

  @override
  Widget build(BuildContext context) {
    final total = h2h.homeWins + h2h.awayWins + h2h.draws;
    final homeRatio = total > 0 ? h2h.homeWins / total : 0.0;
    final drawRatio = total > 0 ? h2h.draws     / total : 0.0;
    final awayRatio = total > 0 ? h2h.awayWins  / total : 0.0;

    return Column(children: [
      // Barre de résumé
      Row(children: [
        // Home wins
        Expanded(
          child: Column(children: [
            TweenAnimationBuilder<int>(
              tween: IntTween(begin: 0, end: h2h.homeWins),
              duration: const Duration(milliseconds: 800),
              builder: (_, v, __) => Text('$v',
                style: TextStyle(
                  color: AppColors.success,
                  fontSize: 24, fontWeight: FontWeight.w900)),
            ),
            Text(h2h.homeTeam,
              textAlign: TextAlign.center,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: context.cl.textS, fontSize: 10)),
          ]),
        ),
        // Draws
        Column(children: [
          TweenAnimationBuilder<int>(
            tween: IntTween(begin: 0, end: h2h.draws),
            duration: const Duration(milliseconds: 800),
            builder: (_, v, __) => Text('$v',
              style: TextStyle(
                color: context.cl.textM,
                fontSize: 24, fontWeight: FontWeight.w900)),
          ),
          Text('Nuls',
            style: TextStyle(color: context.cl.textM, fontSize: 10)),
        ]),
        // Away wins
        Expanded(
          child: Column(children: [
            TweenAnimationBuilder<int>(
              tween: IntTween(begin: 0, end: h2h.awayWins),
              duration: const Duration(milliseconds: 800),
              builder: (_, v, __) => Text('$v',
                style: TextStyle(
                  color: AppColors.error,
                  fontSize: 24, fontWeight: FontWeight.w900)),
            ),
            Text(h2h.awayTeam,
              textAlign: TextAlign.center,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: context.cl.textS, fontSize: 10)),
          ]),
        ),
      ]),
      const SizedBox(height: 12),
      // Barre proportionnelle
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 900),
          curve: Curves.easeOutCubic,
          builder: (_, t, __) => Row(children: [
            if (homeRatio > 0) Expanded(
              flex: (homeRatio * 100).round(),
              child: Container(
                height: 8,
                color: AppColors.success.withValues(alpha: 0.7 + 0.3 * t)),
            ),
            if (drawRatio > 0) Expanded(
              flex: (drawRatio * 100).round(),
              child: Container(height: 8, color: context.cl.borderSoft),
            ),
            if (awayRatio > 0) Expanded(
              flex: (awayRatio * 100).round(),
              child: Container(
                height: 8,
                color: AppColors.error.withValues(alpha: 0.7 + 0.3 * t)),
            ),
          ]),
        ),
      ),
      const SizedBox(height: 6),
      // Liste des derniers matchs
      ...() {
        final shown = h2h.matches.take(6).toList();
        return [
          for (var i = 0; i < shown.length; i++)
            _H2HRow(
              match: shown[i],
              h2h: h2h,
              homeLogo: homeLogo,
              awayLogo: awayLogo,
              showDivider: i < shown.length - 1,
            ),
        ];
      }(),
    ]);
  }
}

class _H2HRow extends StatelessWidget {
  final H2HMatchResult match;
  final H2HData        h2h;
  final String? homeLogo;
  final String? awayLogo;
  final bool showDivider;
  const _H2HRow({
    required this.match,
    required this.h2h,
    this.homeLogo,
    this.awayLogo,
    this.showDivider = true,
  });

  /// L'hôte change d'une confrontation à l'autre : on rattache le logo au nom
  /// de l'équipe, jamais à sa position dans la ligne.
  String? _logoFor(String team) => team == h2h.homeTeam ? homeLogo : awayLogo;

  /// Le vainqueur est déduit du score de la ligne, et non du champ `winner` de
  /// l'API : celui-ci est exprimé par rapport au domicile du *match courant*
  /// (cf. api_football.service.ts), donc le lire comme l'hôte de cette
  /// rencontre-là inverse la couleur dès que l'hôte a changé.
  ///
  /// La couleur suit ensuite l'équipe (vert = équipe à domicile du match
  /// courant, rouge = son adversaire), pour rester cohérente avec la barre de
  /// synthèse au-dessus quel que soit le terrain de la rencontre.
  Color? _colorFor(String team) {
    if (match.homeScore == match.awayScore) return null;
    final winner = match.homeScore > match.awayScore
      ? match.homeTeam
      : match.awayTeam;
    if (team != winner) return null;
    return team == h2h.homeTeam ? AppColors.success : AppColors.error;
  }

  Widget _teamSide(BuildContext context, String team, {required bool alignEnd}) {
    final color = _colorFor(team);
    final logo  = _TeamLogo(url: _logoFor(team) ?? '', size: 18);
    final name  = Flexible(
      child: Text(team,
        textAlign: alignEnd ? TextAlign.right : TextAlign.left,
        maxLines: 1, overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color ?? context.cl.textS,
          fontSize: 12,
          fontWeight: color != null ? FontWeight.w700 : FontWeight.w400)),
    );

    return Expanded(
      child: Row(
        mainAxisAlignment: alignEnd ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: alignEnd
          ? [name, const SizedBox(width: 7), logo]
          : [logo, const SizedBox(width: 7), name],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Column(children: [
    Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Column(children: [
        Row(children: [
          Text(DateFormat('EEE d MMM y', 'fr_FR').format(match.date),
            style: TextStyle(color: context.cl.textM, fontSize: 10.5)),
          const Spacer(),
          if (match.league.isNotEmpty)
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: context.cl.surfaceDeep,
                  borderRadius: BorderRadius.circular(5)),
                child: Text(match.league.toUpperCase(),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.cl.textM,
                    fontSize: 8.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4)),
              ),
            ),
        ]),
        const SizedBox(height: 9),
        Row(children: [
          _teamSide(context, match.homeTeam, alignEnd: true),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text('${match.homeScore} - ${match.awayScore}',
              style: TextStyle(
                color: context.cl.textP,
                fontSize: 14, fontWeight: FontWeight.w800)),
          ),
          _teamSide(context, match.awayTeam, alignEnd: false),
        ]),
      ]),
    ),
    if (showDivider) Container(height: 1, color: context.cl.borderSoft),
  ]);
}

class _H2HLoading extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Column(
    children: List.generate(3, (_) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        height: 24,
        decoration: BoxDecoration(
          color: context.cl.surfaceD,
          borderRadius: BorderRadius.circular(6)),
      ).animate(onPlay: (c) => c.repeat())
       .shimmer(duration: 1400.ms, color: context.cl.borderSoft),
    )),
  );
}

// ─── ANALYSE IA ──────────────────────────────────────────────────────────────

class _AIAnalysisCard extends ConsumerWidget {
  final String matchId;
  final MatchStatus status;
  const _AIAnalysisCard({required this.matchId, this.status = MatchStatus.upcoming});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aiAsync = ref.watch(aiAnalysisProvider(matchId));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF6C3AE8).withValues(alpha: 0.08),
            const Color(0xFF3A7BD5).withValues(alpha: 0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF6C3AE8).withValues(alpha: 0.25),
          width: 1,
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: const Color(0xFF6C3AE8).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.query_stats_rounded,
              color: Color(0xFF6C3AE8), size: 16),
          ),
          const SizedBox(width: 10),
          Text('Analyse statistique',
            style: TextStyle(
              color: context.cl.textP,
              fontSize: 14,
              fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 16),
        aiAsync.when(
          loading: () => _AILoadingState(),
          error: (err, __) {
            final isPremiumRequired = err is DioException &&
                (err.response?.statusCode == 403 ||
                 err.response?.data?['code'] == 'PREMIUM_REQUIRED');
            if (isPremiumRequired) {
              return _AIPremiumLockedState(
                status: status,
                onTap: () => goToPremium(context, ref));
            }
            return _AIErrorState(
              onRetry: () => ref.invalidate(aiAnalysisProvider(matchId)));
          },
          data: (ai) => _AIData(analysis: ai),
        ),
      ]),
    );
  }
}

class _AIData extends StatelessWidget {
  final AiAnalysis analysis;
  const _AIData({required this.analysis});

  Color get _probColor {
    if (analysis.probability >= 70) return AppColors.success;
    if (analysis.probability >= 55) return const Color(0xFF84CC16);
    if (analysis.probability >= 45) return AppColors.warning;
    return AppColors.error;
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('PROBABILITÉ DE SUCCÈS',
              style: TextStyle(
                color: context.cl.textM,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6)),
            const SizedBox(height: 8),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: analysis.probability / 100),
              duration: const Duration(milliseconds: 1200),
              curve: Curves.easeOutCubic,
              builder: (ctx, val, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: val,
                      minHeight: 8,
                      backgroundColor: ctx.cl.borderSoft,
                      valueColor: AlwaysStoppedAnimation<Color>(_probColor),
                    ),
                  ),
                ],
              ),
            ),
          ]),
        ),
        const SizedBox(width: 16),
        TweenAnimationBuilder<int>(
          tween: IntTween(begin: 0, end: analysis.probability),
          duration: const Duration(milliseconds: 1200),
          curve: Curves.easeOutCubic,
          builder: (_, val, __) => Text('$val%',
            style: TextStyle(
              color: _probColor,
              fontSize: 28,
              fontWeight: FontWeight.w900,
            )),
        ),
      ]),
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.cl.surfaceD,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('✦ ', style: TextStyle(color: Color(0xFF6C3AE8), fontSize: 12)),
          Expanded(
            child: Text(analysis.explanation,
              style: TextStyle(
                color: context.cl.textS,
                fontSize: 12,
                height: 1.5,
              )),
          ),
        ]),
      ),
    ],
  );
}

class _AILoadingState extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(children: [
        SizedBox(
          width: 16, height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: const Color(0xFF6C3AE8),
          ),
        ),
        const SizedBox(width: 10),
        Text('Analyse en cours…',
          style: TextStyle(color: context.cl.textM, fontSize: 12)),
      ]),
      const SizedBox(height: 12),
      Container(
        height: 8,
        decoration: BoxDecoration(
          color: context.cl.borderSoft,
          borderRadius: BorderRadius.circular(6)),
      )
        .animate(onPlay: (c) => c.repeat())
        .shimmer(duration: 1500.ms, color: const Color(0xFF6C3AE8).withValues(alpha: 0.15)),
    ],
  );
}

class _AIPremiumLockedState extends StatefulWidget {
  final VoidCallback onTap;
  final MatchStatus status;
  const _AIPremiumLockedState({required this.onTap, required this.status});

  @override
  State<_AIPremiumLockedState> createState() => _AIPremiumLockedStateState();
}

class _AIPremiumLockedStateState extends State<_AIPremiumLockedState>
    with SingleTickerProviderStateMixin {
  static const _gold = Color(0xFFDAA520);
  static const _goldLight = Color(0xFFF4C430);

  /// Sur un match terminé, promettre une « probabilité de succès » n'a plus
  /// de valeur : le score est connu. On vend alors le débriefing — ce que
  /// le modèle avait anticipé — qui reste le meilleur moyen de juger sa fiabilité
  /// avant de s'abonner.
  bool get _isFinished => widget.status == MatchStatus.finished;

  String get _title => _isFinished
    ? 'Débriefing du modèle'
    : 'Débloquez l\'analyse complète';

  String get _subtitle => _isFinished
    ? 'Ce que le modèle avait anticipé, et sur quels critères'
    : 'Probabilité de succès calculée à partir des cotes et de la forme';

  late final AnimationController _pressCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 85),
    reverseDuration: const Duration(milliseconds: 150),
  );
  late final Animation<double> _scale = Tween(begin: 1.0, end: 0.97).animate(
    CurvedAnimation(parent: _pressCtrl, curve: Curves.easeOut));

  @override
  void dispose() { _pressCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTapDown: (_) => _pressCtrl.forward(),
    onTapUp: (_) {
      _pressCtrl.reverse();
      HapticFeedback.lightImpact();
      widget.onTap();
    },
    onTapCancel: () => _pressCtrl.reverse(),
    child: ScaleTransition(
      scale: _scale,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(children: [
          // Aperçu flouté qui imite une vraie analyse — montre qu'il y a du
          // contenu réel derrière le voile, plutôt qu'une simple phrase.
          Positioned.fill(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
              child: const Opacity(opacity: 0.55, child: _AIPreviewMock()),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    context.cl.surfaceD.withValues(alpha: 0.55),
                    context.cl.surfaceD.withValues(alpha: 0.93),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 40, height: 40,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(colors: [_goldLight, _gold]),
                ),
                child: const Icon(Icons.query_stats_rounded, color: Colors.black, size: 19),
              ),
              const SizedBox(height: 10),
              Text(_title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: context.cl.textP,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(_subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(color: context.cl.textS, fontSize: 11, height: 1.4)),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [_goldLight, _gold]),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [BoxShadow(
                    color: _gold.withValues(alpha: 0.35),
                    blurRadius: 14, offset: const Offset(0, 4))],
                ),
                // Le bouton doré reste identique d'un verrou à l'autre — c'est
                // devenu le signal « action Premium ». Seul le libellé change,
                // pour éviter deux CTA rigoureusement identiques à la suite.
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.lock_open_rounded, color: Colors.black, size: 15),
                  const SizedBox(width: 6),
                  Text(_isFinished ? 'Voir le débriefing' : 'Débloquer l\'analyse',
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 12,
                      fontWeight: FontWeight.w800)),
                ]),
              ).animate(onPlay: (c) => c.repeat())
               .shimmer(duration: 2200.ms, delay: 700.ms, color: Colors.white70),
            ]),
          ),
        ]),
      ),
    ),
  );
}

/// Squelette imitant la mise en page de [_AIData], flouté et assombri
/// derrière le CTA — donne un aperçu crédible du contenu sans afficher
/// de vrais chiffres.
class _AIPreviewMock extends StatelessWidget {
  const _AIPreviewMock();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: 0.72,
              minHeight: 8,
              backgroundColor: context.cl.borderSoft,
              valueColor: const AlwaysStoppedAnimation(AppColors.success),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Container(
          width: 34, height: 22,
          decoration: BoxDecoration(
            color: context.cl.borderSoft,
            borderRadius: BorderRadius.circular(5)),
        ),
      ]),
      const SizedBox(height: 16),
      _line(context, 1),
      const SizedBox(height: 7),
      _line(context, 0.85),
      const SizedBox(height: 7),
      _line(context, 0.5),
    ]),
  );

  Widget _line(BuildContext context, double widthFactor) => FractionallySizedBox(
    widthFactor: widthFactor,
    alignment: Alignment.centerLeft,
    child: Container(
      height: 10,
      decoration: BoxDecoration(
        color: context.cl.borderSoft,
        borderRadius: BorderRadius.circular(4)),
    ),
  );
}

class _AIErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  const _AIErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(Icons.warning_amber_rounded, color: context.cl.textM, size: 16),
    const SizedBox(width: 8),
    Expanded(
      child: Text('Analyse temporairement indisponible.',
        style: TextStyle(color: context.cl.textM, fontSize: 12))),
    TextButton(
      onPressed: onRetry,
      style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero),
      child: Text('Réessayer',
        style: TextStyle(color: const Color(0xFF6C3AE8), fontSize: 12))),
  ]);
}

// ─── FORME DES ÉQUIPES ───────────────────────────────────────────────────────

/// Forme récente des deux équipes. Les points de forme n'ont pas de maximum
/// fixe côté backend — ils ne sont exploités qu'en rapport de l'un à l'autre
/// (cf. `formToProb` dans ai_prediction.service.ts) — d'où une barre
/// comparative plutôt que deux jauges sur une échelle absolue.
class _FormCard extends StatelessWidget {
  final MatchEntity match;
  const _FormCard({required this.match});

  @override
  Widget build(BuildContext context) {
    final total = match.homeFormPoints + match.awayFormPoints;
    final homeRatio = total > 0 ? match.homeFormPoints / total : 0.5;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cl.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.cl.borderSoft, width: 0.8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _CardHeader(
          icon: Icons.trending_up_rounded,
          color: AppColors.success,
          title: 'Forme des équipes'),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: Text(match.homeTeam,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.success, fontSize: 11.5,
                fontWeight: FontWeight.w700))),
          const SizedBox(width: 12),
          Expanded(
            child: Text(match.awayTeam,
              textAlign: TextAlign.right,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.error, fontSize: 11.5,
                fontWeight: FontWeight.w700))),
        ]),
        const SizedBox(height: 9),
        Row(children: [
          Text('${match.homeFormPoints} pts',
            style: TextStyle(
              color: context.cl.textP, fontSize: 13, fontWeight: FontWeight.w800)),
          const Spacer(),
          Text('${match.awayFormPoints} pts',
            style: TextStyle(
              color: context.cl.textP, fontSize: 13, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 8),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.5, end: homeRatio),
          duration: const Duration(milliseconds: 800),
          curve: Curves.easeOutCubic,
          builder: (context, val, child) => ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: SizedBox(
              height: 8,
              child: Row(children: [
                Expanded(
                  flex: (val * 1000).round().clamp(1, 999),
                  child: Container(color: AppColors.success)),
                Expanded(
                  flex: ((1 - val) * 1000).round().clamp(1, 999),
                  child: Container(color: AppColors.error)),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _MiserButton extends ConsumerStatefulWidget {
  final MatchEntity match;
  const _MiserButton({required this.match});

  @override
  ConsumerState<_MiserButton> createState() => _MiserButtonState();
}

class _MatchStatsCard extends ConsumerWidget {
  final String matchId;
  const _MatchStatsCard({required this.matchId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(matchStatsProvider(matchId));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cl.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.cl.borderSoft, width: 0.8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: AppColors.info.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.bar_chart_rounded, color: AppColors.info, size: 16),
          ),
          const SizedBox(width: 10),
          Text('Statistiques du match',
            style: TextStyle(
              color: context.cl.textP,
              fontSize: 13,
              fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 14),
        statsAsync.when(
          loading: () => _StatsLoading(),
          error: (_, __) => _StatsUnavailable(),
          data: (data) => data == null
            ? _StatsUnavailable()
            : _StatsList(stats: data.stats,
                homeTeam: data.homeTeam, awayTeam: data.awayTeam),
        ),
      ]),
    );
  }
}

/// Faits marquants du match (buts, cartons) — affichés dans l'onglet Détails,
/// séparément des statistiques chiffrées qui ont leur propre onglet.
/// Masquée quand il n'y a aucun événement notable à montrer.
class _MatchEventsCard extends ConsumerWidget {
  final String matchId;
  final MatchEntity match;
  const _MatchEventsCard({required this.matchId, required this.match});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(matchStatsProvider(matchId));
    final data = statsAsync.valueOrNull;
    if (data == null || !_EventsList.hasNotable(data.events)) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cl.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.cl.borderSoft, width: 0.8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _CardHeader(
          icon: Icons.timeline_rounded,
          color: AppColors.info,
          title: 'Faits marquants'),
        const SizedBox(height: 14),
        // En-tête et filet reprennent exactement la structure d'une ligne
        // d'événement (colonne minute + 2 colonnes + colonne icône) : leur
        // alignement est ainsi garanti par construction plutôt que par un
        // calcul de marges qui dériverait au moindre changement.
        Row(children: [
          const SizedBox(width: _EventsList.minuteWidth),
          Expanded(
            child: Center(child: _TeamLogo(url: match.homeTeamLogo ?? '', size: 20))),
          const SizedBox(width: _EventsList.iconWidth),
          Expanded(
            child: Center(child: _TeamLogo(url: match.awayTeamLogo ?? '', size: 20))),
        ]),
        const SizedBox(height: 12),
        Stack(children: [
          Positioned.fill(
            child: Row(children: [
              const SizedBox(width: _EventsList.minuteWidth),
              const Expanded(child: SizedBox()),
              SizedBox(
                width: _EventsList.iconWidth,
                child: Center(
                  child: Container(width: 1, color: context.cl.borderSoft))),
              const Expanded(child: SizedBox()),
            ]),
          ),
          _EventsList(events: data.events,
            homeTeam: data.homeTeam, awayTeam: data.awayTeam),
        ]),
      ]),
    );
  }
}

/// En-tête commun à toutes les cartes d'information : même taille d'icône,
/// même typographie. Évite que chaque carte dérive de son côté.
class _CardHeader extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  const _CardHeader({required this.icon, required this.color, required this.title});

  @override
  Widget build(BuildContext context) => Row(children: [
    Container(
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: color, size: 16),
    ),
    const SizedBox(width: 10),
    Expanded(
      child: Text(title,
        maxLines: 1, overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: context.cl.textP,
          fontSize: 13.5,
          fontWeight: FontWeight.w700)),
    ),
  ]);
}

class _EventsList extends StatelessWidget {
  final List<MatchEvent> events;
  final String homeTeam, awayTeam;
  const _EventsList({required this.events, required this.homeTeam, required this.awayTeam});

  /// Géométrie de la ligne, partagée avec l'en-tête et le filet central de
  /// [_MatchEventsCard] : l'axe des deux camps est décalé par la colonne des
  /// minutes, le centrer « au milieu de la carte » le désaligne.
  static const double minuteWidth = 38;
  static const double iconWidth   = 24;

  /// Seuls les buts et les cartons sont affichés — les remplacements et autres
  /// événements alourdiraient la liste sans intérêt.
  static bool _isNotable(MatchEvent e) => e.type == 'Goal' || e.type == 'Card';

  /// Permet au parent de décider s'il doit afficher la carte, en appliquant
  /// exactement le même filtre que le rendu.
  static bool hasNotable(List<MatchEvent> events) => events.any(_isNotable);

  static Widget _eventIcon(MatchEvent e) {
    if (e.type == 'Goal') {
      if (e.detail == 'Own Goal') {
        return Stack(clipBehavior: Clip.none, children: [
          Icon(Icons.sports_soccer_rounded, color: AppColors.error, size: 16),
          Positioned(right: -4, bottom: -2,
            child: Icon(Icons.arrow_back_rounded, color: AppColors.error, size: 8)),
        ]);
      }
      if (e.detail == 'Penalty') {
        return Stack(clipBehavior: Clip.none, children: [
          Icon(Icons.sports_soccer_rounded, color: AppColors.success, size: 16),
          Positioned(right: -4, bottom: -2,
            child: Icon(Icons.gps_fixed_rounded, color: AppColors.warning, size: 8)),
        ]);
      }
      if (e.detail == 'Missed Penalty') {
        return Icon(Icons.sports_soccer_rounded,
          color: AppColors.error.withValues(alpha: 0.5), size: 16);
      }
      return Icon(Icons.sports_soccer_rounded, color: AppColors.success, size: 16);
    }
    if (e.type == 'Card') {
      final isRed = e.detail.contains('Red');
      return Container(
        width: 11, height: 15,
        decoration: BoxDecoration(
          color: isRed ? AppColors.error : AppColors.warning,
          borderRadius: BorderRadius.circular(2),
        ),
      );
    }
    if (e.type == 'subst') {
      return Icon(Icons.swap_horiz_rounded, color: AppColors.info, size: 16);
    }
    return const Icon(Icons.sports_soccer_rounded, color: Colors.grey, size: 16);
  }

  @override
  Widget build(BuildContext context) {
    final notable = events.where(_isNotable).toList();

    if (notable.isEmpty) {
      return Text('Aucun événement notable.',
        style: TextStyle(color: context.cl.textM, fontSize: 12));
    }

    return Column(
      children: notable.map((e) {
        final isHome = e.team == homeTeam;
        final minStr = e.extra != null ? "${e.minute}+${e.extra}'" : "${e.minute}'";

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            // Minute
            SizedBox(width: minuteWidth,
              child: Text(minStr,
                style: TextStyle(
                  color: AppColors.info, fontSize: 11,
                  fontWeight: FontWeight.w700))),
            // Gauche (domicile)
            Expanded(child: isHome
              ? _EventItem(event: e, align: TextAlign.right)
              : const SizedBox()),
            // Icône centrale — largeur fixe : les icônes n'ont pas toutes la
            // même taille (16px pour un but, 11px pour un carton) et sans
            // colonne fixe l'axe central se déplaçait d'une ligne à l'autre.
            SizedBox(
              width: iconWidth,
              child: Center(child: _eventIcon(e)),
            ),
            // Droite (extérieur)
            Expanded(child: !isHome
              ? _EventItem(event: e, align: TextAlign.left)
              : const SizedBox()),
          ]),
        );
      }).toList(),
    );
  }
}

class _EventItem extends StatelessWidget {
  final MatchEvent event;
  final TextAlign align;
  const _EventItem({required this.event, required this.align});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: align == TextAlign.right
      ? CrossAxisAlignment.end : CrossAxisAlignment.start,
    children: [
      Text(event.player,
        textAlign: align,
        style: TextStyle(color: context.cl.textP, fontSize: 12,
          fontWeight: FontWeight.w600),
        maxLines: 1, overflow: TextOverflow.ellipsis),
      if (event.assist != null && event.assist!.isNotEmpty)
        Text('↳ ${event.assist}',
          textAlign: align,
          style: TextStyle(color: context.cl.textM, fontSize: 10),
          maxLines: 1, overflow: TextOverflow.ellipsis),
    ],
  );
}

class _StatsList extends StatelessWidget {
  final List<MatchStat> stats;
  final String homeTeam, awayTeam;
  const _StatsList({required this.stats, required this.homeTeam, required this.awayTeam});

  static const _wantedStats = [
    'Ball Possession',
    'Total Shots',
    'Shots on Goal',
    'Shots off Goal',
    'Blocked Shots',
    'Corner Kicks',
    'Fouls',
    'Yellow Cards',
    'Red Cards',
    'Offsides',
    'Total passes',
    'Passes accurate',
    'Goalkeeper Saves',
  ];

  static const _frenchLabels = {
    'Ball Possession':   'Possession',
    'Total Shots':       'Tirs (total)',
    'Shots on Goal':     'Tirs cadrés',
    'Shots off Goal':    'Tirs hors cadre',
    'Blocked Shots':     'Tirs bloqués',
    'Corner Kicks':      'Corners',
    'Fouls':             'Fautes',
    'Yellow Cards':      'Cartons jaunes',
    'Red Cards':         'Cartons rouges',
    'Offsides':          'Hors-jeu',
    'Total passes':      'Passes (total)',
    'Passes accurate':   'Passes réussies',
    'Goalkeeper Saves':  'Arrêts du gardien',
  };

  @override
  Widget build(BuildContext context) {
    final filtered = stats
      .where((s) => _wantedStats.contains(s.label))
      .toList()
      ..sort((a, b) =>
        _wantedStats.indexOf(a.label).compareTo(_wantedStats.indexOf(b.label)));

    if (filtered.isEmpty) {
      return Text('Statistiques indisponibles.',
        style: TextStyle(color: context.cl.textM, fontSize: 12));
    }

    // La possession sert d'en-tête visuel : c'est la seule stat qui se lit
    // naturellement comme un partage à 100 %, les autres sont des compteurs.
    final possession = filtered
      .where((s) => s.label == 'Ball Possession').firstOrNull;
    final others = filtered.where((s) => s.label != 'Ball Possession');

    return Column(children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(children: [
          Expanded(child: Text(homeTeam,
            style: TextStyle(color: AppColors.primary, fontSize: 11,
              fontWeight: FontWeight.w700),
            maxLines: 1, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 12),
          Expanded(child: Text(awayTeam,
            style: TextStyle(color: AppColors.warning, fontSize: 11,
              fontWeight: FontWeight.w700),
            textAlign: TextAlign.right,
            maxLines: 1, overflow: TextOverflow.ellipsis)),
        ]),
      ),
      if (possession != null) ...[
        Text('Possession de balle',
          style: TextStyle(color: context.cl.textS, fontSize: 11.5)),
        const SizedBox(height: 8),
        _PossessionBar(home: possession.home, away: possession.away),
        const SizedBox(height: 14),
      ],
      ...others.map((s) => _StatRow(
        label: _frenchLabels[s.label] ?? s.label,
        home: s.home, away: s.away,
        lowerIsBetter: _lowerIsBetter.contains(s.label),
      )),
    ]);
  }

  /// Stats où le plus petit chiffre est le meilleur — la pastille doit alors
  /// mettre en avant l'équipe qui en a le moins.
  static const _lowerIsBetter = {
    'Fouls', 'Yellow Cards', 'Red Cards', 'Offsides',
  };
}

/// Barre de possession pleine largeur, chaque camp portant son pourcentage.
class _PossessionBar extends StatelessWidget {
  final dynamic home, away;
  const _PossessionBar({this.home, this.away});

  @override
  Widget build(BuildContext context) {
    final h = _statValue(home), a = _statValue(away);
    final total = h + a;
    final hRatio = total > 0 ? h / total : 0.5;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.5, end: hRatio),
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeOutCubic,
      builder: (context, val, child) => ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          height: 30,
          child: Row(children: [
            Expanded(
              flex: (val * 1000).round().clamp(1, 999),
              child: Container(
                color: AppColors.primary,
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('${home ?? 0}',
                    style: const TextStyle(
                      color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800)),
                ),
              ),
            ),
            Expanded(
              flex: ((1 - val) * 1000).round().clamp(1, 999),
              child: Container(
                color: AppColors.warning,
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('${away ?? 0}',
                    style: const TextStyle(
                      color: Colors.black, fontSize: 13, fontWeight: FontWeight.w800)),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Une ligne « valeur — libellé — valeur ». Seule l'équipe en tête reçoit une
/// pastille colorée : le regard trouve le vainqueur de la stat sans avoir à
/// comparer deux nombres.
class _StatRow extends StatelessWidget {
  final String label;
  final dynamic home, away;
  final bool lowerIsBetter;
  const _StatRow({
    required this.label,
    this.home,
    this.away,
    this.lowerIsBetter = false,
  });

  @override
  Widget build(BuildContext context) {
    final h = _statValue(home), a = _statValue(away);
    final homeLeads = h != a && (lowerIsBetter ? h < a : h > a);
    final awayLeads = h != a && (lowerIsBetter ? a < h : a > h);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        SizedBox(
          width: 54,
          child: Align(
            alignment: Alignment.centerLeft,
            child: _value(context, home, AppColors.primary, homeLeads, Colors.white),
          ),
        ),
        Expanded(
          child: Text(label,
            textAlign: TextAlign.center,
            style: TextStyle(color: context.cl.textS, fontSize: 11.5, height: 1.3)),
        ),
        SizedBox(
          width: 54,
          child: Align(
            alignment: Alignment.centerRight,
            child: _value(context, away, AppColors.warning, awayLeads, Colors.black),
          ),
        ),
      ]),
    );
  }

  Widget _value(BuildContext context, dynamic v, Color color, bool leads, Color onColor) {
    final text = Text('${v ?? 0}',
      style: TextStyle(
        color: leads ? onColor : context.cl.textP,
        fontSize: 12.5,
        fontWeight: FontWeight.w700));

    if (!leads) return text;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(11)),
      child: text,
    );
  }
}

/// Les valeurs d'API-Football arrivent en `int`, ou en `String` pour les
/// pourcentages ("76%"), ou `null` quand la stat n'est pas fournie.
double _statValue(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString().replaceAll('%', '').trim()) ?? 0;
}

class _StatsLoading extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Column(
    children: List.generate(4, (_) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        height: 20,
        decoration: BoxDecoration(
          color: context.cl.surfaceD,
          borderRadius: BorderRadius.circular(6)),
      ).animate(onPlay: (c) => c.repeat())
       .shimmer(duration: 1400.ms, color: context.cl.borderSoft),
    )),
  );
}

class _StatsUnavailable extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      Icon(Icons.info_outline_rounded, color: context.cl.textM, size: 15),
      const SizedBox(width: 8),
      Expanded(child: Text(
        'Statistiques indisponibles pour ce match.',
        style: TextStyle(color: context.cl.textM, fontSize: 12))),
    ]),
  );
}

// ─────────────────────────────────────────────────────────────────────────────

class _MiserButtonState extends ConsumerState<_MiserButton> {
  bool _betPlaced = false;

  @override
  Widget build(BuildContext context) {
    final alreadyBet = ref.watch(hasBetOnPronosticProvider(widget.match.id));

    if (_betPlaced || alreadyBet) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color:  AppColors.success.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.success.withValues(alpha: 0.3))),
        child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.check_circle_rounded, color: AppColors.success, size: 18),
          SizedBox(width: 8),
          Text('Mise enregistrée dans ton bankroll',
              style: TextStyle(color: AppColors.success,
                  fontSize: 13, fontWeight: FontWeight.w600)),
        ]),
      );
    }

    return GestureDetector(
      onTap: () async {
        HapticFeedback.lightImpact();
        // Miser suppose une bankroll, donc un compte. Sans cette garde, un
        // invité ouvrait la feuille qui échouait en 401 sur un message
        // générique — le dialogue ne diagnostique que le 404 « pas de
        // bankroll configurée ».
        if (!ref.read(effectiveLoggedInProvider)) {
          context.push(
            '/auth/email?from=${Uri.encodeComponent('/pronostics/${widget.match.id}')}');
          return;
        }
        final ok = await showMiserDialog(
          context,
          ref:              ref,
          pronosticId:      widget.match.id,
          homeTeam:         widget.match.homeTeam,
          awayTeam:         widget.match.awayTeam,
          predictionLabel:  widget.match.displayPredictionLabel,
          confidenceScore:  widget.match.confidenceScore,
          oddsRecommended:  widget.match.oddsRecommended,
        );
        if (ok) setState(() => _betPlaced = true);
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.success, Color(0xFF059669)],
            begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(
            color: AppColors.success.withValues(alpha: 0.35),
            blurRadius: 14, offset: const Offset(0, 5))]),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.savings_rounded, color: Colors.white, size: 20),
          const SizedBox(width: 10),
          const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Valider ma mise',
                style: TextStyle(color: Colors.white,
                    fontSize: 15, fontWeight: FontWeight.w700)),
            Text('Ajouter à mon bankroll',
                style: TextStyle(color: Colors.white70, fontSize: 11)),
          ]),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20)),
            child: const Text('→', style: TextStyle(
                color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
          ),
        ]),
      ),
    );
  }
}

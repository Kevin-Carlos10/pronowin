import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pronowin/core/widgets/in_app_browser_page.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/team_logo_widget.dart';
import '../../../../features/auth/presentation/providers/auth_provider.dart';
import '../../../../features/abonnement/presentation/providers/subscription_provider.dart';
import '../../../../shared/utils/premium_nav.dart';
import '../../../../features/notifications/presentation/providers/notification_service.dart';
import '../../../../core/network/connectivity_provider.dart';
import '../providers/accueil_provider.dart';
import '../providers/streak_provider.dart';
import '../../../bankroll/presentation/providers/bankroll_provider.dart';

class AccueilPage extends ConsumerStatefulWidget {
  const AccueilPage({super.key});

  @override
  ConsumerState<AccueilPage> createState() => _AccueilPageState();
}

class _AccueilPageState extends ConsumerState<AccueilPage> {
  Timer? _liveTimer;
  String? _selectedLeague; // null = tous

  @override
  void initState() {
    super.initState();
    _liveTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      final pronostics = ref.read(pronosticsJourProvider).valueOrNull;
      final hasLive = pronostics?.any(
        (p) => (p as Map<String, dynamic>)['status'] == 'live',
      ) ?? false;
      if (hasLive) ref.invalidate(pronosticsJourProvider);
    });
  }

  @override
  void dispose() {
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
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 110),
              sliver: SliverList(
                delegate: SliverChildListDelegate([

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

                  // ─── BANKROLL MINI-WIDGET ─────────────────────────────────
                  const _BankrollMiniWidget()
                    .animate()
                    .fadeIn(duration: 400.ms, delay: 80.ms)
                    .slideY(begin: 0.08, end: 0, duration: 350.ms,
                        curve: Curves.easeOutCubic),

                  // ─── STREAK BANNER ────────────────────────────────────────
                  const _StreakBanner()
                    .animate()
                    .fadeIn(duration: 400.ms, delay: 120.ms)
                    .slideY(begin: 0.08, end: 0, duration: 350.ms,
                        curve: Curves.easeOutCubic),

                  // ─── STATS RAPIDES ────────────────────────────────────────
                  _QuickStats(isPremium: isPremium)
                    .animate()
                    .fadeIn(duration: 400.ms, delay: 100.ms)
                    .slideY(begin: 0.1, end: 0, duration: 400.ms,
                        curve: Curves.easeOutCubic),
                  const SizedBox(height: 20),

                  // ─── BANNIÈRE PREMIUM ─────────────────────────────────────
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
                          title: '🔴 En direct',
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
                            if (status == 'live') return true;
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
                      if (isLocked) return const SizedBox.shrink();
                      return Column(children: [
                        const _SectionHeader(title: 'Top prono du jour'),
                        const SizedBox(height: 12),
                        _HeroPronoCard(prono: top, onTap: () =>
                            context.push('/pronostics/${top['id']}', extra: null)),
                        const SizedBox(height: 24),
                      ]);
                    },
                  ),

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

                      final allSorted = _sorted(list);

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
                              onSelect: (l) => setState(() =>
                                  _selectedLeague = (_selectedLeague == l) ? null : l),
                            ),
                          const SizedBox(height: 12),

                          // ── Liste triée ────────────────────────────────────
                          ...filtered.asMap().entries.map((e) {
                            final p = e.value;
                            return _PronosticCard(
                              prono: p,
                              isPremium: isPremium,
                              onTap: () => context.push(
                                  '/pronostics/${p['id']}', extra: null),
                            )
                            .animate(delay: Duration(milliseconds: e.key * 60))
                            .fadeIn(duration: 300.ms)
                            .slideY(begin: 0.06, end: 0,
                                duration: 280.ms, curve: Curves.easeOutCubic);
                          }),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 28),

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
class _SliverHeader extends ConsumerWidget {
  final dynamic user;
  final bool isPremium;
  const _SliverHeader({required this.user, required this.isPremium});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now         = DateTime.now();
    final unreadCount = ref.watch(unreadCountProvider);
    final greeting = now.hour < 12
        ? 'Bonjour'
        : now.hour < 18
            ? 'Bon après-midi'
            : 'Bonsoir';

    return SliverAppBar(
      expandedHeight: 150,
      floating: true,
      pinned: false,
      snap: true,
      elevation: 0,
      backgroundColor: context.cl.bg,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [context.cl.bg, context.cl.surfaceD],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          padding: const EdgeInsets.fromLTRB(16, 48, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // ── Ligne 1 : Logo PronoWin + cloche (style FotMob) ──────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  RichText(
                    text: const TextSpan(
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                      ),
                      children: [
                        TextSpan(text: 'Prono', style: TextStyle(color: Colors.white)),
                        TextSpan(text: 'Win',   style: TextStyle(color: AppColors.primary)),
                      ],
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: () => context.push('/notifications'),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              width: 38, height: 38,
                              decoration: BoxDecoration(
                                color: context.cl.surface,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: context.cl.border, width: 0.5),
                              ),
                              child: Icon(Icons.notifications_rounded,
                                  color: context.cl.textS, size: 20),
                            ),
                            if (unreadCount > 0)
                              Positioned(
                                top: -4, right: -4,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: AppColors.error,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: context.cl.bg, width: 1.5),
                                  ),
                                  child: Text(
                                    unreadCount > 9 ? '9+' : '$unreadCount',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 8,
                                        fontWeight: FontWeight.w800),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        DateFormat('dd MMM', 'fr_FR').format(now),
                        style: TextStyle(color: context.cl.textM, fontSize: 9),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 10),

              // ── Ligne 2 : Avatar + salutation ────────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: () => context.push('/compte'),
                    child: Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppColors.primary, AppColors.primaryLight],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: const [
                          BoxShadow(color: Color(0x59E8541A), blurRadius: 8, offset: Offset(0, 3)),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: (user?.avatarUrl != null && (user!.avatarUrl as String).isNotEmpty)
                            ? Image.network(
                                user!.avatarUrl as String,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => _AvatarInitials(user: user),
                              )
                            : _AvatarInitials(user: user),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '$greeting, ${user?.displayName ?? 'Parieur'} 👋',
                          style: TextStyle(
                            color: context.cl.textP,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        if (isPremium)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [
                                Color(0xFFB8860B),
                                Color(0xFFFFD700),
                              ]),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.workspace_premium_rounded,
                                    color: Colors.white, size: 10),
                                SizedBox(width: 3),
                                Text('PREMIUM',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.5)),
                              ],
                            ),
                          )
                        else
                          GestureDetector(
                            onTap: () => context.go('/abonnement'),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('Plan Gratuit · ',
                                    style: TextStyle(color: context.cl.textM, fontSize: 11)),
                                const Text('Passer Premium ✨',
                                    style: TextStyle(
                                        color: AppColors.primaryLight,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),

            ],
          ),
        ),
      ),
    );
  }
}

// ─── Avatar initiales ─────────────────────────────────────────────────────────
class _AvatarInitials extends StatelessWidget {
  final dynamic user;
  const _AvatarInitials({required this.user});
  @override
  Widget build(BuildContext context) => Center(
    child: Text(
      user?.pseudo?.isNotEmpty == true ? (user!.pseudo as String)[0].toUpperCase() : 'P',
      style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
    ),
  );
}

// ══════════════════════════════════════════════════════════════════════════════'
// STATS RAPIDES
// ══════════════════════════════════════════════════════════════════════════════'
class _QuickStats extends ConsumerWidget {
  final bool isPremium;
  const _QuickStats({required this.isPremium});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(statsJourProvider);

    return statsAsync.when(
      loading: () => Row(children: [
        _StatChipSkeleton(), const SizedBox(width: 10),
        _StatChipSkeleton(), const SizedBox(width: 10),
        _StatChipSkeleton(),
      ]),
      error: (_, _) => const SizedBox.shrink(),
      data: (stats) {
        final winRate      = stats['winRate']      as int? ?? 0;
        final streak       = stats['streak']       as int? ?? 0;
        final upcoming     = stats['upcoming']     as int? ?? 0;
        final totalFinished = stats['totalFinished'] as int? ?? 0;

        return Row(children: [
          _StatChip(
            icon: Icons.local_fire_department_rounded,
            label: 'Série',
            value: streak > 0 ? '$streak 🔥' : '—',
            color: AppColors.warning,
            hint: streak == 0 ? 'Pas encore de série en cours' : null,
          ),
          const SizedBox(width: 10),
          _StatChip(
            icon: Icons.trending_up_rounded,
            label: 'Taux win',
            value: totalFinished >= 3 ? '$winRate%' : '—',
            color: AppColors.success,
            hint: totalFinished < 3 ? 'Disponible après 3 pronos terminés' : null,
          ),
          const SizedBox(width: 10),
          _StatChip(
            icon: Icons.sports_soccer_rounded,
            label: 'À venir',
            value: upcoming > 0 ? '$upcoming' : '—',
            color: AppColors.info,
            hint: upcoming == 0 ? 'Aucun match programmé' : null,
          ),
        ]);
      },
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  /// Message affiché en tooltip quand la valeur est indisponible (—)
  final String? hint;
  const _StatChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final isEmpty = value == '—';
    Widget chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: context.cl.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: (isEmpty ? context.cl.border : color).withValues(alpha: isEmpty ? 1.0 : 0.2),
            width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: isEmpty ? context.cl.textM : color, size: 16),
          const SizedBox(height: 6),
          Text(value,
              style: TextStyle(
                  color: isEmpty ? context.cl.textM : color,
                  fontSize: 13,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 1),
          Text(label,
              style: TextStyle(
                  color: context.cl.textM,
                  fontSize: 9,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );

    if (isEmpty && hint != null) {
      chip = Tooltip(
        message: hint!,
        triggerMode: TooltipTriggerMode.tap,
        preferBelow: true,
        decoration: BoxDecoration(
          color: context.cl.surfaceD,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: context.cl.border)),
        textStyle: TextStyle(color: context.cl.textM, fontSize: 11),
        child: chip,
      );
    }

    return Expanded(child: chip);
  }
}

class _StatChipSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      height: 72,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.cl.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.cl.border, width: 0.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 16, height: 16, decoration: BoxDecoration(
          color: context.cl.borderS, borderRadius: BorderRadius.circular(4))),
        const SizedBox(height: 6),
        Container(width: 36, height: 12, decoration: BoxDecoration(
          color: context.cl.borderS, borderRadius: BorderRadius.circular(4))),
        const SizedBox(height: 4),
        Container(width: 28, height: 8, decoration: BoxDecoration(
          color: context.cl.borderS, borderRadius: BorderRadius.circular(4))),
      ]),
    ).animate(onPlay: (c) => c.repeat(reverse: true))
      .shimmer(duration: 1000.ms, color: context.cl.border.withValues(alpha: 0.5)),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// BANNIÈRE PREMIUM
// ══════════════════════════════════════════════════════════════════════════════
class _PremiumBanner extends ConsumerWidget {
  final VoidCallback onTap;
  const _PremiumBanner({required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pronosAsync = ref.watch(pronosticsJourProvider);
    final statsAsync  = ref.watch(statsJourProvider);

    // Cherche un prono VIP du jour
    final vipProno = pronosAsync.whenOrNull(
      data: (list) {
        try {
          return list.firstWhere(
            (p) => (p as Map<String, dynamic>)['is_premium'] == true,
          ) as Map<String, dynamic>?;
        } catch (_) { return null; }
      },
    );

    // Taux de réussite pour le titre contextuel
    final winRate = statsAsync.whenOrNull(
      data: (s) => (s['winRate'] as num?)?.toDouble(),
    );

    final String headline = winRate != null && winRate >= 70
        ? '${winRate.toStringAsFixed(0)}% de réussite cette semaine'
        : vipProno != null
            ? 'Accède au pronostic VIP du jour'
            : 'Analyses IA · Cotes exclusives · VIP';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1C2545), Color(0xFF0D1530)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.45), width: 1),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.14),
              blurRadius: 20, offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Corps: preview VIP ou illustration ─────────────────────────
              if (vipProno != null)
                _LockedPronoPreview(prono: vipProno)
              else
                const _PremiumIllustration(),

              // ── Pied: headline + CTA ────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFD700).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: const Text('PREMIUM',
                                style: TextStyle(
                                  color: Color(0xFFFFD700),
                                  fontSize: 9, fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5)),
                            ),
                          ]),
                          const SizedBox(height: 5),
                          Text(headline,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 13, fontWeight: FontWeight.w700,
                              height: 1.3)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 10),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                            colors: [AppColors.primary, AppColors.primaryLight]),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.45),
                            blurRadius: 10, offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Text('Débloquer',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LockedPronoPreview extends StatelessWidget {
  final Map<String, dynamic> prono;
  const _LockedPronoPreview({required this.prono});

  @override
  Widget build(BuildContext context) {
    final homeTeam     = prono['home_team'] as String? ?? '';
    final awayTeam     = prono['away_team'] as String? ?? '';
    final homeLogoUrl  = prono['home_team_logo'] as String?;
    final awayLogoUrl  = prono['away_team_logo'] as String?;
    final predLabel    = prono['prediction_label'] as String? ?? '???';
    final oddsRec      = (prono['odds_recommended'] as num?)?.toDouble();

    return Stack(
      children: [
        // Fond match
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(child: Column(children: [
                TeamLogoWidget(url: homeLogoUrl, size: 40),
                const SizedBox(height: 6),
                Text(homeTeam,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 11, fontWeight: FontWeight.w700),
                  textAlign: TextAlign.center,
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              ])),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Column(children: [
                  const Text('VS',
                    style: TextStyle(
                      color: AppColors.textMuted, fontSize: 16,
                      fontWeight: FontWeight.w900, letterSpacing: 2)),
                  const SizedBox(height: 4),
                  if (oddsRec != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6)),
                      child: Text('x${oddsRec.toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: AppColors.success,
                          fontSize: 11, fontWeight: FontWeight.w800)),
                    ),
                ]),
              ),
              Expanded(child: Column(children: [
                TeamLogoWidget(url: awayLogoUrl, size: 40),
                const SizedBox(height: 6),
                Text(awayTeam,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 11, fontWeight: FontWeight.w700),
                  textAlign: TextAlign.center,
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              ])),
            ],
          ),
        ),

        // Pronostic flouté (BackdropFilter)
        Positioned(
          left: 16, right: 16, bottom: 6,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.25),
                      width: 0.5),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.lock_rounded,
                        color: AppColors.primary, size: 13),
                    const SizedBox(width: 6),
                    Text(predLabel,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13, fontWeight: FontWeight.w800),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PremiumIllustration extends StatelessWidget {
  const _PremiumIllustration();

  @override
  Widget build(BuildContext context) {
    const tiles = [
      (Icons.psychology_rounded,     'Analyses IA',       Color(0xFF8B5CF6)),
      (Icons.show_chart_rounded,     'Cotes exclusives',  Color(0xFF10B981)),
      (Icons.workspace_premium_rounded, 'Pronos VIP',     Color(0xFFFFD700)),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
      child: Row(
        children: tiles.map((t) {
          final (icon, label, color) = t;
          return Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: color.withValues(alpha: 0.2), width: 0.5),
              ),
              child: Column(children: [
                Icon(icon, color: color, size: 22),
                const SizedBox(height: 6),
                Text(label,
                  style: TextStyle(
                    color: color,
                    fontSize: 9, fontWeight: FontWeight.w700),
                  textAlign: TextAlign.center),
              ]),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════'
// CARROUSEL LIVE
// ══════════════════════════════════════════════════════════════════════════════'
class _LiveMatchesCarousel extends StatelessWidget {
  final List<dynamic> matches;
  final bool isPremium;
  const _LiveMatchesCarousel({required this.matches, required this.isPremium});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: matches.map((m) {
        final match    = m as Map<String, dynamic>;
        final isLocked = (match['is_premium'] as bool? ?? false) && !isPremium;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _LiveMatchCard(match: match, isLocked: isLocked),
        );
      }).toList(),
    );
  }
}

class _LiveMatchCard extends StatefulWidget {
  final Map<String, dynamic> match;
  final bool isLocked;
  const _LiveMatchCard({required this.match, required this.isLocked});

  @override
  State<_LiveMatchCard> createState() => _LiveMatchCardState();
}

class _LiveMatchCardState extends State<_LiveMatchCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.match;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1C0A0A), Color(0xFF2A0E0E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.45), width: 1),
        boxShadow: [
          BoxShadow(
            color: AppColors.error.withValues(alpha: 0.18),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [

          // ── Badge LIVE + compétition ──────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedBuilder(
                animation: _pulse,
                builder: (_, __) => Container(
                  width: 7, height: 7,
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.4 + 0.6 * _pulse.value),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              const SizedBox(width: 5),
              const Text('EN DIRECT',
                  style: TextStyle(
                      color: AppColors.error,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2)),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  m['league'] as String? ?? '',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 10),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // ── Score central ─────────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Équipe domicile
              Expanded(
                child: Column(
                  children: [
                    TeamLogoWidget(url: m['home_team_logo'] as String?, size: 44),
                    const SizedBox(height: 8),
                    Text(
                      m['home_team'] as String? ?? '',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              // Score
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Column(
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _ScoreBox(score: m['home_score'] ?? 0),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Text('-',
                              style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.5),
                                  fontSize: 22,
                                  fontWeight: FontWeight.w300)),
                        ),
                        _ScoreBox(score: m['away_score'] ?? 0),
                      ],
                    ),
                  ],
                ),
              ),

              // Équipe extérieure
              Expanded(
                child: Column(
                  children: [
                    TeamLogoWidget(url: m['away_team_logo'] as String?, size: 44),
                    const SizedBox(height: 8),
                    Text(
                      m['away_team'] as String? ?? '',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),

          // ── Pronostic (si débloqué) ───────────────────────────────────────
          if (!widget.isLocked && (m['prediction_label'] as String? ?? '').isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
              ),
              child: Text(
                'Prono : ${m['prediction_label']}',
                style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ScoreBox extends StatelessWidget {
  final dynamic score;
  const _ScoreBox({required this.score});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48, height: 48,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      alignment: Alignment.center,
      child: Text(
        '$score',
        style: const TextStyle(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.w900),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════'
// HERO PRONO CARD (Top prono du jour)
// ══════════════════════════════════════════════════════════════════════════════'
class _HeroPronoCard extends StatelessWidget {
  final Map<String, dynamic> prono;
  final VoidCallback onTap;
  const _HeroPronoCard({required this.prono, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final conf      = (prono['confidence_score'] as num?)?.toInt() ?? 0;
    final isLive    = (prono['status'] as String? ?? '') == 'live';
    final homeScore = prono['home_score'];
    final awayScore = prono['away_score'];
    final hasScore  = isLive && homeScore != null && awayScore != null;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isLive
                ? [const Color(0xFF2A0E0E), const Color(0xFF1C0A0A), const Color(0xFF0A0505)]
                : [const Color(0xFF1C2545), const Color(0xFF0F1A35), const Color(0xFF0A0E1A)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
              color: isLive
                  ? AppColors.error.withValues(alpha: 0.5)
                  : AppColors.primary.withValues(alpha: 0.4),
              width: 1),
          boxShadow: [
            BoxShadow(
              color: (isLive ? AppColors.error : AppColors.primary).withValues(alpha: 0.14),
              blurRadius: 24,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          children: [
            // Ligue + badge top / live
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: context.cl.surfaceD,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.sports_soccer_rounded,
                          color: AppColors.primaryLight, size: 11),
                      const SizedBox(width: 5),
                      Text(
                        prono['league'] as String? ?? '',
                        style: TextStyle(color: context.cl.textS, fontSize: 10),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                if (isLive)
                  _HeroLiveBadge()
                else
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                          colors: [Color(0xFFB8860B), Color(0xFFFFD700)]),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.star_rounded, color: Colors.white, size: 11),
                        SizedBox(width: 4),
                        Text('TOP DU JOUR',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5)),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 18),

            // Équipes + score central
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    children: [
                      _HeroTeamLogo(url: prono['home_team_logo'] as String? ?? ''),
                      const SizedBox(height: 8),
                      Text(
                        prono['home_team'] as String? ?? '',
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                // Centre : score si live, sinon VS + heure
                if (hasScore)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Column(children: [
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        _HeroScoreBox(score: homeScore),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          child: Text('-',
                              style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.4),
                                  fontSize: 20,
                                  fontWeight: FontWeight.w300)),
                        ),
                        _HeroScoreBox(score: awayScore),
                      ]),
                    ]),
                  )
                else
                  Column(
                    children: [
                      const Text('VS',
                          style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 2)),
                      const SizedBox(height: 6),
                      Text(
                        prono['match_date'] != null
                            ? DateFormat('HH:mm').format(
                                DateTime.tryParse(prono['match_date'] as String) ??
                                    DateTime.now())
                            : '--:--',
                        style: const TextStyle(
                            color: AppColors.primaryLight, fontSize: 12),
                      ),
                    ],
                  ),
                Expanded(
                  child: Column(
                    children: [
                      _HeroTeamLogo(url: prono['away_team_logo'] as String? ?? ''),
                      const SizedBox(height: 8),
                      Text(
                        prono['away_team'] as String? ?? '',
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // Pronostic + Cote + Confiance
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.25),
                    width: 0.5),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('PRONOSTIC',
                            style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8)),
                        const SizedBox(height: 4),
                        Text(
                          prono['prediction_label'] as String? ?? '',
                          style: const TextStyle(
                              color: AppColors.primary,
                              fontSize: 16,
                              fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    children: [
                      const Text('COTE',
                          style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8)),
                      const SizedBox(height: 4),
                      Text(
                        prono['odds_recommended']
                                ?.toStringAsFixed(2) ??
                            '',
                        style: const TextStyle(
                            color: AppColors.success,
                            fontSize: 22,
                            fontWeight: FontWeight.w900),
                      ),
                    ],
                  ),
                  const SizedBox(width: 16),
                  Column(
                    children: [
                      const Text('CONFIANCE',
                          style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5)),
                      const SizedBox(height: 6),
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: conf.toDouble()),
                        duration: const Duration(milliseconds: 700),
                        curve: Curves.easeOutBack,
                        builder: (_, val, _) => Row(
                          children: List.generate(5, (i) {
                            final fill = (val - i).clamp(0.0, 1.0);
                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 1),
                              child: Icon(
                                fill > 0.5
                                    ? Icons.star_rounded
                                    : Icons.star_outline_rounded,
                                color: fill > 0.5
                                    ? AppColors.warning.withValues(alpha: fill)
                                    : AppColors.borderSoft,
                                size: 16),
                            );
                          }),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroTeamLogo extends StatelessWidget {
  final String url;
  const _HeroTeamLogo({required this.url});
  @override
  Widget build(BuildContext context) =>
      TeamLogoWidget(url: url.isEmpty ? null : url, size: 52);
}

class _HeroScoreBox extends StatelessWidget {
  final dynamic score;
  const _HeroScoreBox({required this.score});
  @override
  Widget build(BuildContext context) => Container(
    width: 44, height: 44,
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppColors.error.withValues(alpha: 0.4)),
    ),
    alignment: Alignment.center,
    child: Text('$score',
        style: const TextStyle(
            color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
  );
}

class _HeroLiveBadge extends StatefulWidget {
  @override
  State<_HeroLiveBadge> createState() => _HeroLiveBadgeState();
}

class _HeroLiveBadgeState extends State<_HeroLiveBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() { _pulse.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: AppColors.error.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: AppColors.error.withValues(alpha: 0.5)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      AnimatedBuilder(
        animation: _pulse,
        builder: (_, __) => Container(
          width: 7, height: 7,
          decoration: BoxDecoration(
            color: AppColors.error.withValues(alpha: 0.4 + 0.6 * _pulse.value),
            shape: BoxShape.circle,
          ),
        ),
      ),
      const SizedBox(width: 5),
      const Text('EN DIRECT',
          style: TextStyle(
              color: AppColors.error,
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2)),
    ]),
  );
}

// ══════════════════════════════════════════════════════════════════════════════'
// CARTE PRONOSTIC
// ══════════════════════════════════════════════════════════════════════════════'
class _PronosticCard extends ConsumerWidget {
  final Map<String, dynamic> prono;
  final bool isPremium;
  final VoidCallback onTap;
  const _PronosticCard(
      {required this.prono, required this.isPremium, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLocked  = (prono['is_premium'] as bool? ?? false) && !isPremium;
    final conf      = (prono['confidence_score'] as num?)?.toInt() ?? 0;
    final status    = prono['status'] as String? ?? '';
    final isFinished = status == 'finished';
    final isLive     = status == 'live';
    final homeScore  = prono['home_score'];
    final awayScore  = prono['away_score'];
    final hasScore   = homeScore != null && awayScore != null;
    final result     = prono['result'] as String?; // 'WIN' | 'LOSS' | null
    final matchId    = prono['match_id'] as String? ?? '';
    final favorites  = ref.watch(favoritesProvider).valueOrNull ?? {};
    final isFav      = favorites.contains(matchId);

    // Couleur bordure selon résultat
    Color borderColor;
    if (isFinished && result == 'WIN') {
      borderColor = AppColors.success.withValues(alpha: 0.5);
    } else if (isFinished && result == 'LOSS') {
      borderColor = AppColors.error.withValues(alpha: 0.4);
    } else if (isLive) {
      borderColor = AppColors.error.withValues(alpha: 0.5);
    } else if (isLocked) {
      borderColor = context.cl.border;
    } else {
      borderColor = AppColors.primary.withValues(alpha: 0.2);
    }

    return GestureDetector(
      onTap: isLocked ? null : onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.cl.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: borderColor, width: 0.8),
        ),
        child: Column(
          children: [
            Row(
              children: [
                // Logo domicile
                _SmallTeamLogo(url: prono['home_team_logo'] as String? ?? ''),
                const SizedBox(width: 10),

                // Équipes + Ligue
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${prono['home_team']} vs ${prono['away_team']}',
                        style: TextStyle(
                            color: context.cl.textP,
                            fontSize: 12,
                            fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Text(prono['league'] as String? ?? '',
                              style: TextStyle(
                                  color: context.cl.textM, fontSize: 10)),
                          if (prono['match_date'] != null && !isFinished && !isLive) ...[
                            Text(' · ',
                                style: TextStyle(
                                    color: context.cl.textM, fontSize: 10)),
                            Text(
                              DateFormat('HH:mm').format(
                                  DateTime.tryParse(
                                          prono['match_date'] as String) ??
                                      DateTime.now()),
                              style: TextStyle(
                                  color: context.cl.textM, fontSize: 10),
                            ),
                          ],
                          if (isLive) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: AppColors.error.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text('LIVE',
                                  style: TextStyle(
                                      color: AppColors.error,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800)),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),

                // Droite : score OU prono
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Score final ou en cours
                    if (hasScore && (isFinished || isLive))
                      _InlineScore(
                        home: homeScore,
                        away: awayScore,
                        isLive: isLive,
                      )
                    else if (isLocked)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: context.cl.surfaceD,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.lock_rounded,
                                color: context.cl.textM, size: 11),
                            const SizedBox(width: 4),
                            Text('VIP',
                                style: TextStyle(
                                    color: context.cl.textM,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: AppColors.primary.withValues(alpha: 0.3),
                              width: 0.5),
                        ),
                        child: Text(
                          prono['prediction_label'] as String? ?? '',
                          style: const TextStyle(
                              color: AppColors.primary,
                              fontSize: 11,
                              fontWeight: FontWeight.w700),
                        ),
                      ),

                    const SizedBox(height: 5),

                    // Badge WIN/LOSS pour matchs terminés
                    if (isFinished && result != null)
                      _ResultBadge(result: result)
                    else if (!isLocked && !isFinished) ...[
                      _ConfidenceDots(conf: conf),
                      if ((prono['odds_recommended'] as num?) != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          (prono['odds_recommended'] as num).toStringAsFixed(2),
                          style: const TextStyle(
                              color: AppColors.success,
                              fontSize: 13,
                              fontWeight: FontWeight.w800),
                        ),
                      ],
                    ],
                  ],
                ),

                const SizedBox(width: 8),
                // Logo extérieur
                _SmallTeamLogo(url: prono['away_team_logo'] as String? ?? ''),

                // Bouton favori
                if (matchId.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      ref.read(favoritesProvider.notifier).toggle(matchId);
                    },
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      transitionBuilder: (child, anim) =>
                          ScaleTransition(scale: anim, child: child),
                      child: Icon(
                        isFav
                            ? Icons.bookmark_rounded
                            : Icons.bookmark_border_rounded,
                        key: ValueKey(isFav),
                        color: isFav ? AppColors.primary : context.cl.textM,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ],
            ),

            // Prono label sous le score (matchs terminés débloqués)
            if (isFinished && !isLocked && (prono['prediction_label'] as String? ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    const SizedBox(width: 38),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: result == 'WIN'
                            ? AppColors.success.withValues(alpha: 0.10)
                            : result == 'LOSS'
                                ? AppColors.error.withValues(alpha: 0.10)
                                : context.cl.surfaceD,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Prono : ${prono['prediction_label']}',
                        style: TextStyle(
                          color: result == 'WIN'
                              ? AppColors.success
                              : result == 'LOSS'
                                  ? AppColors.error
                                  : context.cl.textM,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // ── Countdown (< 2h avant le match) ──────────────────────────
            if (!isFinished && !isLive) ...[
              () {
                final date = DateTime.tryParse(prono['match_date'] as String? ?? '');
                if (date == null) return const SizedBox.shrink();
                final diff = date.difference(DateTime.now());
                if (diff.inMinutes > 0 && diff.inMinutes <= 120) {
                  return _MatchCountdownInline(kickoff: date);
                }
                return const SizedBox.shrink();
              }(),
            ],

            // ── Forme domicile/extérieur ──────────────────────────────────
            if (!isLocked) ...[
              () {
                final hp = prono['home_form_points'] as int? ?? 0;
                final ap = prono['away_form_points'] as int? ?? 0;
                if (hp == 0 && ap == 0) return const SizedBox.shrink();
                return _FormRow(
                  homeName: prono['home_team'] as String? ?? '',
                  awayName: prono['away_team'] as String? ?? '',
                  homePoints: hp,
                  awayPoints: ap,
                );
              }(),
            ],
          ],
        ),
      ),
    );
  }
}

class _InlineScore extends StatelessWidget {
  final dynamic home;
  final dynamic away;
  final bool isLive;
  const _InlineScore({required this.home, required this.away, this.isLive = false});

  @override
  Widget build(BuildContext context) {
    final color = isLive ? AppColors.error : context.cl.textP;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isLive
            ? AppColors.error.withValues(alpha: 0.12)
            : context.cl.surfaceD,
        borderRadius: BorderRadius.circular(8),
        border: isLive
            ? Border.all(color: AppColors.error.withValues(alpha: 0.4))
            : null,
      ),
      child: Text(
        '$home - $away',
        style: TextStyle(
            color: color,
            fontSize: 15,
            fontWeight: FontWeight.w900,
            letterSpacing: 1),
      ),
    );
  }
}

class _ResultBadge extends StatelessWidget {
  final String result;
  const _ResultBadge({required this.result});

  @override
  Widget build(BuildContext context) {
    final isWin = result == 'WIN';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isWin
            ? AppColors.success.withValues(alpha: 0.15)
            : AppColors.error.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isWin ? Icons.check_circle_rounded : Icons.cancel_rounded,
            color: isWin ? AppColors.success : AppColors.error,
            size: 11,
          ),
          const SizedBox(width: 3),
          Text(
            isWin ? 'Gagné' : 'Perdu',
            style: TextStyle(
              color: isWin ? AppColors.success : AppColors.error,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _SmallTeamLogo extends StatelessWidget {
  final String url;
  const _SmallTeamLogo({required this.url});
  @override
  Widget build(BuildContext context) =>
      TeamLogoWidget(url: url.isEmpty ? null : url, size: 28);
}

// ══════════════════════════════════════════════════════════════════════════════
// FILTRE PAR LIGUE
// ══════════════════════════════════════════════════════════════════════════════
class _LeagueFilterChips extends StatelessWidget {
  final List<String> leagues;
  final String? selected;
  final ValueChanged<String> onSelect;
  const _LeagueFilterChips({required this.leagues, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: leagues.map((l) {
          final isSelected = l == selected;
          return GestureDetector(
            onTap: () => onSelect(l),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primary
                    : context.cl.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected
                      ? AppColors.primary
                      : context.cl.border,
                  width: 0.8,
                ),
              ),
              child: Text(
                l,
                style: TextStyle(
                  color: isSelected ? Colors.white : context.cl.textM,
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// CONFIANCE — 5 DOTS COLORÉS + LABEL
// ══════════════════════════════════════════════════════════════════════════════
class _ConfidenceDots extends StatelessWidget {
  final int conf;
  const _ConfidenceDots({required this.conf});

  @override
  Widget build(BuildContext context) {
    final color = conf >= 4
        ? AppColors.success
        : conf >= 3
            ? AppColors.warning
            : AppColors.error;
    final label = conf >= 4 ? 'Excellent' : conf >= 3 ? 'Bon' : 'Faible';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(5, (i) => Container(
            width: 7, height: 7,
            margin: const EdgeInsets.only(left: 2),
            decoration: BoxDecoration(
              color: i < conf ? color : context.cl.borderS,
              borderRadius: BorderRadius.circular(2),
            ),
          )),
        ),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// COUNTDOWN INLINE (< 2h avant le match)
// ══════════════════════════════════════════════════════════════════════════════
class _MatchCountdownInline extends StatefulWidget {
  final DateTime kickoff;
  const _MatchCountdownInline({required this.kickoff});
  @override
  State<_MatchCountdownInline> createState() => _MatchCountdownInlineState();
}

class _MatchCountdownInlineState extends State<_MatchCountdownInline> {
  late Timer _t;
  Duration _remaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    _remaining = widget.kickoff.difference(DateTime.now());
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      final r = widget.kickoff.difference(DateTime.now());
      if (mounted) setState(() => _remaining = r.isNegative ? Duration.zero : r);
    });
  }

  @override
  void dispose() { _t.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    if (_remaining == Duration.zero) return const SizedBox.shrink();
    final h  = _remaining.inHours;
    final m  = _remaining.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s  = _remaining.inSeconds.remainder(60).toString().padLeft(2, '0');
    final timeStr = h > 0 ? '${h}h $m min' : '$m:$s';
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.timer_outlined, size: 13, color: AppColors.primary),
          const SizedBox(width: 5),
          Text('Coup d\'envoi dans ', style: TextStyle(color: context.cl.textM, fontSize: 11)),
          Text(timeStr, style: const TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// FORME V/N/D (calculée depuis les points sur 5 matchs)
// ══════════════════════════════════════════════════════════════════════════════
class _FormRow extends StatelessWidget {
  final String homeName;
  final String awayName;
  final int homePoints;
  final int awayPoints;
  const _FormRow({required this.homeName, required this.awayName,
      required this.homePoints, required this.awayPoints});

  // Reconstitue une série V/N/D approximative depuis les points (max 15 pts sur 5 matchs)
  List<String> _series(int pts) {
    final list = <String>[];
    var rem = pts;
    for (var i = 0; i < 5; i++) {
      if (rem >= 3) { list.add('V'); rem -= 3; }
      else if (rem >= 1) { list.add('N'); rem -= 1; }
      else { list.add('D'); }
    }
    return list;
  }

  Color _dotColor(String r) =>
    r == 'V' ? AppColors.success : r == 'N' ? AppColors.warning : AppColors.error;

  @override
  Widget build(BuildContext context) {
    final homeSeries = _series(homePoints);
    final awaySeries = _series(awayPoints);
    final total = homePoints + awayPoints;
    final homeAdv = total == 0 ? 0.5 : homePoints / total;

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: context.cl.surfaceD,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text(homeName.split(' ').first,
                  style: TextStyle(color: context.cl.textM, fontSize: 10, fontWeight: FontWeight.w600)),
              const SizedBox(width: 6),
              ...homeSeries.map((r) => Container(
                width: 14, height: 14,
                margin: const EdgeInsets.only(right: 2),
                decoration: BoxDecoration(
                  color: _dotColor(r).withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Center(child: Text(r,
                    style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w800))),
              )),
              const Spacer(),
              ...awaySeries.map((r) => Container(
                width: 14, height: 14,
                margin: const EdgeInsets.only(left: 2),
                decoration: BoxDecoration(
                  color: _dotColor(r).withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Center(child: Text(r,
                    style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w800))),
              )),
              const SizedBox(width: 6),
              Text(awayName.split(' ').first,
                  style: TextStyle(color: context.cl.textM, fontSize: 10, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              height: 4,
              child: Row(children: [
                Expanded(
                  flex: (homeAdv * 100).round(),
                  child: Container(color: AppColors.primary),
                ),
                Expanded(
                  flex: 100 - (homeAdv * 100).round(),
                  child: Container(color: context.cl.borderS),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 3),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Avantage domicile ${(homeAdv * 100).round()}%',
                  style: TextStyle(color: context.cl.textM, fontSize: 9)),
              Text('→ ${homeAdv >= 0.5 ? homeName.split(' ').first : awayName.split(' ').first}',
                  style: const TextStyle(color: AppColors.primary, fontSize: 9, fontWeight: FontWeight.w700)),
            ],
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// SECTION ACTUALITÉS — layout vertical
// ══════════════════════════════════════════════════════════════════════════════
class _NewsSection extends StatefulWidget {
  final List<Map<String, dynamic>> items;
  const _NewsSection({required this.items});
  @override
  State<_NewsSection> createState() => _NewsSectionState();
}

class _NewsSectionState extends State<_NewsSection> {
  Set<String> _readIds = {};
  bool _showAll = false;

  @override
  void initState() {
    super.initState();
    _loadRead();
  }

  Future<void> _loadRead() async {
    final prefs = await SharedPreferences.getInstance();
    final list  = prefs.getStringList('news_read_ids') ?? [];
    if (mounted) setState(() => _readIds = list.toSet());
  }

  Future<void> _markRead(String id) async {
    if (_readIds.contains(id)) return;
    final prefs = await SharedPreferences.getInstance();
    _readIds.add(id);
    await prefs.setStringList('news_read_ids', _readIds.toList());
    if (mounted) setState(() {});
  }

  void _openArticle(BuildContext context, Map<String, dynamic> news) {
    HapticFeedback.mediumImpact();
    _markRead(news['id'] as String? ?? '');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _NewsDetailSheet(news: news),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Pinned en premier, puis tri par date
    final sorted = [...widget.items]..sort((a, b) {
      final aPin = (a['is_pinned'] as bool? ?? false) ? 0 : 1;
      final bPin = (b['is_pinned'] as bool? ?? false) ? 0 : 1;
      if (aPin != bPin) return aPin.compareTo(bPin);
      final da = DateTime.tryParse(a['created_at'] as String? ?? '') ?? DateTime(2000);
      final db = DateTime.tryParse(b['created_at'] as String? ?? '') ?? DateTime(2000);
      return db.compareTo(da);
    });

    final unreadCount = sorted.where((n) => !_readIds.contains(n['id'] as String? ?? '')).length;
    final visible = _showAll ? sorted : sorted.take(4).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(children: [
              const Text('📰 Actualités football',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w800)),
              if (unreadCount > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(10)),
                  child: Text('$unreadCount',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w800)),
                ),
              ],
            ]),
            if (sorted.length > 4)
              GestureDetector(
                onTap: () => setState(() => _showAll = !_showAll),
                child: Text(
                  _showAll ? 'Réduire' : 'Voir tout',
                  style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
              ),
          ],
        ),
        const SizedBox(height: 12),

        // Featured card (premier article)
        if (visible.isNotEmpty)
          _FeaturedNewsCard(
            news: visible.first,
            isRead: _readIds.contains(visible.first['id'] as String? ?? ''),
            onTap: () => _openArticle(context, visible.first),
          ).animate().fadeIn(duration: 350.ms).slideY(begin: 0.06, end: 0,
              curve: Curves.easeOutCubic),

        // Cards compactes (articles suivants)
        ...visible.skip(1).toList().asMap().entries.map((e) {
          final i    = e.key;
          final news = e.value;
          return _CompactNewsCard(
            news: news,
            isRead: _readIds.contains(news['id'] as String? ?? ''),
            onTap: () => _openArticle(context, news),
          )
          .animate(delay: Duration(milliseconds: 80 + i * 60))
          .fadeIn(duration: 300.ms)
          .slideY(begin: 0.05, end: 0, curve: Curves.easeOutCubic);
        }),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// HELPERS COMMUNS NEWS
// ──────────────────────────────────────────────────────────────────────────────
Color _newsAccent(String? cat) {
  if (cat == null) return AppColors.primary;
  if (cat.contains('Monde'))      return const Color(0xFF10B981);
  if (cat.contains('Champions'))  return const Color(0xFFFFD700);
  if (cat.contains('Premier'))    return const Color(0xFF6366F1);
  if (cat.contains('Serie'))      return const Color(0xFF3B82F6);
  if (cat.contains('Liga'))       return AppColors.error;
  if (cat.contains('Ligue 1'))    return const Color(0xFF8B5CF6);
  return AppColors.primary;
}

// ──────────────────────────────────────────────────────────────────────────────
Map<String, String> _imgHeaders(String url) {
  if (url.contains('bfmtv.com') || url.contains('images.bfmtv')) {
    return {'Referer': 'https://rmcsport.bfmtv.com/'};
  }
  if (url.contains('bbci.co.uk') || url.contains('ichef.bbc')) {
    return {'Referer': 'https://www.bbc.com/'};
  }
  return {};
}

// FEATURED CARD — grande carte avec image pleine largeur
// ──────────────────────────────────────────────────────────────────────────────
class _FeaturedNewsCard extends StatelessWidget {
  final Map<String, dynamic> news;
  final bool isRead;
  final VoidCallback onTap;
  const _FeaturedNewsCard({required this.news, required this.isRead, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cat    = news['categorie'] as String?;
    final accent = _newsAccent(cat);
    final imgUrl = news['image_url'] as String?;
    final isPinned = news['is_pinned'] as bool? ?? false;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        height: 200,
        decoration: BoxDecoration(
          color: context.cl.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isRead ? context.cl.border : accent.withValues(alpha: 0.4),
            width: isRead ? 0.5 : 1.2,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(children: [
            // Image fond
            if (imgUrl != null && imgUrl.isNotEmpty)
              Positioned.fill(
                child: Image.network(imgUrl, fit: BoxFit.cover,
                  headers: _imgHeaders(imgUrl),
                  errorBuilder: (_, _, _) => Container(color: context.cl.surfaceD)),
              )
            else
              Positioned.fill(child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [accent.withValues(alpha: 0.15), context.cl.surfaceD],
                    begin: Alignment.topLeft, end: Alignment.bottomRight)),
              )),

            // Dégradé bas
            Positioned.fill(child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.black.withValues(alpha: 0.75),
                    Colors.black.withValues(alpha: 0.1),
                  ],
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                )),
            )),

            // Barre accent gauche
            Positioned(left: 0, top: 0, bottom: 0,
              child: Container(width: 3, color: accent)),

            // Contenu
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top : catégorie + badges
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(6)),
                      child: Text(cat ?? '',
                        style: const TextStyle(
                          color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)),
                    ),
                    if (isPinned) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6)),
                        child: const Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.push_pin_rounded, color: Colors.white, size: 9),
                          SizedBox(width: 3),
                          Text('À la une',
                            style: TextStyle(color: Colors.white, fontSize: 9,
                              fontWeight: FontWeight.w700)),
                        ]),
                      ),
                    ],
                    const Spacer(),
                    if (!isRead)
                      Container(
                        width: 8, height: 8,
                        decoration: const BoxDecoration(
                          color: AppColors.primary, shape: BoxShape.circle),
                      ),
                  ]),
                  const Spacer(),
                  // Titre
                  Text(news['titre'] as String? ?? '',
                    style: const TextStyle(
                      color: Colors.white, fontSize: 15,
                      fontWeight: FontWeight.w800, height: 1.3),
                    maxLines: 3, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 8),
                  // Date + emoji
                  Row(children: [
                    Text(news['emoji'] as String? ?? '',
                      style: const TextStyle(fontSize: 13)),
                    const SizedBox(width: 6),
                    Icon(Icons.schedule_rounded, size: 11, color: Colors.white70),
                    const SizedBox(width: 3),
                    Text(news['date'] as String? ?? '',
                      style: const TextStyle(color: Colors.white70, fontSize: 11)),
                  ]),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// COMPACT CARD — ligne horizontale
// ──────────────────────────────────────────────────────────────────────────────
class _CompactNewsCard extends StatelessWidget {
  final Map<String, dynamic> news;
  final bool isRead;
  final VoidCallback onTap;
  const _CompactNewsCard({required this.news, required this.isRead, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cat    = news['categorie'] as String?;
    final accent = _newsAccent(cat);
    final imgUrl = news['image_url'] as String?;
    final hasImg = imgUrl != null && imgUrl.isNotEmpty;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.cl.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isRead ? context.cl.border : accent.withValues(alpha: 0.35),
            width: isRead ? 0.5 : 1,
          ),
        ),
        child: Row(children: [
          // Miniature image ou emoji
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: hasImg
                ? Image.network(imgUrl!, width: 60, height: 60, fit: BoxFit.cover,
                    headers: _imgHeaders(imgUrl!),
                    errorBuilder: (_, _, _) => _NewsEmojiFallback(
                      emoji: news['emoji'] as String? ?? '📰', accent: accent))
                : _NewsEmojiFallback(emoji: news['emoji'] as String? ?? '📰', accent: accent),
          ),
          const SizedBox(width: 12),
          // Texte
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Catégorie
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4)),
                child: Text(cat ?? '',
                  style: TextStyle(color: accent, fontSize: 9, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 5),
              // Titre
              Text(news['titre'] as String? ?? '',
                style: TextStyle(
                  color: isRead ? context.cl.textS : context.cl.textP,
                  fontSize: 12,
                  fontWeight: isRead ? FontWeight.w500 : FontWeight.w700,
                  height: 1.3),
                maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 5),
              // Date
              Row(children: [
                Icon(Icons.schedule_rounded, size: 10, color: context.cl.textM),
                const SizedBox(width: 3),
                Text(news['date'] as String? ?? '',
                  style: TextStyle(color: context.cl.textM, fontSize: 10)),
              ]),
            ],
          )),
          const SizedBox(width: 8),
          // Point non-lu
          if (!isRead)
            Container(
              width: 8, height: 8,
              decoration: const BoxDecoration(
                color: AppColors.primary, shape: BoxShape.circle),
            ),
        ]),
      ),
    );
  }
}

class _NewsEmojiFallback extends StatelessWidget {
  final String emoji;
  final Color accent;
  const _NewsEmojiFallback({required this.emoji, required this.accent});
  @override
  Widget build(BuildContext context) => Container(
    width: 60, height: 60,
    color: accent.withValues(alpha: 0.10),
    child: Center(child: Text(emoji, style: const TextStyle(fontSize: 26))),
  );
}

// ──────────────────────────────────────────────────────────────────────────────
// NEWS DETAIL BOTTOM SHEET
// ──────────────────────────────────────────────────────────────────────────────
class _NewsDetailSheet extends StatelessWidget {
  final Map<String, dynamic> news;
  const _NewsDetailSheet({required this.news});

  @override
  Widget build(BuildContext context) {
    final cat       = news['categorie'] as String?;
    final accent    = _newsAccent(cat);
    final imgUrl    = news['image_url'] as String?;
    final resume    = news['resume'] as String? ?? '';
    final sourceUrl = news['source_url'] as String?;
    final hasSource = sourceUrl != null && sourceUrl.isNotEmpty;

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (_, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: context.cl.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: ListView(
          controller: scrollCtrl,
          padding: EdgeInsets.zero,
          children: [
            // Drag handle
            Center(child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: context.cl.border, borderRadius: BorderRadius.circular(2)),
            )),

            // Image header
            if (imgUrl != null && imgUrl.isNotEmpty)
              Stack(children: [
                SizedBox(
                  height: 200, width: double.infinity,
                  child: Image.network(imgUrl, fit: BoxFit.cover,
                    headers: _imgHeaders(imgUrl),
                    errorBuilder: (_, _, _) => const SizedBox.shrink())),
                Positioned.fill(child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.black.withValues(alpha: 0.65), Colors.transparent],
                      begin: Alignment.bottomCenter, end: Alignment.topCenter)),
                )),
                // Barre accent bas de l'image
                Positioned(left: 0, right: 0, bottom: 0,
                  child: Container(height: 3, color: accent)),
              ]),

            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Catégorie + date
                  Row(children: [
                    Text(news['emoji'] as String? ?? '', style: const TextStyle(fontSize: 22)),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: accent.withValues(alpha: 0.3))),
                      child: Text(cat ?? '',
                        style: TextStyle(color: accent, fontSize: 11, fontWeight: FontWeight.w700))),
                    const Spacer(),
                    Row(children: [
                      Icon(Icons.schedule_rounded, size: 11, color: context.cl.textM),
                      const SizedBox(width: 3),
                      Text(news['date'] as String? ?? '',
                        style: TextStyle(color: context.cl.textM, fontSize: 11)),
                    ]),
                  ]),
                  const SizedBox(height: 14),

                  // Titre
                  Text(news['titre'] as String? ?? '',
                    style: TextStyle(
                      color: context.cl.textP, fontSize: 20,
                      fontWeight: FontWeight.w800, height: 1.3)),

                  if (resume.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Container(width: double.infinity, height: 2,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [accent, accent.withValues(alpha: 0)]))),
                    const SizedBox(height: 14),
                    Text(resume,
                      style: TextStyle(
                        color: context.cl.textM, fontSize: 14, height: 1.65)),
                  ],

                  const SizedBox(height: 24),

                  // Bouton "Lire l'article complet" si source_url
                  if (hasSource) ...[
                    SizedBox(
                      width: double.infinity,
                      child: GestureDetector(
                        onTap: () {
                          Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => InAppBrowserPage(
                              url:   sourceUrl!,
                              title: news['titre'] as String? ?? '',
                            ),
                          ));
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [AppColors.primary, AppColors.primaryLight]),
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.35),
                              blurRadius: 12, offset: const Offset(0, 4))]),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.open_in_new_rounded, color: Colors.white, size: 16),
                              SizedBox(width: 8),
                              Text('Lire l\'article complet',
                                style: TextStyle(
                                  color: Colors.white, fontSize: 14,
                                  fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],

                  // Bouton fermer
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: TextButton.styleFrom(
                        backgroundColor: context.cl.surfaceD,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14))),
                      child: Text('Fermer',
                        style: TextStyle(
                          color: context.cl.textM, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}


// ══════════════════════════════════════════════════════════════════════════════'
// COMPOSANTS UTILITAIRES
// ══════════════════════════════════════════════════════════════════════════════'
class _SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onMore;
  final int? showBadge;

  const _SectionHeader({
    required this.title,
    this.onMore,
    this.showBadge,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(title,
            style: TextStyle(
                color: context.cl.textP,
                fontSize: 15,
                fontWeight: FontWeight.w800)),
        if (showBadge != null) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.error,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('$showBadge',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w800)),
          ),
        ],
        const Spacer(),
        if (onMore != null)
          GestureDetector(
            onTap: onMore,
            child: const Text('Voir tout',
                style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500)),
          ),
      ],
    );
  }
}

class _PronosticsShimmer extends StatefulWidget {
  const _PronosticsShimmer();
  @override
  State<_PronosticsShimmer> createState() => _PronosticsShimmerState();
}

class _PronosticsShimmerState extends State<_PronosticsShimmer>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.3, end: 0.7).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, _) => Column(
        children: List.generate(
          4,
          (i) => Container(
            margin: const EdgeInsets.only(bottom: 10),
            height: 68,
            decoration: BoxDecoration(
              color: context.cl.surface.withValues(alpha: _anim.value),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                const SizedBox(width: 14),
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: context.cl.borderS.withValues(alpha: _anim.value),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 11,
                        width: 130,
                        decoration: BoxDecoration(
                          color: context.cl.borderS
                              .withValues(alpha: _anim.value),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        height: 9,
                        width: 80,
                        decoration: BoxDecoration(
                          color: context.cl.borderS
                              .withValues(alpha: _anim.value * 0.7),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NewsShimmer extends StatelessWidget {
  const _NewsShimmer();
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 160,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: 3,
          separatorBuilder: (_, _) => const SizedBox(width: 10),
          itemBuilder: (_, i) => Container(
            width: 200,
            height: 160,
            decoration: BoxDecoration(
              color: context.cl.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: context.cl.border, width: 0.5),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(width: 24, height: 24,
                      decoration: BoxDecoration(
                        color: context.cl.borderS,
                        borderRadius: BorderRadius.circular(6))),
                    const Spacer(),
                    Container(width: 48, height: 14,
                      decoration: BoxDecoration(
                        color: context.cl.borderS,
                        borderRadius: BorderRadius.circular(4))),
                  ]),
                  const SizedBox(height: 10),
                  Container(height: 11, width: double.infinity,
                    decoration: BoxDecoration(
                      color: context.cl.borderS,
                      borderRadius: BorderRadius.circular(4))),
                  const SizedBox(height: 6),
                  Container(height: 11, width: 140,
                    decoration: BoxDecoration(
                      color: context.cl.borderS,
                      borderRadius: BorderRadius.circular(4))),
                  const SizedBox(height: 6),
                  Container(height: 11, width: 100,
                    decoration: BoxDecoration(
                      color: context.cl.borderS,
                      borderRadius: BorderRadius.circular(4))),
                ],
              ),
            ),
          ).animate(onPlay: (c) => c.repeat(reverse: true))
            .shimmer(duration: 1200.ms, delay: Duration(milliseconds: i * 150),
              color: context.cl.surface.withValues(alpha: 0.6)),
        ),
      );
}

class _EmptyPronostics extends StatelessWidget {
  const _EmptyPronostics();
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: context.cl.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.cl.border, width: 0.5),
        ),
        child: Row(
          children: [
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.calendar_today_rounded,
                  color: AppColors.primary, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Pas de prono aujourd\'hui',
                      style: TextStyle(
                          color: context.cl.textP,
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text('Le prochain match est demain',
                      style: TextStyle(
                          color: context.cl.textS, fontSize: 11)),
                ],
              ),
            ),
            TextButton(
              onPressed: () => context.go('/pronostics'),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('Voir', style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
                const SizedBox(width: 2),
                const Icon(Icons.arrow_forward_ios_rounded,
                    color: AppColors.primary, size: 10),
              ]),
            ),
          ],
        ),
      );
}

// ══════════════════════════════════════════════════════════════════════════════
// COUNTDOWN PROCHAIN MATCH
// ══════════════════════════════════════════════════════════════════════════════
class _NextMatchCountdown extends ConsumerStatefulWidget {
  const _NextMatchCountdown();
  @override
  ConsumerState<_NextMatchCountdown> createState() => _NextMatchCountdownState();
}

class _NextMatchCountdownState extends ConsumerState<_NextMatchCountdown> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _pad(int v) => v.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final nextAsync = ref.watch(nextPronosticProvider);

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: nextAsync.when(
        loading: () => _NextMatchSkeleton(),
        error:   (_, _) => const SizedBox.shrink(),
        data: (prono) {
          if (prono == null) return const SizedBox.shrink();
          final dateStr   = prono['match_date'] as String?;
          if (dateStr == null) return const SizedBox.shrink();
          final matchDate = DateTime.tryParse(dateStr)?.toLocal();
          if (matchDate == null) return const SizedBox.shrink();
          final diff = matchDate.difference(DateTime.now());
          if (diff.isNegative) return const SizedBox.shrink();

          final days    = diff.inDays;
          final hours   = diff.inHours.remainder(24);
          final minutes = diff.inMinutes.remainder(60);
          final seconds = diff.inSeconds.remainder(60);

          final matchId        = prono['id'] as String?;
          final predLabel      = prono['prediction_label'] as String?;
          final oddsRec        = (prono['odds_recommended'] as num?)?.toDouble();
          final confidenceScore = prono['confidence_score'] as int? ?? 0;
          final isPremium      = prono['is_premium'] as bool? ?? false;

          return GestureDetector(
            onTap: matchId == null ? null : () {
              HapticFeedback.lightImpact();
              context.push('/pronostics/$matchId');
            },
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0B1120), Color(0xFF162040), Color(0xFF0B1120)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.35), width: 0.8),
                boxShadow: [
                  BoxShadow(color: AppColors.primary.withValues(alpha: 0.12),
                    blurRadius: 24, offset: const Offset(0, 6)),
                ],
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [

                // ── Header ──────────────────────────────────────────────────────
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.13),
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(color: AppColors.primary.withValues(alpha: 0.35), width: 0.5)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                        width: 5, height: 5,
                        decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle))
                        .animate(onPlay: (c) => c.repeat())
                        .fadeIn(duration: 600.ms).then().fadeOut(duration: 600.ms),
                      const SizedBox(width: 5),
                      const Text('PROCHAIN MATCH',
                        style: TextStyle(color: AppColors.primary, fontSize: 9,
                          fontWeight: FontWeight.w800, letterSpacing: 0.6)),
                    ]),
                  ),
                  const Spacer(),
                  if (isPremium)
                    Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6)),
                      child: const Text('PREMIUM',
                        style: TextStyle(color: AppColors.warning, fontSize: 8,
                          fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                    ),
                  Text(
                    DateFormat("EEE d MMM · HH'h'mm", 'fr_FR').format(matchDate),
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                ]),
                const SizedBox(height: 16),

                // ── Équipes ──────────────────────────────────────────────────────
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Expanded(child: Column(children: [
                    TeamLogoWidget(url: prono['home_team_logo'] as String?, size: 52),
                    const SizedBox(height: 7),
                    Text(prono['home_team'] as String? ?? '',
                      style: const TextStyle(color: AppColors.textPrimary,
                        fontSize: 12, fontWeight: FontWeight.w700),
                      textAlign: TextAlign.center, maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  ])),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(children: [
                      Text('VS',
                        style: TextStyle(color: context.cl.textM, fontSize: 20,
                          fontWeight: FontWeight.w900, letterSpacing: 3)),
                      const SizedBox(height: 4),
                      Text(prono['league'] as String? ?? '',
                        style: TextStyle(color: context.cl.textM, fontSize: 9),
                        textAlign: TextAlign.center,
                        maxLines: 2),
                    ]),
                  ),
                  Expanded(child: Column(children: [
                    TeamLogoWidget(url: prono['away_team_logo'] as String?, size: 52),
                    const SizedBox(height: 7),
                    Text(prono['away_team'] as String? ?? '',
                      style: const TextStyle(color: AppColors.textPrimary,
                        fontSize: 12, fontWeight: FontWeight.w700),
                      textAlign: TextAlign.center, maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  ])),
                ]),
                const SizedBox(height: 16),

                // ── Countdown ────────────────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.30),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.15), width: 0.5)),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                    if (days > 0) ...[
                      _CountUnit(value: _pad(days), label: days == 1 ? 'JOUR' : 'JOURS'),
                      _CountDivider(),
                    ],
                    _CountUnit(value: _pad(hours), label: 'HEURES'),
                    _CountDivider(),
                    _CountUnit(value: _pad(minutes), label: 'MIN'),
                    _CountDivider(),
                    _CountUnit(value: _pad(seconds), label: 'SEC'),
                  ]),
                ),
                const SizedBox(height: 14),

                // ── Pronostic + confiance + cote ──────────────────────────────────
                if (predLabel != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.20),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.primary.withValues(alpha: 0.12), width: 0.5)),
                    child: Row(children: [
                      // Prono label
                      Expanded(child: Row(children: [
                        const Icon(Icons.trending_up_rounded, color: AppColors.primary, size: 14),
                        const SizedBox(width: 6),
                        Flexible(child: Text(predLabel,
                          style: const TextStyle(color: AppColors.textPrimary,
                            fontSize: 13, fontWeight: FontWeight.w800),
                          overflow: TextOverflow.ellipsis)),
                      ])),
                      // Confiance dots
                      if (confidenceScore > 0) ...[
                        const SizedBox(width: 10),
                        Row(children: List.generate(5, (i) => Container(
                          width: 6, height: 6,
                          margin: const EdgeInsets.only(left: 3),
                          decoration: BoxDecoration(
                            color: i < confidenceScore
                                ? AppColors.success
                                : Colors.white.withValues(alpha: 0.15),
                            shape: BoxShape.circle),
                        ))),
                      ],
                      // Cote
                      if (oddsRec != null) ...[
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.success.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8)),
                          child: Text('x${oddsRec.toStringAsFixed(2)}',
                            style: const TextStyle(color: AppColors.success,
                              fontSize: 12, fontWeight: FontWeight.w800)),
                        ),
                      ],
                    ]),
                  ),

                const SizedBox(height: 14),

                // ── CTA bouton ────────────────────────────────────────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.primary, AppColors.primaryLight]),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(color: AppColors.primary.withValues(alpha: 0.40),
                        blurRadius: 12, offset: const Offset(0, 4)),
                    ],
                  ),
                  child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text('Voir le pronostic',
                      style: TextStyle(color: Colors.white, fontSize: 13,
                        fontWeight: FontWeight.w800)),
                    SizedBox(width: 6),
                    Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 15),
                  ]),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }
}

class _NextMatchSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    height: 280,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: context.cl.surface,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: context.cl.borderSoft, width: 0.8)),
    child: Column(children: [
      Row(children: [
        Container(width: 100, height: 18,
          decoration: BoxDecoration(color: context.cl.surfaceD,
            borderRadius: BorderRadius.circular(6))),
        const Spacer(),
        Container(width: 80, height: 14,
          decoration: BoxDecoration(color: context.cl.surfaceD,
            borderRadius: BorderRadius.circular(6))),
      ]),
      const SizedBox(height: 24),
      Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
        Column(children: [
          Container(width: 52, height: 52,
            decoration: BoxDecoration(color: context.cl.surfaceD, shape: BoxShape.circle)),
          const SizedBox(height: 8),
          Container(width: 60, height: 12,
            decoration: BoxDecoration(color: context.cl.surfaceD,
              borderRadius: BorderRadius.circular(6))),
        ]),
        Container(width: 30, height: 20,
          decoration: BoxDecoration(color: context.cl.surfaceD,
            borderRadius: BorderRadius.circular(4))),
        Column(children: [
          Container(width: 52, height: 52,
            decoration: BoxDecoration(color: context.cl.surfaceD, shape: BoxShape.circle)),
          const SizedBox(height: 8),
          Container(width: 60, height: 12,
            decoration: BoxDecoration(color: context.cl.surfaceD,
              borderRadius: BorderRadius.circular(6))),
        ]),
      ]),
      const SizedBox(height: 20),
      Container(height: 52, decoration: BoxDecoration(
        color: context.cl.surfaceD, borderRadius: BorderRadius.circular(14))),
    ]),
  )
    .animate(onPlay: (c) => c.repeat())
    .shimmer(duration: 1500.ms, color: context.cl.borderSoft.withValues(alpha: 0.5));
}

class _CountUnit extends StatelessWidget {
  final String value, label;
  const _CountUnit({required this.value, required this.label});
  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (child, anim) => SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, -0.5),
                end: Offset.zero,
              ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
              child: FadeTransition(opacity: anim, child: child),
            ),
            child: Text(
              value,
              key: ValueKey(value),
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  fontFeatures: [FontFeature.tabularFigures()]),
            ),
          ),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 8,
                  letterSpacing: 0.6)),
        ],
      );
}

class _CountDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.only(bottom: 12),
        child: Text(':',
            style: TextStyle(
                color: AppColors.primary,
                fontSize: 20,
                fontWeight: FontWeight.w900)),
      );
}

// ══════════════════════════════════════════════════════════════════════════════
// ERROR CARD
// ══════════════════════════════════════════════════════════════════════════════
class _ErrorCard extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorCard({required this.onRetry});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: context.cl.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(Icons.wifi_off_rounded,
                color: context.cl.textM, size: 32),
            const SizedBox(height: 8),
            Text('Erreur de connexion',
                style: TextStyle(color: context.cl.textS)),
            const SizedBox(height: 8),
            TextButton(
                onPressed: onRetry, child: const Text('Réessayer')),
          ],
        ),
      );
}

// ─── BANNIÈRE TUTORIELS ───────────────────────────────────────────────────────
class _TutorielsBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () {
      HapticFeedback.lightImpact();
      context.push('/tutoriels');
    },
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.info.withValues(alpha: 0.12),
            AppColors.info.withValues(alpha: 0.04),
          ],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.info.withValues(alpha: 0.25), width: 0.8),
      ),
      child: Row(children: [
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: AppColors.info.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.school_rounded, color: AppColors.info, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Apprends à gagner',
            style: TextStyle(
              color: context.cl.textP,
              fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text('Stratégies, value bet, bankroll…',
            style: TextStyle(color: context.cl.textM, fontSize: 11)),
        ])),
        const Icon(Icons.arrow_forward_ios_rounded,
          color: AppColors.info, size: 14),
      ]),
    ),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// MES FAVORIS
// ══════════════════════════════════════════════════════════════════════════════
class _FavoritesSection extends ConsumerWidget {
  const _FavoritesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favsAsync = ref.watch(favoritesListProvider);

    return favsAsync.when(
      loading: () => const SizedBox.shrink(),
      error:   (_, _) => const SizedBox.shrink(),
      data: (list) {
        if (list.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader(title: '🔖 Mes favoris', onMore: null),
            const SizedBox(height: 10),
            SizedBox(
              height: 90,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (_, i) {
                  final fav = list[i];
                  return _FavoriteTile(fav: fav);
                },
              ),
            ),
            const SizedBox(height: 20),
          ],
        );
      },
    );
  }
}

class _FavoriteTile extends ConsumerWidget {
  final Map<String, dynamic> fav;
  const _FavoriteTile({required this.fav});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status    = fav['status'] as String? ?? '';
    final isLive    = status == 'live';
    final isFinished = status == 'finished';
    final homeScore = fav['home_score'];
    final awayScore = fav['away_score'];
    final hasScore  = homeScore != null && awayScore != null;
    final pronoId   = fav['prono_id'] as String?;
    final matchId   = fav['match_id'] as String? ?? '';

    Color borderColor = context.cl.border;
    if (isLive) borderColor = AppColors.error.withValues(alpha: 0.6);
    if (isFinished) borderColor = context.cl.border;

    return GestureDetector(
      onTap: () {
        if (pronoId != null) context.push('/pronostics/$pronoId', extra: null);
      },
      child: Container(
        width: 140,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: context.cl.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor, width: 0.8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Ligue + statut
            Row(
              children: [
                Expanded(
                  child: Text(
                    fav['league'] as String? ?? '',
                    style: TextStyle(color: context.cl.textM, fontSize: 9),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isLive)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('LIVE',
                        style: TextStyle(
                            color: AppColors.error,
                            fontSize: 8,
                            fontWeight: FontWeight.w800)),
                  ),
                // Bouton retirer
                GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    ref.read(favoritesProvider.notifier).toggle(matchId);
                    ref.invalidate(favoritesListProvider);
                  },
                  child: const Icon(Icons.bookmark_rounded,
                      color: AppColors.primary, size: 14),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // Équipes
            Row(
              children: [
                TeamLogoWidget(url: fav['home_team_logo'] as String?, size: 18),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    fav['home_team'] as String? ?? '',
                    style: TextStyle(
                        color: context.cl.textP,
                        fontSize: 10,
                        fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Row(
              children: [
                TeamLogoWidget(url: fav['away_team_logo'] as String?, size: 18),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    fav['away_team'] as String? ?? '',
                    style: TextStyle(
                        color: context.cl.textP,
                        fontSize: 10,
                        fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const Spacer(),
            // Score ou heure
            if (hasScore && (isLive || isFinished))
              Text(
                '$homeScore - $awayScore',
                style: TextStyle(
                    color: isLive ? AppColors.error : context.cl.textP,
                    fontSize: 13,
                    fontWeight: FontWeight.w900),
              )
            else if (fav['match_date'] != null)
              Text(
                DateFormat('HH:mm').format(
                    DateTime.tryParse(fav['match_date'] as String) ??
                        DateTime.now()),
                style: TextStyle(color: context.cl.textM, fontSize: 11),
              ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// BANNIÈRE HORS LIGNE (SliverToBoxAdapter)
// ══════════════════════════════════════════════════════════════════════════════
class _SliverOfflineBanner extends ConsumerWidget {
  const _SliverOfflineBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOnline  = ref.watch(isOnlineProvider);
    final lastSync  = ref.watch(lastPronosSyncProvider);
    final fromCache = ref.watch(isServingFromCacheProvider);

    if (isOnline && !fromCache) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    final String message;
    final IconData icon;
    final Color color;

    if (!isOnline) {
      icon  = Icons.wifi_off_rounded;
      color = const Color(0xFFD97706);
      if (lastSync != null) {
        final diff = DateTime.now().difference(lastSync);
        final ago  = diff.inMinutes < 60
            ? 'il y a ${diff.inMinutes} min'
            : 'il y a ${diff.inHours}h';
        message = 'Hors ligne · Données du $ago';
      } else {
        message = 'Hors ligne · Aucune donnée en cache';
      }
    } else {
      icon    = Icons.cloud_done_rounded;
      color   = AppColors.success;
      message = 'Reconnecté · Mise à jour en cours…';
    }

    return SliverToBoxAdapter(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        child: Container(
          key: ValueKey(isOnline),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color:        color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border:       Border.all(color: color.withValues(alpha: 0.35), width: 0.8),
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: 14),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    color: color, fontSize: 11, fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (!isOnline)
                GestureDetector(
                  onTap: () {
                    ref.invalidate(pronosticsJourProvider);
                    ref.invalidate(actualitesProvider);
                    ref.invalidate(statsJourProvider);
                  },
                  child: Icon(Icons.refresh_rounded, color: color, size: 16),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// MINI-WIDGET BANKROLL
// ══════════════════════════════════════════════════════════════════════════════
class _BankrollMiniWidget extends ConsumerWidget {
  const _BankrollMiniWidget();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bankrollAsync = ref.watch(bankrollProvider);

    return bankrollAsync.when(
      loading: () => const SizedBox.shrink(),
      error:   (_, _) => const SizedBox.shrink(),
      data: (bankroll) {
        if (bankroll == null) return const SizedBox.shrink();

        final profit      = bankroll.currentBalance - bankroll.totalBudget;
        final isProfit    = profit >= 0;
        final profitColor = isProfit ? AppColors.success : AppColors.error;
        final settled     = bankroll.bets.where((b) => b.result != null).toList();
        final wins        = settled.where((b) => b.result == 'WIN').length;
        final winRate     = settled.isNotEmpty
            ? '${(wins / settled.length * 100).toStringAsFixed(0)}%'
            : '—';
        final pending = bankroll.bets.where((b) => b.result == null).length;

        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              context.push('/bankroll');
            },
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              decoration: BoxDecoration(
                color: context.cl.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: AppColors.success.withValues(alpha: 0.25), width: 0.8),
                boxShadow: [BoxShadow(
                  color: AppColors.success.withValues(alpha: 0.06),
                  blurRadius: 12, offset: const Offset(0, 4))],
              ),
              child: Row(children: [

                // Icône wallet
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.success, Color(0xFF059669)],
                      begin: Alignment.topLeft, end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [BoxShadow(
                      color: AppColors.success.withValues(alpha: 0.3),
                      blurRadius: 8, offset: const Offset(0, 3))]),
                  child: const Icon(Icons.account_balance_wallet_rounded,
                      color: Colors.white, size: 19)),
                const SizedBox(width: 12),

                // Solde
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Mon Bankroll', style: TextStyle(
                        color: context.cl.textM, fontSize: 11,
                        fontWeight: FontWeight.w500)),
                    const SizedBox(height: 2),
                    Text('${_fmt(bankroll.currentBalance)} ${bankroll.currency}',
                        style: TextStyle(
                            color: context.cl.textP, fontSize: 16,
                            fontWeight: FontWeight.w800, letterSpacing: -0.3)),
                  ],
                )),

                // ROI + win rate
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(
                      isProfit
                          ? Icons.trending_up_rounded
                          : Icons.trending_down_rounded,
                      color: profitColor, size: 13),
                    const SizedBox(width: 3),
                    Text('${isProfit ? '+' : ''}${_fmt(profit)}',
                        style: TextStyle(color: profitColor,
                            fontSize: 12, fontWeight: FontWeight.w700)),
                  ]),
                  const SizedBox(height: 4),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('$winRate win',
                        style: TextStyle(color: context.cl.textM, fontSize: 10)),
                    if (pending > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6)),
                        child: Text('$pending en cours',
                            style: const TextStyle(
                                color: AppColors.warning, fontSize: 9,
                                fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ]),
                ]),

                const SizedBox(width: 8),
                Icon(Icons.chevron_right_rounded,
                    color: context.cl.textM, size: 18),
              ]),
            ),
          ),
        );
      },
    );
  }

  String _fmt(double v) {
    final s = v.abs().toStringAsFixed(0);
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
      buf.write(s[i]);
    }
    return v < 0 ? '-${buf.toString()}' : buf.toString();
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// STREAK BANNER
// ══════════════════════════════════════════════════════════════════════════════
class _StreakBanner extends ConsumerWidget {
  const _StreakBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final streakAsync = ref.watch(streakProvider);

    return streakAsync.when(
      loading: () => const SizedBox.shrink(),
      error:   (_, _) => const SizedBox.shrink(),
      data: (streak) {
        if (streak.streakDays == 0) return const SizedBox.shrink();

        final prevMilestone = streak.milestones
            .lastWhere((m) => m <= streak.streakDays, orElse: () => 0);
        final progress = streak.progressToNext(prevMilestone);
        final isMilestone = streak.isMilestone && streak.todayClaimed;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isMilestone
                  ? [const Color(0xFF2D1B00), const Color(0xFF1A1000)]
                  : [const Color(0xFF1A1A2E), const Color(0xFF0F0F1A)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isMilestone
                  ? AppColors.warning.withValues(alpha: 0.6)
                  : AppColors.primary.withValues(alpha: 0.3),
              width: 0.8,
            ),
            boxShadow: [
              BoxShadow(
                color: (isMilestone ? AppColors.warning : AppColors.primary)
                    .withValues(alpha: 0.12),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Flamme + streak
                  Text(
                    isMilestone ? '🏆' : '🔥',
                    style: const TextStyle(fontSize: 22),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isMilestone
                              ? 'Milestone atteint ! ${streak.streakDays} jours 🎉'
                              : '${streak.streakDays} jours de streak',
                          style: TextStyle(
                            color: isMilestone
                                ? AppColors.warning
                                : AppColors.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          streak.todayClaimed
                              ? '+${streak.xpEarnedToday} XP gagné aujourd\'hui'
                              : 'Connectez-vous demain pour continuer',
                          style: TextStyle(
                            color: streak.todayClaimed
                                ? AppColors.success
                                : AppColors.textMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // XP total
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.3),
                          width: 0.5),
                    ),
                    child: Column(
                      children: [
                        Text(
                          '${streak.xpTotal}',
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const Text(
                          'XP',
                          style: TextStyle(
                            color: AppColors.primaryLight,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              // Barre de progression vers le prochain milestone
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 5,
                        backgroundColor: AppColors.borderSoft,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          isMilestone ? AppColors.warning : AppColors.primary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Next: ${streak.nextMilestone}j',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

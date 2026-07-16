import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../features/auth/presentation/providers/auth_provider.dart';
import '../../../../features/notifications/presentation/providers/notification_service.dart';
import '../../domain/entities/match_entity.dart';
import '../providers/pronostics_provider.dart';
import '../providers/favorites_provider.dart';
import '../widgets/match_card_widget.dart';
import '../../../../shared/widgets/skeletons.dart';
import 'search_page.dart';

class PronosticsPage extends ConsumerStatefulWidget {
  const PronosticsPage({super.key});

  @override
  ConsumerState<PronosticsPage> createState() => _PronosticsPageState();
}

class _PronosticsPageState extends ConsumerState<PronosticsPage> {
  DateTime _selectedDate = DateTime.now();
  late final List<DateTime> _dates;
  bool _showFavorites = false;

  final _sports = [
    {'id': 'all',        'label': 'Tous',       'icon': Icons.apps_rounded},
    {'id': 'football',   'label': 'Football',   'icon': Icons.sports_soccer},
    {'id': 'basketball', 'label': 'Basketball', 'icon': Icons.sports_basketball},
    {'id': 'tennis',     'label': 'Tennis',     'icon': Icons.sports_tennis},
  ];

  static const _pastDays   = 30;
  static const _futureDays = 7;
  final ScrollController _dateScrollCtrl  = ScrollController();
  final ScrollController _listScrollCtrl  = ScrollController();

  void _onListScroll() {
    final pos = _listScrollCtrl.position;
    if (pos.pixels >= pos.maxScrollExtent - 300) {
      ref.read(matchesPaginatedProvider.notifier).loadMore();
    }
  }

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    // -30 jours à +7 jours
    _dates = List.generate(
      _pastDays + _futureDays,
      (i) => today.subtract(Duration(days: _pastDays - i)),
    );
    // Scroll vers aujourd'hui après le premier frame
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToToday());
    _listScrollCtrl.addListener(_onListScroll);
  }

  @override
  void dispose() {
    _dateScrollCtrl.dispose();
    _listScrollCtrl
      ..removeListener(_onListScroll)
      ..dispose();
    super.dispose();
  }

  void _scrollToToday() {
    // Chaque chip fait ~60px, on centre sur l'index _pastDays
    const itemWidth = 60.0;
    final offset = (_pastDays * itemWidth) - 100;
    if (_dateScrollCtrl.hasClients) {
      _dateScrollCtrl.jumpTo(offset.clamp(0, _dateScrollCtrl.position.maxScrollExtent));
    }
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final filter        = ref.watch(pronosticsFilterProvider);
    final statusFilter  = ref.watch(statusFilterProvider);
    final leagueFilter  = ref.watch(leagueFilterProvider);
    final oddsRange     = ref.watch(oddsRangeFilterProvider);
    final pagedState    = ref.watch(matchesPaginatedProvider);
    final authState     = ref.watch(authProvider);
    final unread        = ref.watch(unreadCountProvider);
    final favState      = ref.watch(favoritesProvider);
    final isPremium     = authState is AuthAuthenticated && authState.user.isPremium;
    final favCount      = favState.matchIds.length + favState.leagues.length;
    final allMatches    = pagedState.matches;

    // Compteurs par jour (pour badges + jours grisés)
    final Map<String, int> matchCountByDay = {};
    for (final m in allMatches) {
      final key = '${m.matchDate.year}-${m.matchDate.month}-${m.matchDate.day}';
      matchCountByDay[key] = (matchCountByDay[key] ?? 0) + 1;
    }

    // Ligues disponibles pour le jour sélectionné (pour le filtre)
    final List<String> availableLeagues = [];
    for (final m in allMatches) {
      if (_isSameDay(m.matchDate, _selectedDate) && !availableLeagues.contains(m.league)) {
        availableLeagues.add(m.league);
      }
    }

    final activeAdvancedCount = (leagueFilter != null ? 1 : 0) +
        (oddsRange != OddsRange.all ? 1 : 0);

    return Scaffold(
      appBar: _buildAppBar(context, unread, activeAdvancedCount, availableLeagues),
      body: Column(children: [
        // ── Tab toggle Pronostics / Favoris ──────────────────────────────────
        _TabToggle(
          showFavorites: _showFavorites,
          favCount:      favCount,
          onToggle: (v) {
            HapticFeedback.selectionClick();
            setState(() => _showFavorites = v);
          },
        ),

        // ── Vue Favoris ───────────────────────────────────────────────────────
        if (_showFavorites) Expanded(
          child: ref.watch(favoritesMatchesProvider).when(
            loading: () => _ShimmerList(),
            error: (e, _) => _ErrorView(
              message: e.toString().replaceAll('Exception:', '').trim(),
              onRetry: () => ref.invalidate(favoritesMatchesProvider)),
            data: (favMatches) => _FavoritesView(
              favMatches: favMatches,
              favState:   favState,
              isPremium:  isPremium,
              onToggleLeague: (l) => ref.read(favoritesProvider.notifier).toggleLeague(l),
            ),
          ),
        ),

        // ── Vue normale ───────────────────────────────────────────────────────
        if (!_showFavorites) ...[
          _DateScrollBar(
            dates:           _dates,
            selectedDate:    _selectedDate,
            matchCountByDay: matchCountByDay,
            scrollController: _dateScrollCtrl,
            onSelect: (d) {
              setState(() => _selectedDate = d);
              // Envoyer la date au provider (format YYYY-MM-DD)
              final dateStr = '${d.year.toString().padLeft(4,'0')}-'
                  '${d.month.toString().padLeft(2,'0')}-'
                  '${d.day.toString().padLeft(2,'0')}';
              ref.read(pronosticsFilterProvider.notifier)
                  .update((f) => f.copyWith(dateFilter: dateStr));
            },
          ),
          _SportFilter(
            sports:   _sports,
            selected: filter.sport,
            onSelect: (id) => ref.read(pronosticsFilterProvider.notifier)
                .update((f) => f.copyWith(sport: id)),
          ),
          _StatusFilterBar(
            selected: statusFilter,
            onSelect: (s) {
              HapticFeedback.selectionClick();
              ref.read(statusFilterProvider.notifier).state = s;
            },
          ),
          Expanded(
            child: pagedState.isInitialLoading
              ? _ShimmerList()
              : pagedState.error != null && pagedState.matches.isEmpty
              ? _ErrorView(
                  message: pagedState.error!,
                  onRetry: () => ref.read(matchesPaginatedProvider.notifier).refresh())
              : Builder(builder: (context) {
                final matches = pagedState.matches;
                // Filtrer par date sélectionnée
                var filtered = matches
                    .where((m) => _isSameDay(m.matchDate, _selectedDate))
                    .toList();

                // Filtrer par statut
                if (statusFilter != null) {
                  filtered = filtered.where((m) => m.status == statusFilter).toList();
                }

                // Filtrer par ligue
                if (leagueFilter != null) {
                  filtered = filtered.where((m) => m.league == leagueFilter).toList();
                }

                // Filtrer par plage de cote
                if (oddsRange != OddsRange.all) {
                  filtered = filtered.where((m) {
                    final o = m.oddsRecommended;
                    return switch (oddsRange) {
                      OddsRange.under15    => o > 0 && o < 1.5,
                      OddsRange.from15to25 => o >= 1.5 && o < 2.5,
                      OddsRange.from25to4  => o >= 2.5 && o < 4.0,
                      OddsRange.over4      => o >= 4.0,
                      OddsRange.all        => true,
                    };
                  }).toList();
                }

                // Stats du jour (avant filtres avancés)
                final dayAll    = matches.where((m) => _isSameDay(m.matchDate, _selectedDate)).toList();
                final dayPronos = dayAll.where((m) => m.hasPronostic).length;
                final dayLive   = dayAll.where((m) => m.status == MatchStatus.live).length;

                final hasAnyFilter = statusFilter != null || leagueFilter != null || oddsRange != OddsRange.all;

                if (filtered.isEmpty) {
                  return Column(children: [
                    if (dayAll.isNotEmpty)
                      _DayStatsBar(total: dayAll.length, pronos: dayPronos, live: dayLive),
                    Expanded(child: _EmptyView(
                      date:          _selectedDate,
                      hasFilter:     hasAnyFilter,
                      onClearFilter: () {
                        ref.read(statusFilterProvider.notifier).state = null;
                        ref.read(leagueFilterProvider.notifier).state = null;
                        ref.read(oddsRangeFilterProvider.notifier).state = OddsRange.all;
                      },
                    )),
                  ]);
                }

                // Grouper par ligue — LIVE en premier dans chaque groupe
                final Map<String, List<MatchEntity>> byLeague = {};
                for (final m in filtered) {
                  byLeague.putIfAbsent(m.league, () => []).add(m);
                }
                for (final league in byLeague.keys) {
                  byLeague[league]!.sort((a, b) {
                    if (a.status == MatchStatus.live && b.status != MatchStatus.live) return -1;
                    if (b.status == MatchStatus.live && a.status != MatchStatus.live) return 1;
                    return a.matchDate.compareTo(b.matchDate);
                  });
                }
                final leagues = byLeague.keys.toList()
                  ..sort((a, b) => byLeague[a]!.first.matchDate
                      .compareTo(byLeague[b]!.first.matchDate));

                return RefreshIndicator(
                  color: AppColors.primary,
                  onRefresh: () async =>
                      ref.read(matchesPaginatedProvider.notifier).refresh(),
                  child: ListView(
                    controller: _listScrollCtrl,
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 100),
                    children: [
                      _DayStatsBar(total: dayAll.length, pronos: dayPronos, live: dayLive),
                      if (hasAnyFilter)
                        _ActiveFiltersBar(
                          statusFilter:  statusFilter,
                          leagueFilter:  leagueFilter,
                          oddsRange:     oddsRange,
                          onClear:       () {
                            ref.read(statusFilterProvider.notifier).state = null;
                            ref.read(leagueFilterProvider.notifier).state = null;
                            ref.read(oddsRangeFilterProvider.notifier).state = OddsRange.all;
                          },
                        ),
                      for (final (li, league) in leagues.indexed) ...[
                        _LeagueSectionHeader(
                          league:      league,
                          leagueCode:  byLeague[league]!.first.leagueCountry,
                          count:       byLeague[league]!.length,
                          isFav:       favState.leagues.contains(league),
                          onToggleFav: () => ref.read(favoritesProvider.notifier).toggleLeague(league),
                        )
                          .animate(delay: Duration(milliseconds: li * 80))
                          .fadeIn(duration: 250.ms)
                          .slideX(begin: -0.04, end: 0, duration: 250.ms,
                              curve: Curves.easeOutCubic),
                        ...byLeague[league]!.asMap().entries.map((e) =>
                          MatchCardWidget(match: e.value, isPremiumUser: isPremium)
                            .animate(delay: Duration(milliseconds: li * 80 + e.key * 60 + 30))
                            .fadeIn(duration: 300.ms)
                            .slideY(begin: 0.08, end: 0,
                                duration: 300.ms, curve: Curves.easeOutCubic)),
                        const SizedBox(height: 4),
                      ],
                      // Footer infinite scroll
                      if (pagedState.isLoadingMore)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: Center(child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.primary)),
                        ),
                      if (!pagedState.hasMore && matches.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Center(child: Text(
                            'Tous les matchs sont chargés',
                            style: TextStyle(color: context.cl.textM, fontSize: 12),
                          )),
                        ),
                    ],
                  ),
                );
              }),
          ),
        ],
      ]),
    );
  }

  AppBar _buildAppBar(
    BuildContext context,
    int unread,
    int activeAdvancedCount,
    List<String> availableLeagues,
  ) => AppBar(
    title: Row(children: [
      Container(
        width: 32, height: 32,
        decoration: BoxDecoration(
          color: AppColors.primary, borderRadius: BorderRadius.circular(8)),
        child: const Icon(Icons.emoji_events_rounded, color: Colors.white, size: 18)),
      const SizedBox(width: 10),
      RichText(
        text: TextSpan(
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600,
            color: context.cl.textP),
          children: const [
            TextSpan(text: 'Prono'),
            TextSpan(text: 'Win',
              style: TextStyle(color: AppColors.primaryLight)),
          ],
        ),
      ),
    ]),
    actions: [
      // Bouton recherche
      GestureDetector(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const SearchPage())),
        child: Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Icon(Icons.search_rounded, color: context.cl.textS, size: 24),
        ),
      ),
      const SizedBox(width: 8),
      // Bouton filtres avancés
      GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          showModalBottomSheet(
            context: context,
            backgroundColor: Colors.transparent,
            isScrollControlled: true,
            builder: (_) => _AdvancedFilterSheet(
              availableLeagues: availableLeagues,
              currentLeague:    ref.read(leagueFilterProvider),
              currentOdds:      ref.read(oddsRangeFilterProvider),
              onApply: (league, odds) {
                ref.read(leagueFilterProvider.notifier).state = league;
                ref.read(oddsRangeFilterProvider.notifier).state = odds;
              },
              onReset: () {
                ref.read(leagueFilterProvider.notifier).state = null;
                ref.read(oddsRangeFilterProvider.notifier).state = OddsRange.all;
              },
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Stack(clipBehavior: Clip.none, children: [
            Icon(Icons.tune_rounded, color: activeAdvancedCount > 0
                ? AppColors.primary : context.cl.textS, size: 24),
            if (activeAdvancedCount > 0) Positioned(
              top: -3, right: -3,
              child: Container(
                width: 15, height: 15,
                decoration: BoxDecoration(
                  color: AppColors.primary, shape: BoxShape.circle,
                  border: Border.all(color: context.cl.bg, width: 1.5)),
                child: Center(child: Text('$activeAdvancedCount',
                  style: const TextStyle(
                    color: Colors.white, fontSize: 8,
                    fontWeight: FontWeight.w800))))),
          ]),
        ),
      ),
      const SizedBox(width: 8),
      GestureDetector(
        onTap: () => context.push('/notifications'),
        child: Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Stack(clipBehavior: Clip.none, children: [
            Icon(Icons.notifications_none_rounded, color: context.cl.textS, size: 26),
            if (unread > 0) Positioned(
              top: -3, right: -3,
              child: Container(
                width: 16, height: 16,
                decoration: BoxDecoration(
                  color: AppColors.error, shape: BoxShape.circle,
                  border: Border.all(color: context.cl.bg, width: 1.5)),
                child: Center(
                  child: Text(unread > 9 ? '9+' : '$unread',
                    style: const TextStyle(
                      color: Colors.white, fontSize: 8,
                      fontWeight: FontWeight.w800))))),
          ]),
        ),
      ),
    ],
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// FILTRE STATUT
// ══════════════════════════════════════════════════════════════════════════════
class _StatusFilterBar extends StatelessWidget {
  final MatchStatus? selected;
  final void Function(MatchStatus?) onSelect;
  const _StatusFilterBar({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final filters = <MatchStatus?, _StatusMeta>{
      null:                  _StatusMeta('Tous',     Icons.apps_rounded,               context.cl.textS),
      MatchStatus.upcoming:  _StatusMeta('À venir',  Icons.schedule_rounded,           AppColors.info),
      MatchStatus.live:      _StatusMeta('LIVE',     Icons.radio_button_checked_rounded, AppColors.error),
      MatchStatus.finished:  _StatusMeta('Terminés', Icons.check_circle_outline_rounded, AppColors.success),
    };

    return Container(
      color: context.cl.bg,
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: filters.entries.map((e) {
            final active = selected == e.key;
            final meta   = e.value;
            return Semantics(
              label:    meta.label,
              selected: active,
              button:   true,
              child: GestureDetector(
                onTap: () => onSelect(e.key),
                child: ExcludeSemantics(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
                    decoration: BoxDecoration(
                      color: active ? meta.color.withValues(alpha: 0.15) : context.cl.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: active ? meta.color : context.cl.borderSoft,
                        width: active ? 1 : 0.5)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(meta.icon, size: 13,
                        color: active ? meta.color : context.cl.textM),
                      const SizedBox(width: 5),
                      Text(meta.label, style: TextStyle(
                        color: active ? meta.color : context.cl.textS,
                        fontSize: 12,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w400)),
                    ]),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _StatusMeta {
  final String label; final IconData icon; final Color color;
  const _StatusMeta(this.label, this.icon, this.color);
}

// ══════════════════════════════════════════════════════════════════════════════
// SÉLECTEUR DE DATE HORIZONTAL
// ══════════════════════════════════════════════════════════════════════════════
class _DateScrollBar extends StatelessWidget {
  final List<DateTime> dates;
  final DateTime selectedDate;
  final Map<String, int> matchCountByDay;
  final void Function(DateTime) onSelect;
  final ScrollController? scrollController;

  const _DateScrollBar({
    required this.dates,
    required this.selectedDate,
    required this.matchCountByDay,
    required this.onSelect,
    this.scrollController,
  });

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  int _countForDate(DateTime d) {
    final key = '${d.year}-${d.month}-${d.day}';
    return matchCountByDay[key] ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Container(
      color: context.cl.bg,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: SizedBox(
        height: 72,
        child: ListView.separated(
          controller: scrollController,
          scrollDirection: Axis.horizontal,
          itemCount: dates.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final date       = dates[i];
            final isSelected = _isSameDay(date, selectedDate);
            final isToday    = _isSameDay(date, now);
            final count      = _countForDate(date);
            final hasMatches = count > 0;
            final dayName    = isToday
                ? 'Auj.'
                : DateFormat('E', 'fr_FR').format(date);

            return GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                onSelect(date);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 52,
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.primary
                      : hasMatches
                          ? context.cl.surface
                          : context.cl.surfaceD,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isSelected
                        ? AppColors.primary
                        : isToday
                            ? AppColors.primary.withValues(alpha: 0.4)
                            : context.cl.borderSoft,
                    width: isSelected ? 0 : 0.8),
                  boxShadow: isSelected
                      ? [BoxShadow(color: AppColors.primary.withValues(alpha: 0.35),
                          blurRadius: 10, offset: const Offset(0, 3))]
                      : null,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(dayName, style: TextStyle(
                      color: isSelected
                          ? Colors.white.withValues(alpha: 0.85)
                          : hasMatches ? context.cl.textS : context.cl.textM,
                      fontSize: 10, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 2),
                    Text('${date.day}', style: TextStyle(
                      color: isSelected
                          ? Colors.white
                          : hasMatches ? context.cl.textP : context.cl.textM,
                      fontSize: 17, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    // Badge nombre de matchs
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: hasMatches
                        ? Container(
                            key: ValueKey(count),
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Colors.white.withValues(alpha: 0.25)
                                  : AppColors.primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6)),
                            child: Text('$count',
                              style: TextStyle(
                                color: isSelected ? Colors.white : AppColors.primary,
                                fontSize: 9, fontWeight: FontWeight.w700)))
                        : SizedBox(key: const ValueKey(0), height: 14),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// BARRE STATS DU JOUR
// ══════════════════════════════════════════════════════════════════════════════
class _DayStatsBar extends StatelessWidget {
  final int total;
  final int pronos;
  final int live;
  const _DayStatsBar({required this.total, required this.pronos, required this.live});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 10, 0, 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: context.cl.surface,
        border: Border(
          bottom: BorderSide(color: context.cl.border, width: 0.5),
          top:    BorderSide(color: context.cl.border, width: 0.5),
        ),
      ),
      child: Row(children: [
        _StatPill(
          icon: Icons.sports_soccer_rounded,
          label: '$total match${total > 1 ? 's' : ''}',
          color: context.cl.textS),
        _StatDivider(),
        _StatPill(
          icon: Icons.analytics_outlined,
          label: '$pronos prono${pronos > 1 ? 's' : ''}',
          color: AppColors.primary),
        if (live > 0) ...[
          _StatDivider(),
          _StatPill(
            icon: Icons.radio_button_checked_rounded,
            label: '$live LIVE',
            color: AppColors.error,
            pulse: true),
        ],
      ]),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: -0.05, end: 0);
  }
}

class _StatPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool pulse;
  const _StatPill({required this.icon, required this.label, required this.color, this.pulse = false});

  @override
  Widget build(BuildContext context) {
    Widget iconWidget = Icon(icon, size: 13, color: color);
    if (pulse) {
      iconWidget = iconWidget
        .animate(onPlay: (c) => c.repeat(reverse: true))
        .fade(begin: 1, end: 0.3, duration: 700.ms);
    }
    return Row(mainAxisSize: MainAxisSize.min, children: [
      iconWidget,
      const SizedBox(width: 5),
      Text(label, style: TextStyle(
        color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    ]);
  }
}

class _StatDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    width: 1, height: 14,
    margin: const EdgeInsets.symmetric(horizontal: 12),
    color: context.cl.border);
}

// ══════════════════════════════════════════════════════════════════════════════
// EN-TÊTE DE SECTION LIGUE
// ══════════════════════════════════════════════════════════════════════════════
class _LeagueSectionHeader extends StatelessWidget {
  final String league;
  final String leagueCode;
  final int    count;
  final bool        isFav;
  final VoidCallback? onToggleFav;

  const _LeagueSectionHeader({
    required this.league,
    required this.leagueCode,
    required this.count,
    this.isFav      = false,
    this.onToggleFav,
  });

  String get _leagueEmoji => switch (leagueCode.toUpperCase()) {
    'PL'  => '🏴󠁧󠁢󠁥󠁮󠁧󠁿',
    'BL1' => '🇩🇪',
    'SA'  => '🇮🇹',
    'PD'  => '🇪🇸',
    'FL1' => '🇫🇷',
    'CL'  => '⭐',
    'WC'  => '🌍',
    _     => '⚽',
  };

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 12, bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    decoration: BoxDecoration(
      color: context.cl.surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: context.cl.border, width: 0.5)),
    child: Row(children: [
      Text(_leagueEmoji, style: const TextStyle(fontSize: 16)),
      const SizedBox(width: 8),
      Expanded(child: Text(league, style: TextStyle(
        color: context.cl.textP, fontSize: 13, fontWeight: FontWeight.w700))),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8)),
        child: Text('$count match${count > 1 ? 's' : ''}',
          style: const TextStyle(
            color: AppColors.primary, fontSize: 10, fontWeight: FontWeight.w600))),
      if (onToggleFav != null) ...[
        const SizedBox(width: 8),
        Semantics(
          label:  isFav ? 'Désépingler cette ligue' : 'Épingler cette ligue',
          button: true,
          child: GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              onToggleFav!();
            },
            child: ExcludeSemantics(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  isFav ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                  key: ValueKey(isFav),
                  size: 16,
                  color: isFav ? AppColors.primary : context.cl.textM,
                ),
              ),
            ),
          ),
        ),
      ],
    ]),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// BARRE FILTRES ACTIFS
// ══════════════════════════════════════════════════════════════════════════════
class _ActiveFiltersBar extends StatelessWidget {
  final MatchStatus? statusFilter;
  final String? leagueFilter;
  final OddsRange oddsRange;
  final VoidCallback onClear;
  const _ActiveFiltersBar({
    required this.statusFilter,
    required this.leagueFilter,
    required this.oddsRange,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final chips = <String>[];
    if (statusFilter != null) {
      chips.add(switch (statusFilter!) {
        MatchStatus.upcoming => 'À venir',
        MatchStatus.live     => 'LIVE',
        MatchStatus.finished => 'Terminés',
      });
    }
    if (leagueFilter != null) chips.add(leagueFilter!);
    if (oddsRange != OddsRange.all) {
      chips.add(switch (oddsRange) {
        OddsRange.under15    => 'Cote < 1.5',
        OddsRange.from15to25 => 'Cote 1.5–2.5',
        OddsRange.from25to4  => 'Cote 2.5–4',
        OddsRange.over4      => 'Cote > 4',
        OddsRange.all        => '',
      });
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
      child: Row(children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: chips.map((label) => Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.3), width: 0.5)),
              child: Text(label, style: const TextStyle(
                color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w600)),
            )).toList()),
          ),
        ),
        GestureDetector(
          onTap: onClear,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.close_rounded, size: 13, color: context.cl.textM),
              const SizedBox(width: 3),
              Text('Tout effacer', style: TextStyle(
                color: context.cl.textM, fontSize: 11, fontWeight: FontWeight.w500)),
            ]),
          ),
        ),
      ]),
    ).animate().fadeIn(duration: 250.ms).slideY(begin: -0.1, end: 0);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// SHEET FILTRES AVANCÉS
// ══════════════════════════════════════════════════════════════════════════════
class _AdvancedFilterSheet extends StatefulWidget {
  final List<String> availableLeagues;
  final String? currentLeague;
  final OddsRange currentOdds;
  final void Function(String? league, OddsRange odds) onApply;
  final VoidCallback onReset;

  const _AdvancedFilterSheet({
    required this.availableLeagues,
    required this.currentLeague,
    required this.currentOdds,
    required this.onApply,
    required this.onReset,
  });

  @override
  State<_AdvancedFilterSheet> createState() => _AdvancedFilterSheetState();
}

class _AdvancedFilterSheetState extends State<_AdvancedFilterSheet> {
  late String? _league;
  late OddsRange _odds;

  @override
  void initState() {
    super.initState();
    _league = widget.currentLeague;
    _odds   = widget.currentOdds;
  }

  @override
  Widget build(BuildContext context) {
    final oddsOptions = <OddsRange, String>{
      OddsRange.all:        'Toutes',
      OddsRange.under15:    '< 1.50',
      OddsRange.from15to25: '1.50 – 2.50',
      OddsRange.from25to4:  '2.50 – 4.00',
      OddsRange.over4:      '> 4.00',
    };

    return Container(
      decoration: BoxDecoration(
        color: context.cl.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: context.cl.border, width: 0.5),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Handle + titre
        Center(child: Container(
          width: 36, height: 4,
          margin: const EdgeInsets.only(bottom: 20),
          decoration: BoxDecoration(color: context.cl.borderS, borderRadius: BorderRadius.circular(2)),
        )),
        Row(children: [
          Icon(Icons.tune_rounded, color: AppColors.primary, size: 20),
          const SizedBox(width: 10),
          Text('Filtres avancés', style: TextStyle(
            color: context.cl.textP, fontSize: 16, fontWeight: FontWeight.w700)),
          const Spacer(),
          TextButton(
            onPressed: () {
              HapticFeedback.lightImpact();
              setState(() { _league = null; _odds = OddsRange.all; });
              widget.onReset();
              Navigator.pop(context);
            },
            child: const Text('Réinitialiser')),
        ]),
        const SizedBox(height: 20),

        // Section Ligue
        if (widget.availableLeagues.isNotEmpty) ...[
          Text('LIGUE', style: TextStyle(
            color: context.cl.textM, fontSize: 11,
            fontWeight: FontWeight.w600, letterSpacing: 1)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _FilterChip(
              label: 'Toutes',
              active: _league == null,
              onTap: () => setState(() => _league = null),
            ),
            ...widget.availableLeagues.map((l) => _FilterChip(
              label: l,
              active: _league == l,
              onTap: () => setState(() => _league = _league == l ? null : l),
            )),
          ]),
          const SizedBox(height: 24),
        ],

        // Section Cote
        Text('COTE RECOMMANDÉE', style: TextStyle(
          color: context.cl.textM, fontSize: 11,
          fontWeight: FontWeight.w600, letterSpacing: 1)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: oddsOptions.entries.map((e) =>
          _FilterChip(
            label: e.value,
            active: _odds == e.key,
            color: e.key == OddsRange.all ? null : _oddsColor(e.key),
            onTap: () => setState(() => _odds = e.key),
          ),
        ).toList()),

        const SizedBox(height: 28),

        // Bouton Appliquer
        SizedBox(
          width: double.infinity, height: 50,
          child: ElevatedButton(
            onPressed: () {
              HapticFeedback.mediumImpact();
              widget.onApply(_league, _odds);
              Navigator.pop(context);
            },
            child: Text(
              _hasChange ? 'Appliquer les filtres' : 'Fermer',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          ),
        ),
      ]),
    );
  }

  bool get _hasChange =>
      _league != widget.currentLeague || _odds != widget.currentOdds;

  Color _oddsColor(OddsRange range) => switch (range) {
    OddsRange.under15    => AppColors.success,
    OddsRange.from15to25 => const Color(0xFF84CC16),
    OddsRange.from25to4  => AppColors.warning,
    OddsRange.over4      => AppColors.error,
    OddsRange.all        => AppColors.primary,
  };
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool active;
  final Color? color;
  final VoidCallback onTap;
  const _FilterChip({required this.label, required this.active,
    required this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.primary;
    return Semantics(
      label:    label,
      selected: active,
      button:   true,
      child: GestureDetector(
        onTap: () { HapticFeedback.selectionClick(); onTap(); },
        child: ExcludeSemantics(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: active ? c.withValues(alpha: 0.15) : context.cl.surfaceD,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: active ? c : context.cl.borderSoft,
                width: active ? 1.2 : 0.5)),
            child: Text(label, style: TextStyle(
              color: active ? c : context.cl.textS,
              fontSize: 13,
              fontWeight: active ? FontWeight.w700 : FontWeight.w400)),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// FILTRE SPORTS
// ══════════════════════════════════════════════════════════════════════════════
class _SportFilter extends StatelessWidget {
  final List<Map<String, dynamic>> sports;
  final String selected;
  final void Function(String) onSelect;
  const _SportFilter({required this.sports, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) => Container(
    color: context.cl.bg,
    padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: sports.map((s) {
        final active = selected == s['id'];
        return GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            onSelect(s['id'] as String);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: active ? AppColors.primary : context.cl.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: active ? AppColors.primary : context.cl.borderSoft,
                width: 0.5)),
            child: Row(children: [
              Icon(s['icon'] as IconData, size: 14,
                color: active ? Colors.white : context.cl.textS),
              const SizedBox(width: 6),
              Text(s['label'] as String, style: TextStyle(
                color: active ? Colors.white : context.cl.textS,
                fontSize: 12,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400)),
            ]),
          ),
        );
      }).toList()),
    ),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// TAB TOGGLE
// ══════════════════════════════════════════════════════════════════════════════
class _TabToggle extends StatelessWidget {
  final bool showFavorites;
  final int favCount;
  final void Function(bool) onToggle;

  const _TabToggle({
    required this.showFavorites,
    required this.favCount,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: context.cl.bg,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      child: Row(children: [
        _Tab(
          label:  'Pronostics',
          icon:   Icons.analytics_outlined,
          active: !showFavorites,
          onTap:  () => onToggle(false),
        ),
        const SizedBox(width: 8),
        _Tab(
          label:  'Favoris',
          icon:   Icons.bookmark_rounded,
          active: showFavorites,
          badge:  favCount > 0 ? '$favCount' : null,
          onTap:  () => onToggle(true),
        ),
      ]),
    );
  }
}

class _Tab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final String? badge;
  final VoidCallback onTap;
  const _Tab({required this.label, required this.icon, required this.active,
    required this.onTap, this.badge});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label:    badge != null ? '$label, $badge élément${int.tryParse(badge!) == 1 ? "" : "s"}' : label,
      selected: active,
      button:   true,
      child: GestureDetector(
        onTap: onTap,
        child: ExcludeSemantics(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: active ? AppColors.primary : context.cl.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: active ? AppColors.primary : context.cl.borderSoft,
                width: 0.8),
              boxShadow: active ? [BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.3),
                blurRadius: 8, offset: const Offset(0, 2))] : null,
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 14, color: active ? Colors.white : context.cl.textS),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(
                color: active ? Colors.white : context.cl.textS,
                fontSize: 12, fontWeight: active ? FontWeight.w700 : FontWeight.w400)),
              if (badge != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: active ? Colors.white.withValues(alpha: 0.25)
                        : AppColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8)),
                  child: Text(badge!, style: TextStyle(
                    color: active ? Colors.white : AppColors.primary,
                    fontSize: 10, fontWeight: FontWeight.w700)),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// VUE FAVORIS
// ══════════════════════════════════════════════════════════════════════════════
class _FavoritesView extends StatelessWidget {
  final List<MatchEntity> favMatches;
  final FavoritesState favState;
  final bool isPremium;
  final void Function(String) onToggleLeague;

  const _FavoritesView({
    required this.favMatches,
    required this.favState,
    required this.isPremium,
    required this.onToggleLeague,
  });

  @override
  Widget build(BuildContext context) {
    // Matchs épinglés individuellement (déjà filtrés par le backend)
    final pinnedMatches = List<MatchEntity>.from(favMatches)
      ..sort((a, b) => a.matchDate.compareTo(b.matchDate));

    // Ligues épinglées — matchs de ces ligues qui ne sont pas déjà épinglés individuellement
    final pinnedLeagues = favState.leagues;
    final pinnedIds     = favState.matchIds;
    final Map<String, List<MatchEntity>> byPinnedLeague = {};
    for (final league in pinnedLeagues) {
      final lm = favMatches
          .where((m) => m.league == league && !pinnedIds.contains(m.id))
          .toList()
        ..sort((a, b) => a.matchDate.compareTo(b.matchDate));
      if (lm.isNotEmpty) byPinnedLeague[league] = lm;
    }

    final hasPinnedMatches = pinnedMatches.isNotEmpty;
    final hasPinnedLeagues = byPinnedLeague.isNotEmpty || pinnedLeagues.isNotEmpty;

    if (!hasPinnedMatches && !hasPinnedLeagues && pinnedLeagues.isEmpty) {
      return _FavoritesEmpty();
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 100),
      children: [
        // Section matchs épinglés
        if (hasPinnedMatches) ...[
          _FavSection(
            title: 'Matchs épinglés',
            icon:  Icons.bookmark_rounded,
            count: pinnedMatches.length,
          ),
          ...pinnedMatches.asMap().entries.map((e) =>
            MatchCardWidget(
              match: e.value,
              isPremiumUser: isPremium,
              showDate: true,
            )
              .animate(delay: Duration(milliseconds: e.key * 60))
              .fadeIn(duration: 300.ms)
              .slideY(begin: 0.08, end: 0, duration: 300.ms, curve: Curves.easeOutCubic)),
        ],

        // Section ligues épinglées
        if (pinnedLeagues.isNotEmpty) ...[
          const SizedBox(height: 8),
          _FavSection(
            title: 'Ligues suivies',
            icon:  Icons.push_pin_rounded,
            count: pinnedLeagues.length,
          ),
          for (final league in pinnedLeagues) ...[
            _LeagueSectionHeader(
              league:      league,
              leagueCode:  byPinnedLeague[league]?.first.leagueCountry ?? '',
              count:       byPinnedLeague[league]?.length ?? 0,
              isFav:       true,
              onToggleFav: () => onToggleLeague(league),
            ).animate().fadeIn(duration: 250.ms).slideX(begin: -0.04, end: 0, duration: 250.ms),
            if (byPinnedLeague[league] != null)
              ...byPinnedLeague[league]!.asMap().entries.map((e) =>
                MatchCardWidget(
                  match: e.value,
                  isPremiumUser: isPremium,
                  showDate: true,
                )
                  .animate(delay: Duration(milliseconds: e.key * 60))
                  .fadeIn(duration: 300.ms)
                  .slideY(begin: 0.08, end: 0, duration: 300.ms, curve: Curves.easeOutCubic))
            else
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Center(child: Text(
                  'Aucun match disponible cette semaine',
                  style: TextStyle(color: context.cl.textM, fontSize: 12))),
              ),
          ],
        ],
      ],
    );
  }
}

class _FavSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final int count;
  const _FavSection({required this.title, required this.icon, required this.count});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10, top: 4),
    child: Row(children: [
      Icon(icon, size: 14, color: AppColors.primary),
      const SizedBox(width: 6),
      Text(title, style: TextStyle(
        color: context.cl.textP, fontSize: 13, fontWeight: FontWeight.w700)),
      const SizedBox(width: 8),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8)),
        child: Text('$count', style: const TextStyle(
          color: AppColors.primary, fontSize: 10, fontWeight: FontWeight.w600))),
    ]),
  ).animate().fadeIn(duration: 250.ms);
}

class _FavoritesEmpty extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Stack(alignment: Alignment.center, children: [
          Container(
            width: 120, height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                AppColors.primary.withValues(alpha: 0.15),
                AppColors.primary.withValues(alpha: 0.0),
              ]),
            ),
          ),
          Container(
            width: 88, height: 88,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary.withValues(alpha: 0.10),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.2), width: 1.5),
            ),
            child: const Center(
              child: Icon(Icons.bookmark_border_rounded,
                size: 40, color: AppColors.primaryLight)),
          ),
        ]).animate().scale(
          begin: const Offset(0.4, 0.4), end: const Offset(1, 1),
          duration: 600.ms, curve: Curves.easeOutBack).fadeIn(duration: 400.ms),

        const SizedBox(height: 24),

        Text('Aucun favori pour l\'instant',
          style: TextStyle(
            color: context.cl.textP, fontSize: 18, fontWeight: FontWeight.w700),
          textAlign: TextAlign.center)
          .animate(delay: 150.ms).fadeIn(duration: 300.ms).slideY(begin: 0.15, end: 0),

        const SizedBox(height: 10),

        Text(
          'Épinglez tes matchs avec 🔖 ou tes ligues préférées avec 📌 pour les retrouver ici.',
          style: TextStyle(color: context.cl.textS, fontSize: 13, height: 1.5),
          textAlign: TextAlign.center)
          .animate(delay: 230.ms).fadeIn(duration: 300.ms),
      ]),
    ),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// SHIMMER / ERROR / EMPTY
// ══════════════════════════════════════════════════════════════════════════════
class _ShimmerList extends StatelessWidget {
  @override
  Widget build(BuildContext context) => ListView.builder(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
    itemCount: 3,
    itemBuilder: (_, _) => const MatchCardSkeleton(),
  );
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.wifi_off_rounded, color: context.cl.textM, size: 48),
        const SizedBox(height: 16),
        Text(message, textAlign: TextAlign.center,
          style: TextStyle(color: context.cl.textS, fontSize: 14)),
        const SizedBox(height: 20),
        ElevatedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Réessayer')),
      ]),
    ),
  ).animate().fadeIn(duration: 350.ms).scale(begin: const Offset(0.92, 0.92), end: const Offset(1, 1), duration: 350.ms, curve: Curves.easeOutBack);
}

class _EmptyView extends StatelessWidget {
  final DateTime date;
  final bool hasFilter;
  final VoidCallback onClearFilter;
  const _EmptyView({
    required this.date,
    required this.hasFilter,
    required this.onClearFilter,
  });

  @override
  Widget build(BuildContext context) {
    final isToday = _isSameDay(date, DateTime.now());
    final label   = hasFilter
        ? 'Aucun match pour ce filtre'
        : isToday
            ? "Pas de pronostic aujourd'hui"
            : 'Pas de pronostic ce jour';
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          // Illustration
          Stack(alignment: Alignment.center, children: [
            Container(
              width: 120, height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  AppColors.primary.withValues(alpha: 0.18),
                  AppColors.primary.withValues(alpha: 0.0),
                ]),
              ),
            ),
            Container(
              width: 88, height: 88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withValues(alpha: 0.10),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.2), width: 1.5),
              ),
              child: const Center(
                child: Text('⚽', style: TextStyle(fontSize: 40)),
              ),
            ),
          ])
          .animate()
          .scale(begin: const Offset(0.4, 0.4), end: const Offset(1, 1),
              duration: 600.ms, curve: Curves.easeOutBack)
          .fadeIn(duration: 400.ms),

          const SizedBox(height: 24),

          Text(label, style: TextStyle(
            color: context.cl.textP, fontSize: 18, fontWeight: FontWeight.w700),
            textAlign: TextAlign.center)
            .animate(delay: 150.ms).fadeIn(duration: 300.ms).slideY(begin: 0.15, end: 0),

          const SizedBox(height: 10),

          Text(
            hasFilter
              ? 'Essayez un autre filtre pour découvrir des matchs disponibles.'
              : isToday
                ? 'Nos analystes préparent les meilleures sélections.\nRevenez plus tard !'
                : 'Pas de pronostics pour le ${DateFormat("d MMMM", "fr_FR").format(date)}.\nConsultez une autre date.',
            style: TextStyle(color: context.cl.textS, fontSize: 13, height: 1.5),
            textAlign: TextAlign.center)
            .animate(delay: 230.ms).fadeIn(duration: 300.ms),

          const SizedBox(height: 8),

          if (!hasFilter && isToday)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.2), width: 0.5),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.arrow_downward_rounded, color: AppColors.primaryLight, size: 14),
                const SizedBox(width: 6),
                Text('Tirez vers le bas pour actualiser',
                  style: TextStyle(color: AppColors.primaryLight, fontSize: 12, fontWeight: FontWeight.w500)),
              ]),
            ).animate(delay: 320.ms).fadeIn(duration: 300.ms),

          if (hasFilter) ...[
            const SizedBox(height: 20),
            TextButton.icon(
              onPressed: onClearFilter,
              icon: const Icon(Icons.filter_alt_off_rounded, size: 16),
              label: const Text('Effacer le filtre'))
              .animate(delay: 300.ms).fadeIn(duration: 300.ms),
          ],
        ]),
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

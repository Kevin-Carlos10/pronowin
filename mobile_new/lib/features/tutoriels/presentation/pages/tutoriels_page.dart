import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../features/auth/presentation/providers/auth_provider.dart';
import '../providers/tutoriels_provider.dart';
import '../../domain/entities/tutorial_entity.dart';

class TutorielsPage extends ConsumerWidget {
  const TutorielsPage({super.key});

  static const _categories = [
    (null,                           'Tous',         '🎯'),
    (TutorialCategory.valuebet,      'Value Bet',    '🎯'),
    (TutorialCategory.bankroll,      'Bankroll',     '💰'),
    (TutorialCategory.strategie,     'Stratégie',    '♟️'),
    (TutorialCategory.analyse,       'Analyse',      '📊'),
    (TutorialCategory.psychologie,   'Psychologie',  '🧠'),
  ];

  static const _levels = [
    (null,                        'Tous'),
    (TutorialLevel.beginner,      'Débutant'),
    (TutorialLevel.intermediate,  'Intermédiaire'),
    (TutorialLevel.advanced,      'Avancé'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tutosAsync  = ref.watch(tutorielsProvider);
    final selectedCat = ref.watch(selectedCategoryProvider);
    final selectedLvl = ref.watch(selectedLevelProvider);
    final searchQuery = ref.watch(searchQueryProvider);
    final authState   = ref.watch(authProvider);
    final isPremium   = authState is AuthAuthenticated && authState.user.isPremium;

    return Scaffold(
      body: tutosAsync.when(
        loading: () => _TutorielsShimmer(),
        error:   (e, _) => _ErrorState(
            onRetry: () => ref.invalidate(tutorielsProvider)),
        data: (tutos) {
          // Filtrer
          var filtered = tutos;
          if (selectedCat != null) {
            filtered = filtered.where((t) => t.category == selectedCat).toList();
          }
          if (selectedLvl != null) {
            filtered = filtered.where((t) => t.level == selectedLvl).toList();
          }
          if (searchQuery.isNotEmpty) {
            filtered = filtered.where((t) =>
              t.title.toLowerCase().contains(searchQuery.toLowerCase()) ||
              t.description.toLowerCase().contains(searchQuery.toLowerCase())
            ).toList();
          }

          final completed = tutos.where((t) => t.isCompleted).length;
          final total     = tutos.length;
          final featured  = tutos.isNotEmpty
              ? (List<TutorialEntity>.from(tutos)
                    ..sort((a, b) => b.rating.compareTo(a.rating)))
                    .first
              : null;

          return RefreshIndicator(
            color: AppColors.info,
            onRefresh: () async => ref.invalidate(tutorielsProvider),
            child: CustomScrollView(
            slivers: [
              // ─── APP BAR ────────────────────────────────────────────────
              SliverAppBar(
                automaticallyImplyLeading: false,
                floating: true,
                snap: true,
                elevation: 0,
                backgroundColor: context.cl.bg,
                leading: ModalRoute.of(context)?.canPop == true
                  ? IconButton(
                      icon: Icon(Icons.arrow_back_ios_new_rounded,
                        size: 19, color: context.cl.textP),
                      onPressed: () => Navigator.of(context).pop())
                  : null,
                title: Row(children: [
                  Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.info, Color(0xFF38BDF8)],
                        begin: Alignment.topLeft, end: Alignment.bottomRight),
                      borderRadius: BorderRadius.circular(9),
                      boxShadow: [const BoxShadow(
                        color: Color(0x59038DC8),
                        blurRadius: 8, offset: Offset(0, 3))]),
                    child: const Icon(Icons.school_rounded,
                        color: Colors.white, size: 17)),
                  const SizedBox(width: 10),
                  RichText(text: TextSpan(
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700,
                      color: context.cl.textP),
                    children: const [
                      TextSpan(text: 'Tuto'),
                      TextSpan(text: 'riels',
                        style: TextStyle(color: AppColors.info)),
                    ],
                  )),
                  const Spacer(),
                  // Badge progression
                  if (total > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: AppColors.success.withValues(alpha: 0.25), width: 0.5)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.check_circle_rounded,
                            color: AppColors.success, size: 12),
                        const SizedBox(width: 4),
                        Text('$completed/$total',
                            style: const TextStyle(
                                color: AppColors.success, fontSize: 11, fontWeight: FontWeight.w700)),
                      ]),
                    ),
                ]),
              ),

              SliverToBoxAdapter(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  // ─── BANNIÈRE PROGRESSION ──────────────────────────────
                  if (total > 0 && (selectedCat == null && selectedLvl == null && searchQuery.isEmpty))
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                      child: _ProgressBanner(completed: completed, total: total)
                        .animate().fadeIn(duration: 350.ms)
                        .slideY(begin: 0.05, end: 0),
                    ),

                  // ─── CARD À LA UNE ─────────────────────────────────────
                  if (featured != null &&
                      selectedCat == null && selectedLvl == null &&
                      searchQuery.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                      child: _FeaturedCard(
                        tuto:      featured,
                        isPremium: isPremium,
                        onTap: () {
                          HapticFeedback.lightImpact();
                          context.push('/tutoriels/${featured.id}',
                              extra: featured);
                        },
                      ).animate().fadeIn(duration: 400.ms)
                        .slideY(begin: 0.05, end: 0, duration: 350.ms,
                            curve: Curves.easeOutCubic),
                    ),

                  const SizedBox(height: 16),

                  // ─── BARRE DE RECHERCHE ───────────────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: _SearchBar(ref: ref),
                  ),
                  const SizedBox(height: 12),

                  // ─── FILTRES CATÉGORIE ────────────────────────────────
                  SizedBox(
                    height: 36,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      children: _categories.map((entry) {
                        final (cat, label, emoji) = entry;
                        final sel = selectedCat == cat;
                        return GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            ref.read(selectedCategoryProvider.notifier).state = cat;
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: sel ? AppColors.info : context.cl.surface,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: sel ? AppColors.info : context.cl.border,
                                width: 0.5)),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Text(emoji, style: const TextStyle(fontSize: 12)),
                              const SizedBox(width: 5),
                              Text(label, style: TextStyle(
                                color: sel ? Colors.white : context.cl.textS,
                                fontSize: 12,
                                fontWeight: sel ? FontWeight.w600 : FontWeight.w400)),
                            ])),
                        );
                      }).toList(),
                    ),
                  ),

                  // ─── FILTRE NIVEAU ─────────────────────────────────────
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 34,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      children: _levels.map((entry) {
                        final (lvl, label) = entry;
                        final sel = selectedLvl == lvl;
                        final color = lvl == null
                            ? context.cl.textS
                            : lvl == TutorialLevel.beginner
                                ? AppColors.success
                                : lvl == TutorialLevel.intermediate
                                    ? AppColors.warning
                                    : AppColors.error;
                        return GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            ref.read(selectedLevelProvider.notifier).state = lvl;
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: sel ? color.withValues(alpha: 0.15) : Colors.transparent,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: sel ? color.withValues(alpha: 0.6) : context.cl.borderSoft,
                                width: 0.8)),
                            child: Text(label, style: TextStyle(
                              color: sel ? color : context.cl.textS,
                              fontSize: 11,
                              fontWeight: sel ? FontWeight.w700 : FontWeight.w400)),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Compteur résultats si filtré
                  if (selectedCat != null || selectedLvl != null || searchQuery.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
                      child: Row(children: [
                        Text('${filtered.length} résultat${filtered.length > 1 ? 's' : ''}',
                          style: TextStyle(color: context.cl.textM, fontSize: 12)),
                        const Spacer(),
                        if (selectedCat != null || selectedLvl != null || searchQuery.isNotEmpty)
                          GestureDetector(
                            onTap: () {
                              ref.read(selectedCategoryProvider.notifier).state = null;
                              ref.read(selectedLevelProvider.notifier).state = null;
                              ref.read(searchQueryProvider.notifier).state = '';
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12)),
                              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                                Icon(Icons.close_rounded, color: AppColors.primary, size: 12),
                                SizedBox(width: 4),
                                Text('Tout effacer', style: TextStyle(
                                  color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w600)),
                              ]),
                            ),
                          ),
                      ]),
                    ),
                ],
              )),

              // ─── LISTE TUTORIELS ──────────────────────────────────────
              filtered.isEmpty
                  ? SliverFillRemaining(
                      child: Center(child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 72, height: 72,
                            decoration: BoxDecoration(
                              color: AppColors.info.withValues(alpha: 0.08),
                              shape: BoxShape.circle),
                            child: const Icon(Icons.school_outlined,
                                color: AppColors.info, size: 34)),
                          const SizedBox(height: 14),
                          Text(searchQuery.isNotEmpty
                              ? 'Aucun résultat pour "$searchQuery"'
                              : 'Aucun tutoriel trouvé',
                              style: TextStyle(
                                  color: context.cl.textP, fontSize: 16, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 6),
                          Text(searchQuery.isNotEmpty
                              ? 'Essayez d\'autres mots-clés'
                              : "Essayez d'autres filtres",
                              style: TextStyle(color: context.cl.textS, fontSize: 13)),
                        ],
                      ).animate()
                        .scale(begin: const Offset(0.88, 0.88), end: const Offset(1, 1),
                          duration: 450.ms, curve: Curves.easeOutBack)
                        .fadeIn(duration: 350.ms)),
                    )
                  : SliverPadding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 100),
                      sliver: SliverList.separated(
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemCount: filtered.length,
                        itemBuilder: (_, i) => _PressableTutoCard(
                          tuto:      filtered[i],
                          isPremium: isPremium,
                          onTap: () {
                            HapticFeedback.lightImpact();
                            context.push(
                                '/tutoriels/${filtered[i].id}',
                                extra: filtered[i]);
                          },
                        ).animate(delay: Duration(milliseconds: i * 50))
                          .fadeIn(duration: 300.ms)
                          .slideY(begin: 0.08, end: 0, duration: 300.ms,
                              curve: Curves.easeOutCubic),
                      ),
                    ),
            ],
          ));  // CustomScrollView
        },
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// BARRE DE RECHERCHE
// ══════════════════════════════════════════════════════════════════════════════
class _SearchBar extends StatefulWidget {
  final WidgetRef ref;
  const _SearchBar({required this.ref});
  @override
  State<_SearchBar> createState() => _SearchBarState();
}
class _SearchBarState extends State<_SearchBar> {
  final _ctrl = TextEditingController();
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
      onChanged: (v) => widget.ref.read(searchQueryProvider.notifier).state = v,
      style: TextStyle(color: context.cl.textP, fontSize: 14),
      decoration: InputDecoration(
        hintText: 'Rechercher un tutoriel...',
        hintStyle: TextStyle(color: context.cl.textM, fontSize: 13),
        prefixIcon: Icon(Icons.search_rounded, color: context.cl.textM, size: 20),
        suffixIcon: _ctrl.text.isNotEmpty
          ? IconButton(
              icon: Icon(Icons.close_rounded, color: context.cl.textM, size: 18),
              onPressed: () {
                _ctrl.clear();
                widget.ref.read(searchQueryProvider.notifier).state = '';
                setState(() {});
              })
          : null,
        filled: true,
        fillColor: context.cl.surface,
        contentPadding: const EdgeInsets.symmetric(vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: context.cl.border, width: 0.5)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: context.cl.border, width: 0.5)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.info, width: 1.2)),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// BANNIÈRE PROGRESSION
// ══════════════════════════════════════════════════════════════════════════════
class _ProgressBanner extends StatelessWidget {
  final int completed, total;
  const _ProgressBanner({required this.completed, required this.total});

  @override
  Widget build(BuildContext context) {
    final pct   = total > 0 ? completed / total : 0.0;
    final allDone = completed == total && total > 0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: allDone
          ? AppColors.success.withValues(alpha: 0.08)
          : AppColors.info.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: allDone
            ? AppColors.success.withValues(alpha: 0.25)
            : AppColors.info.withValues(alpha: 0.2))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(
            allDone ? Icons.emoji_events_rounded : Icons.school_rounded,
            color: allDone ? AppColors.success : AppColors.info, size: 16),
          const SizedBox(width: 8),
          Expanded(child: Text(
            allDone
              ? 'Félicitations ! Tous les tutoriels sont terminés 🎉'
              : 'Ta progression',
            style: TextStyle(
              color: allDone ? AppColors.success : context.cl.textP,
              fontSize: 13, fontWeight: FontWeight.w600))),
          Text(
            '$completed / $total',
            style: TextStyle(
              color: allDone ? AppColors.success : AppColors.info,
              fontSize: 12, fontWeight: FontWeight.w700)),
        ]),
        if (!allDone) ...[
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: pct),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (_, v, _) => LinearProgressIndicator(
                value: v,
                minHeight: 5,
                backgroundColor: AppColors.info.withValues(alpha: 0.12),
                valueColor: const AlwaysStoppedAnimation<Color>(AppColors.info),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${(pct * 100).round()}% accompli · ${total - completed} restant${total - completed > 1 ? 's' : ''}',
            style: TextStyle(color: context.cl.textM, fontSize: 11)),
        ],
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// CARD À LA UNE
// ══════════════════════════════════════════════════════════════════════════════
class _FeaturedCard extends StatefulWidget {
  final TutorialEntity tuto;
  final bool isPremium;
  final VoidCallback onTap;
  const _FeaturedCard({required this.tuto, required this.isPremium, required this.onTap});
  @override
  State<_FeaturedCard> createState() => _FeaturedCardState();
}

class _FeaturedCardState extends State<_FeaturedCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _pressCtrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _pressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 90),
      reverseDuration: const Duration(milliseconds: 160),
    );
    _scale = Tween(begin: 1.0, end: 0.97).animate(
      CurvedAnimation(parent: _pressCtrl, curve: Curves.easeOut));
  }

  @override
  void dispose() { _pressCtrl.dispose(); super.dispose(); }

  TutorialEntity get tuto => widget.tuto;
  bool get isPremium => widget.isPremium;

  Color get _catColor => switch (tuto.category) {
    TutorialCategory.valuebet    => AppColors.info,
    TutorialCategory.bankroll    => AppColors.success,
    TutorialCategory.strategie   => AppColors.primary,
    TutorialCategory.analyse     => AppColors.info,
    TutorialCategory.psychologie ||
    TutorialCategory.psychology  => const Color(0xFFA78BFA),
    TutorialCategory.martingale  => AppColors.warning,
    TutorialCategory.trading     => AppColors.error,
    TutorialCategory.statistics  => AppColors.primaryLight,
  };

  @override
  Widget build(BuildContext context) {
    final isLocked = tuto.isPremium && !isPremium;
    return GestureDetector(
      onTapDown: (_) => _pressCtrl.forward(),
      onTapUp: (_) { _pressCtrl.reverse(); widget.onTap(); },
      onTapCancel: () => _pressCtrl.reverse(),
      child: ScaleTransition(scale: _scale, child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _catColor.withValues(alpha: 0.35), width: 0.8),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(children: [
            // Fond : thumbnail ou gradient
            if (tuto.thumbnailUrl != null)
              SizedBox(
                height: 180,
                width: double.infinity,
                child: Image.network(
                  tuto.thumbnailUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => _GradientBg(color: _catColor),
                ),
              )
            else
              _GradientBg(color: _catColor, height: 180),

            // Overlay dégradé bas → haut
            Container(
              height: 180,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.black.withValues(alpha: tuto.thumbnailUrl != null ? 0.65 : 0.0),
                    Colors.black.withValues(alpha: tuto.thumbnailUrl != null ? 0.2 : 0.0),
                  ],
                  begin: Alignment.bottomCenter, end: Alignment.topCenter)),
            ),

            // Contenu
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header badges
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(
                        color: _catColor.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: _catColor.withValues(alpha: 0.5), width: 0.5)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Container(width: 5, height: 5,
                          decoration: BoxDecoration(color: _catColor, shape: BoxShape.circle)),
                        const SizedBox(width: 5),
                        const Text('À LA UNE', style: TextStyle(
                          color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                      ]),
                    ),
                    const Spacer(),
                    if (tuto.isPremium)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [Color(0xFFB8860B), Color(0xFFFFD700)]),
                          borderRadius: BorderRadius.circular(6)),
                        child: const Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 10),
                          SizedBox(width: 3),
                          Text('PREMIUM', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)),
                        ]),
                      ),
                  ]),
                  const SizedBox(height: 80),

                  // Titre
                  Text(tuto.title,
                    style: const TextStyle(color: Colors.white, fontSize: 15,
                      fontWeight: FontWeight.w800, height: 1.25,
                      shadows: [Shadow(color: Colors.black38, blurRadius: 6)]),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 8),

                  // Footer méta
                  Row(children: [
                    _LevelBadge(level: tuto.level),
                    const SizedBox(width: 8),
                    Icon(Icons.access_time_rounded, size: 12, color: Colors.white70),
                    const SizedBox(width: 3),
                    Text(tuto.durationText, style: const TextStyle(color: Colors.white70, fontSize: 11)),
                    const SizedBox(width: 8),
                    const Icon(Icons.star_rounded, size: 12, color: AppColors.warning),
                    Text(' ${tuto.rating.toStringAsFixed(1)}', style: const TextStyle(
                      color: AppColors.warning, fontSize: 11, fontWeight: FontWeight.w700)),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: isLocked ? Colors.black38 : _catColor.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white30, width: 0.5)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(isLocked ? Icons.lock_rounded : Icons.play_arrow_rounded,
                          color: Colors.white, size: 14),
                        const SizedBox(width: 4),
                        Text(isLocked ? 'Premium' : 'Commencer',
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                      ]),
                    ).animate(onPlay: (c) => c.repeat(reverse: true))
                     .shimmer(duration: 2000.ms, color: Colors.white24,
                         delay: isLocked ? 99999.ms : 1000.ms),
                  ]),
                ],
              ),
            ),
          ]),
        ),
      )),
    );
  }
}

class _GradientBg extends StatelessWidget {
  final Color color;
  final double height;
  const _GradientBg({required this.color, this.height = 180});
  @override
  Widget build(BuildContext context) => Container(
    height: height,
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [color.withValues(alpha: 0.7), color.withValues(alpha: 0.3), context.cl.surface],
        begin: Alignment.topLeft, end: Alignment.bottomRight)),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// CARTE TUTORIEL (liste)
// ══════════════════════════════════════════════════════════════════════════════
class _TutoCard extends StatelessWidget {
  final TutorialEntity tuto;
  final bool isPremium;
  final VoidCallback onTap;
  const _TutoCard({required this.tuto, required this.isPremium, required this.onTap});

  Color get _catColor => switch (tuto.category) {
    TutorialCategory.valuebet    => AppColors.info,
    TutorialCategory.bankroll    => AppColors.success,
    TutorialCategory.strategie   => AppColors.primary,
    TutorialCategory.analyse     => AppColors.info,
    TutorialCategory.psychologie ||
    TutorialCategory.psychology  => const Color(0xFFA78BFA),
    TutorialCategory.martingale  => AppColors.warning,
    TutorialCategory.trading     => AppColors.error,
    TutorialCategory.statistics  => AppColors.primaryLight,
  };

  @override
  Widget build(BuildContext context) {
    final isLocked = tuto.isPremium && !isPremium;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.cl.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isLocked
                ? context.cl.border
                : tuto.isCompleted
                    ? AppColors.success.withValues(alpha: 0.3)
                    : tuto.isPremium
                        ? AppColors.warning.withValues(alpha: 0.25)
                        : context.cl.border,
            width: (tuto.isCompleted || tuto.isPremium) ? 0.8 : 0.5),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Bande gauche colorée
            Container(
              width: 3, height: 52,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                color: tuto.isCompleted ? AppColors.success : _catColor,
                borderRadius: BorderRadius.circular(2))),

            // Icône : thumbnail si dispo, sinon emoji
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 48, height: 48,
                child: tuto.thumbnailUrl != null
                  ? Image.network(
                      tuto.thumbnailUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => _EmojiIcon(tuto: tuto, catColor: _catColor),
                    )
                  : _EmojiIcon(tuto: tuto, catColor: _catColor),
              ),
            ),
            const SizedBox(width: 12),

            // Texte
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tuto.title,
                    style: TextStyle(
                        color: context.cl.textP, fontSize: 13,
                        fontWeight: FontWeight.w600, height: 1.3),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 5),
                Row(children: [
                  _LevelBadge(level: tuto.level),
                  const SizedBox(width: 6),
                  Icon(Icons.access_time_rounded, size: 11, color: context.cl.textM),
                  const SizedBox(width: 2),
                  Text(tuto.durationText, style: TextStyle(color: context.cl.textM, fontSize: 10)),
                  const SizedBox(width: 6),
                  const Icon(Icons.star_rounded, size: 11, color: AppColors.warning),
                  Text(' ${tuto.rating.toStringAsFixed(1)}', style: const TextStyle(
                    color: AppColors.warning, fontSize: 10, fontWeight: FontWeight.w600)),
                ]),
              ])),

            const SizedBox(width: 8),
            // Droite : icône lock/premium/chevron
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (tuto.isPremium)
                  Icon(
                    isLocked ? Icons.lock_rounded : Icons.workspace_premium_rounded,
                    color: isLocked ? context.cl.textM : AppColors.warning, size: 16),
                const SizedBox(height: 4),
                Icon(Icons.chevron_right_rounded, color: context.cl.textM, size: 18),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Pressable wrapper pour _TutoCard ──────────────────────────────────────────
class _PressableTutoCard extends StatefulWidget {
  final TutorialEntity tuto;
  final bool isPremium;
  final VoidCallback onTap;
  const _PressableTutoCard({required this.tuto, required this.isPremium, required this.onTap});
  @override
  State<_PressableTutoCard> createState() => _PressableTutoCardState();
}

class _PressableTutoCardState extends State<_PressableTutoCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 85),
      reverseDuration: const Duration(milliseconds: 150),
    );
    _scale = Tween(begin: 1.0, end: 0.97).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTapDown: (_) => _ctrl.forward(),
    onTapUp: (_) { _ctrl.reverse(); widget.onTap(); },
    onTapCancel: () => _ctrl.reverse(),
    child: ScaleTransition(scale: _scale, child: _TutoCard(
      tuto: widget.tuto, isPremium: widget.isPremium, onTap: () {})),
  );
}

// Icône emoji de fallback
class _EmojiIcon extends StatelessWidget {
  final TutorialEntity tuto;
  final Color catColor;
  const _EmojiIcon({required this.tuto, required this.catColor});
  @override
  Widget build(BuildContext context) => Container(
    color: catColor.withValues(alpha: 0.10),
    child: Stack(children: [
      Center(child: Text(tuto.category.emoji, style: const TextStyle(fontSize: 22))),
      if (tuto.isCompleted)
        Positioned(right: -2, bottom: -2,
          child: Container(
            width: 16, height: 16,
            decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle),
            child: const Icon(Icons.check_rounded, color: Colors.white, size: 10))),
    ]),
  );
}

// ── Helpers ───────────────────────────────────────────────────────────────────
class _LevelBadge extends StatelessWidget {
  final TutorialLevel level;
  const _LevelBadge({required this.level});

  Color get _color => switch (level) {
    TutorialLevel.beginner     => AppColors.success,
    TutorialLevel.intermediate => AppColors.warning,
    TutorialLevel.advanced     => AppColors.error,
  };

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: _color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(4)),
        child: Text(level.label, style: TextStyle(
            color: _color, fontSize: 10, fontWeight: FontWeight.w600)));
}

// ── Shimmer ───────────────────────────────────────────────────────────────────
class _TutorielsShimmer extends StatefulWidget {
  @override
  State<_TutorielsShimmer> createState() => _TutorielsShimmerState();
}

class _TutorielsShimmerState extends State<_TutorielsShimmer>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.3, end: 0.7).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _anim,
        builder: (_, _) => ListView.separated(
          padding: const EdgeInsets.fromLTRB(14, 60, 14, 80),
          itemCount: 6,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (_, _) => Container(
            height: 80,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: context.cl.surface,
              borderRadius: BorderRadius.circular(16)),
            child: Row(children: [
              Container(width: 3, height: 52, margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  color: context.cl.surfaceDeep.withValues(alpha: _anim.value),
                  borderRadius: BorderRadius.circular(2))),
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: context.cl.surfaceDeep.withValues(alpha: _anim.value),
                  borderRadius: BorderRadius.circular(12))),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(height: 12, width: double.infinity,
                    decoration: BoxDecoration(
                      color: context.cl.surfaceDeep.withValues(alpha: _anim.value),
                      borderRadius: BorderRadius.circular(6))),
                  const SizedBox(height: 8),
                  Container(height: 10, width: 100,
                    decoration: BoxDecoration(
                      color: context.cl.surfaceDeep.withValues(alpha: _anim.value * 0.6),
                      borderRadius: BorderRadius.circular(6))),
                ])),
            ]),
          ),
        ),
      );
}

// ── Error State ───────────────────────────────────────────────────────────────
class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  color: context.cl.surface, shape: BoxShape.circle,
                  border: Border.all(color: context.cl.border, width: 0.5)),
                child: Icon(Icons.wifi_off_rounded, color: context.cl.textM, size: 38)),
              const SizedBox(height: 20),
              Text('Connexion impossible',
                  style: TextStyle(color: context.cl.textP, fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text('Vérifiez votre connexion internet\net réessayez.',
                  style: TextStyle(color: context.cl.textS, fontSize: 13, height: 1.5),
                  textAlign: TextAlign.center),
              const SizedBox(height: 24),
              GestureDetector(
                onTap: onRetry,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [AppColors.info, Color(0xFF38BDF8)]),
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [BoxShadow(
                      color: AppColors.info.withValues(alpha: 0.35),
                      blurRadius: 12, offset: const Offset(0, 4))]),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.refresh_rounded, color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Text('Réessayer', style: TextStyle(
                      color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                  ]),
                ),
              ),
            ],
          ).animate()
            .fadeIn(duration: 400.ms)
            .scale(begin: const Offset(0.9, 0.9), duration: 400.ms, curve: Curves.easeOutCubic),
        ),
      );
}

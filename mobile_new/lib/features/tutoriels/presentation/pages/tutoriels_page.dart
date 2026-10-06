import 'package:pronowin/l10n/app_strings.dart';
import 'package:flutter/material.dart';
import '../../../../core/widgets/image_distante.dart';
import '../../../../shared/widgets/erreur_chargement.dart';
import '../../../../core/utils/motion.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../features/auth/presentation/providers/auth_provider.dart';
import '../widgets/tutorial_icons.dart';
import '../providers/tutoriels_provider.dart';
import '../../../../shared/utils/montant.dart';
import '../../domain/entities/tutorial_entity.dart';
import '../../../../shared/widgets/bottom_nav_metrics.dart';
import '../../../../shared/utils/rafraichir.dart';

// Couleurs par catégorie connue — repli neutre pour toute catégorie créée
// librement par l'admin et non reconnue de ce code.
const Map<String, Color> _tutorialCategoryColors = {
  'valuebet':    AppColors.info,
  'bankroll':    AppColors.success,
  'strategie':   AppColors.primary,
  'analyse':     AppColors.info,
  'psychologie': Color(0xFFA78BFA),
  'psychology':  Color(0xFFA78BFA),
  'martingale':  AppColors.warning,
  'trading':     AppColors.error,
  'statistics':  AppColors.primaryLight,
};
Color _colorForCategory(String category) =>
    _tutorialCategoryColors[category.toLowerCase()] ?? AppColors.primaryLight;

class TutorielsPage extends ConsumerWidget {
  const TutorielsPage({super.key});

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
        error:   (e, _) => ErreurChargement(
          erreur: e,
          quoi: tr(context, "les tutoriels"),
          from: '/tutoriels',
            onRetry: () => ref.invalidate(tutorielsProvider)),
        data: (tutos) {
          // Catégories disponibles — dérivées des tutoriels réellement présents,
          // pas d'une liste figée : toute nouvelle catégorie créée côté admin
          // apparaît ici automatiquement.
          final categoryOptions = <String>{for (final t in tutos) t.category}.toList()..sort();

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

          // La carte "À la une" n'est affichée que sans filtre actif — dans ce
          // cas, on retire ce tutoriel de la liste en dessous pour éviter de
          // l'afficher deux fois.
          final showFeatured = featured != null &&
              selectedCat == null && selectedLvl == null && searchQuery.isEmpty;
          if (showFeatured) {
            filtered = filtered.where((t) => t.id != featured.id).toList();
          }

          return RefreshIndicator(
            color: context.cl.info,
            onRefresh: () {
              ref.invalidate(tutorielsProvider);
              return attendreChargements([ref.read(tutorielsProvider.future)]);
            },
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
                      gradient: LinearGradient(
                        colors: [context.cl.info, Color(0xFF38BDF8)],
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
                    children: [TextSpan(text: tr(context, "Tutoriels"), style: TextStyle(color: context.cl.info))],
                  )),
                  const Spacer(),
                  // Badge progression
                  if (total > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: context.cl.success.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: context.cl.success.withValues(alpha: 0.25), width: 0.5)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.check_circle_rounded,
                            color: context.cl.success, size: 12),
                        const SizedBox(width: 4),
                        Text('$completed/$total',
                            style: TextStyle(
                                color: context.cl.success, fontSize: 11, fontWeight: FontWeight.w700)),
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
                    height: 44,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      children: [
                        (null, tr(context, "Tous"), ''),
                        for (final c in categoryOptions)
                          (c, TutorialCategoryInfo.labelFor(c), c),
                      ].map((entry) {
                        final (cat, label, iconKey) = entry;
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
                              color: sel ? context.cl.info : context.cl.surface,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: sel ? context.cl.info : context.cl.border,
                                width: 0.5)),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(tutorialCategoryIcon(iconKey),
                                  size: 14,
                                  color: sel ? Colors.white : context.cl.textM),
                              const SizedBox(width: 6),
                              Text(tr(context, label), style: TextStyle(
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
                    height: 44,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      children: _levels.map((entry) {
                        final (lvl, label) = entry;
                        final sel = selectedLvl == lvl;
                        final color = lvl == null
                            ? context.cl.textS
                            : lvl == TutorialLevel.beginner
                                ? context.cl.success
                                : lvl == TutorialLevel.intermediate
                                    ? context.cl.warning
                                    : context.cl.error;
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
                            child: Text(tr(context, label), style: TextStyle(
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
                        Text(AppStrings.of(context).count(filtered.length, one: "{arg0} résultat", other: "{arg0} résultats"),
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
                              child:  Row(mainAxisSize: MainAxisSize.min, children: [
                                Icon(Icons.close_rounded, color: AppColors.primary, size: 12),
                                SizedBox(width: 4),
                                Text(tr(context, "Tout effacer"), style: TextStyle(
                                  color: context.cl.accent, fontSize: 11, fontWeight: FontWeight.w600)),
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
                              color: context.cl.info.withValues(alpha: 0.08),
                              shape: BoxShape.circle),
                            child: Icon(Icons.school_outlined,
                                color: context.cl.info, size: 34)),
                          const SizedBox(height: 14),
                          Text(searchQuery.isNotEmpty
                              ? tr(context, "Aucun résultat pour \"{arg0}\"", [searchQuery])
                              : tr(context, "Aucun tutoriel trouvé"),
                              style: TextStyle(
                                  color: context.cl.textP, fontSize: 16, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 6),
                          Text(searchQuery.isNotEmpty
                              ? tr(context, "Essayez d'autres mots-clés")
                              : tr(context, "Essayez d'autres filtres"),
                              style: TextStyle(color: context.cl.textS, fontSize: 13)),
                        ],
                      ).animate()
                        .scale(begin: const Offset(0.88, 0.88), end: const Offset(1, 1),
                          duration: 450.ms, curve: Curves.easeOutBack)
                        .fadeIn(duration: 350.ms)),
                    )
                  : SliverPadding(
                      padding: EdgeInsets.fromLTRB(14, 0, 14, bottomNavSpace(context)),
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
                        )
                            // Décalage plafonné au 8e élément : sans cela une
                            // liste de 20 tutoriels met une seconde à finir de
                            // s'afficher, et chaque changement de filtre rejoue
                            // toute la cascade.
                            .animate(
                                key: ValueKey(filtered[i].id),
                                delay: Duration(
                                    milliseconds: (i > 8 ? 8 : i) * 45))
                            .fadeIn(duration: 280.ms)
                            .slideY(
                                begin: 0.08,
                                end: 0,
                                duration: 280.ms,
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
        hintText: tr(context, "Rechercher un tutoriel..."),
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
          borderSide: BorderSide(color: context.cl.info, width: 1.2)),
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

    return Semantics(
      label: allDone
        ? tr(context, "Progression : tous les tutoriels sont terminés, {arg0} sur {arg1}.", [total, total])
        : tr(context, "Progression : {arg0} tutoriels terminés sur {arg1}.", [completed, total]),
      excludeSemantics: true,
      child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: allDone
          ? context.cl.success.withValues(alpha: 0.08)
          : context.cl.info.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: allDone
            ? context.cl.success.withValues(alpha: 0.25)
            : context.cl.info.withValues(alpha: 0.2))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(
            allDone ? Icons.emoji_events_rounded : Icons.school_rounded,
            color: allDone ? context.cl.success : context.cl.info, size: 16),
          const SizedBox(width: 8),
          Expanded(child: Text(
            allDone
              ? tr(context, "Félicitations ! Tous les tutoriels sont terminés 🎉")
              : tr(context, "Ta progression"),
            style: TextStyle(
              color: allDone ? context.cl.success : context.cl.textP,
              fontSize: 13, fontWeight: FontWeight.w600))),
          Text(
            '$completed / $total',
            style: TextStyle(
              color: allDone ? context.cl.success : context.cl.info,
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
                backgroundColor: context.cl.info.withValues(alpha: 0.12),
                valueColor: AlwaysStoppedAnimation<Color>(context.cl.info),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            tr(context, "Progression : {arg0}% · À terminer : {arg1}", [(pct * 100).round(), total - completed]),
            style: TextStyle(color: context.cl.textM, fontSize: 11)),
        ],
      ]),
    ));
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

  Color _catColor(BuildContext context) => context.cl.lisible(_colorForCategory(tuto.category));

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
          border: Border.all(color: _catColor(context).withValues(alpha: 0.35), width: 0.8),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(children: [
            // Fond : thumbnail ou gradient
            if (tuto.thumbnailUrl != null)
              SizedBox(
                height: 180,
                width: double.infinity,
                child: ImageDistante(
                  url:   tuto.thumbnailUrl,
                  repli: _GradientBg(color: _catColor(context)),
                ),
              )
            else
              _GradientBg(color: _catColor(context), height: 180),

            // Overlay dégradé bas → haut
            Container(
              height: 180,
              decoration: BoxDecoration(
                // Plus dense en bas, là où se pose le titre : les miniatures
                // portent souvent leur propre texte (« VALUE BET TECHNIQUE
                // GAGNANTE »), et le titre de la carte s'écrivait par-dessus,
                // illisible (vidéo du 5 octobre 2026).
                gradient: LinearGradient(
                  colors: [
                    Colors.black.withValues(alpha: tuto.thumbnailUrl != null ? 0.9 : 0.0),
                    Colors.black.withValues(alpha: tuto.thumbnailUrl != null ? 0.6 : 0.0),
                    Colors.black.withValues(alpha: tuto.thumbnailUrl != null ? 0.15 : 0.0),
                  ],
                  stops: const [0, 0.55, 1],
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
                        color: _catColor(context).withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: _catColor(context).withValues(alpha: 0.5), width: 0.5)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Container(width: 5, height: 5,
                          decoration: BoxDecoration(color: _catColor(context), shape: BoxShape.circle)),
                        const SizedBox(width: 5),
                         Text(tr(context, "À LA UNE"), style: TextStyle(
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
                    if (tuto.aUneDuree) ...[
                      const SizedBox(width: 8),
                      Icon(Icons.access_time_rounded, size: 12, color: Colors.white70),
                      const SizedBox(width: 3),
                      Text(tuto.durationText, style: const TextStyle(color: Colors.white70, fontSize: 11)),
                    ],
                    if (tuto.rating > 0) ...[
                      const SizedBox(width: 8),
                      Icon(Icons.star_rounded, size: 12, color: context.cl.warning),
                      Text(' ${decimalFr(tuto.rating)}', style: TextStyle(
                        color: context.cl.warning, fontSize: 11, fontWeight: FontWeight.w700)),
                    ],
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: isLocked ? Colors.black38 : _catColor(context).withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white30, width: 0.5)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(isLocked ? Icons.lock_rounded : Icons.play_arrow_rounded,
                          color: Colors.white, size: 14),
                        const SizedBox(width: 4),
                        Text(isLocked ? 'Premium' : tr(context, "Commencer"),
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                      ]),
                    ).animate(onPlay: (c) { if (!context.animationsReduites) c.repeat(reverse: true); })
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
  const _TutoCard({required this.tuto, required this.isPremium});

  Color _catColor(BuildContext context) => context.cl.lisible(_colorForCategory(tuto.category));

  @override
  Widget build(BuildContext context) {
    final isLocked = tuto.isPremium && !isPremium;
    return Container(
      decoration: BoxDecoration(
        color: context.cl.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isLocked
              ? context.cl.border
              : tuto.isCompleted
                  ? context.cl.success.withValues(alpha: 0.3)
                  : tuto.isPremium
                      ? context.cl.warning.withValues(alpha: 0.25)
                      : context.cl.border,
          width: (tuto.isCompleted || tuto.isPremium) ? 0.8 : 0.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Miniature pleine largeur (style flux vidéo)
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(fit: StackFit.expand, children: [
              tuto.thumbnailUrl != null
                  ? ImageDistante(
                      url:   tuto.thumbnailUrl,
                      repli: _EmojiIcon(
                          tuto: tuto, catColor: _catColor(context), emojiSize: 40),
                    )
                  : _EmojiIcon(tuto: tuto, catColor: _catColor(context), emojiSize: 40),

              // Badge durée (bas droite, comme sur une miniature vidéo)
              if (tuto.aUneDuree)
              Positioned(
                right: 8, bottom: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(4)),
                  child: Text(tuto.durationText, style: const TextStyle(
                    color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                ),
              ),

              // Badge terminé / premium (haut gauche)
              if (tuto.isCompleted)
                _ThumbBadge(icon: Icons.check_rounded, label: tr(context, "Terminé"), color: AppColors.fondSucces)
              else if (tuto.isPremium)
                _ThumbBadge(icon: Icons.workspace_premium_rounded, label: 'Premium', color: AppColors.fondAlerte),

              // Voile + cadenas si contenu verrouillé
              if (isLocked)
                Positioned.fill(child: Container(
                  color: Colors.black.withValues(alpha: 0.45),
                  child: const Center(
                    child: Icon(Icons.lock_rounded, color: Colors.white, size: 30)),
                )),
            ]),
          ),

          // Texte
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tuto.title,
                  style: TextStyle(
                      color: context.cl.textP, fontSize: 15,
                      fontWeight: FontWeight.w700, height: 1.3),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 6),
              Row(children: [
                _LevelBadge(level: tuto.level),
                if (tuto.aUneDuree) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.access_time_rounded, size: 12, color: context.cl.textM),
                  const SizedBox(width: 3),
                  Text(tuto.durationText, style: TextStyle(color: context.cl.textM, fontSize: 12)),
                ],
                if (tuto.rating > 0) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.star_rounded, size: 12, color: context.cl.warning),
                  Text(' ${decimalFr(tuto.rating)}', style: TextStyle(
                    color: context.cl.warning, fontSize: 12, fontWeight: FontWeight.w600)),
                ],
              ]),
            ]),
          ),
        ],
      ),
    );
  }
}

class _ThumbBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _ThumbBadge({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Positioned(
    left: 8, top: 8,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: Colors.white, size: 12),
        const SizedBox(width: 3),
        Text(tr(context, label), style: const TextStyle(
          color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
      ]),
    ),
  );
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
  Widget build(BuildContext context) {
    final t = widget.tuto;
    final verrouille = t.isPremium && !widget.isPremium;

    return Semantics(
      button: true,
      // Sans libellé, la carte s'annonçait « Débutant », « 4 min », « 1 240 »,
      // « 4.6 » — quatre fragments avant même le titre, et rien ne disait
      // qu'elle était verrouillée.
      label: t.aUneDuree
          ? tr(context, "{arg0}. {arg1} Niveau {arg2}, durée {arg3}.{arg4}", [t.title, t.description, t.levelLabel, t.durationLabel, verrouille ? tr(context, " Réservé aux membres Premium.") : ""])
          : tr(context, "{arg0}. {arg1} Niveau {arg2}.{arg3}", [t.title, t.description, t.levelLabel, verrouille ? tr(context, " Réservé aux membres Premium.") : ""]),
      excludeSemantics: true,
      child: GestureDetector(
        onTapDown: (_) => _ctrl.forward(),
        onTapUp: (_) { _ctrl.reverse(); widget.onTap(); },
        onTapCancel: () => _ctrl.reverse(),
        child: ScaleTransition(scale: _scale, child: _TutoCard(
          tuto: widget.tuto, isPremium: widget.isPremium)),
      ),
    );
  }
}

// Icône emoji de fallback
class _EmojiIcon extends StatelessWidget {
  final TutorialEntity tuto;
  final Color catColor;
  final double emojiSize;
  const _EmojiIcon({required this.tuto, required this.catColor, this.emojiSize = 22});
  @override
  Widget build(BuildContext context) => Container(
    color: catColor.withValues(alpha: 0.10),
    child: Stack(children: [
      Center(
          child: Icon(tutorialCategoryIcon(tuto.category),
              size: emojiSize, color: catColor)),
      if (tuto.isCompleted)
        Positioned(right: -2, bottom: -2,
          child: Container(
            width: 16, height: 16,
            decoration: BoxDecoration(color: AppColors.fondSucces, shape: BoxShape.circle),
            child: const Icon(Icons.check_rounded, color: Colors.white, size: 10))),
    ]),
  );
}

// ── Helpers ───────────────────────────────────────────────────────────────────
class _LevelBadge extends StatelessWidget {
  final TutorialLevel level;
  const _LevelBadge({required this.level});

  Color _color(BuildContext context) => switch (level) {
    TutorialLevel.beginner     => context.cl.success,
    TutorialLevel.intermediate => context.cl.warning,
    TutorialLevel.advanced     => context.cl.error,
  };

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: _color(context).withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(4)),
        child: Text(level.label, style: TextStyle(
            color: _color(context), fontSize: 10, fontWeight: FontWeight.w600)));
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
        vsync: this, duration: const Duration(milliseconds: 900));
    _anim = Tween<double>(begin: 0.3, end: 0.7).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Boucle infinie : coupée si l'utilisateur a réduit les animations.
    // Ce hook est aussi rappelé quand le réglage système change.
    context.boucler(_ctrl, reverse: true);
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


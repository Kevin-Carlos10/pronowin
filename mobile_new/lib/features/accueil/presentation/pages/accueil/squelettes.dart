// En-têtes de section, squelettes et états vides — extrait de accueil_page.dart.
//
// `part` et non un fichier autonome : ces classes sont privées à la
// bibliothèque (préfixe `_`) et doivent le rester. Un import classique
// aurait imposé de les rendre publiques, donc visibles de partout.
part of '../accueil_page.dart';

class _SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onMore;
  final int? showBadge;

  /// Élément posé avant le titre. Auparavant les sections « En direct »,
  /// « Mes favoris » et « Actualités » cuisaient un emoji dans leur chaîne de
  /// titre, et les Actualités avaient en plus leur propre en-tête recopié.
  final Widget? leading;
  final String moreLabel;
  final Color? badgeColor;

  const _SectionHeader({
    required this.title,
    this.onMore,
    this.showBadge,
    this.leading,
    this.moreLabel = 'Voir tout',
    this.badgeColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (leading != null) ...[leading!, const SizedBox(width: 7)],
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
              color: badgeColor ?? AppColors.error,
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
            child: Text(moreLabel,
                style: const TextStyle(
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
    );
    _anim = Tween<double>(begin: 0.3, end: 0.7).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Boucle infinie : coupée si l'utilisateur a réduit les animations.
    // Ce hook est aussi rappelé quand le réglage système change.
    context.boucler(_ctrl, reverse: true);
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
          ).animate(onPlay: (c) { if (!context.animationsReduites) c.repeat(reverse: true); })
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

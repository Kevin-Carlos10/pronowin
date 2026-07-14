import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/tutorial_entity.dart';

class TutorialCardWidget extends StatelessWidget {
  final TutorialEntity tutorial;
  final bool           isPremiumUser;
  final VoidCallback   onTap;

  const TutorialCardWidget({
    super.key, required this.tutorial,
    required this.isPremiumUser, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final locked = tutorial.isPremium && !isPremiumUser;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: context.cl.surface, borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.cl.border, width: 0.5),
        ),
        child: Row(
          children: [
            // ─── Thumbnail ─────────────────────────────────────────
            Hero(
              tag: 'tutorial_thumb_${tutorial.id}',
              child: ClipRRect(
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
              child: Stack(
                children: [
                  Container(
                    width: 100, height: 100,
                    color: _categoryColor.withValues(alpha: 0.12),
                    child: Center(child: Text(_categoryEmoji, style: const TextStyle(fontSize: 34))),
                  ),
                  // Play / Lock overlay
                  Positioned.fill(child: Center(
                    child: Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: locked ? context.cl.textM.withValues(alpha: 0.7) : AppColors.primary.withValues(alpha: 0.9),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        locked ? Icons.lock_rounded : Icons.play_arrow_rounded,
                        color: Colors.white, size: 20,
                      ),
                    ),
                  )),
                  // Completed badge
                  if (tutorial.isCompleted)
                    Positioned(top: 6, right: 6,
                      child: Container(
                        width: 20, height: 20,
                        decoration: BoxDecoration(color: AppColors.success, shape: BoxShape.circle),
                        child: const Icon(Icons.check_rounded, color: Colors.white, size: 12),
                      ),
                    ),
                  // Premium badge
                  if (tutorial.isPremium)
                    Positioned(bottom: 6, left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primary, borderRadius: BorderRadius.circular(4)),
                        child: const Text('VIP', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700)),
                      ),
                    ),
                ],
              ),
            )),  // fin Hero + ClipRRect

            // ─── Infos ────────────────────────────────────────────
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Catégorie + niveau
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: _levelColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10)),
                        child: Text(tutorial.levelLabel, style: TextStyle(
                          color: _levelColor, fontSize: 10, fontWeight: FontWeight.w600)),
                      ),
                      SizedBox(width: 6),
                      Text(tutorial.categoryLabel, style: TextStyle(color: context.cl.textM, fontSize: 10)),
                    ]),
                    const SizedBox(height: 6),

                    // Titre
                    Text(tutorial.title,
                      style: TextStyle(
                        color: locked ? context.cl.textS : context.cl.textP,
                        fontSize: 13, fontWeight: FontWeight.w600, height: 1.3),
                      maxLines: 2, overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: 8),

                    // Méta
                    Row(children: [
                      Icon(Icons.access_time_rounded, size: 12, color: context.cl.textM),
                      SizedBox(width: 4),
                      Text(tutorial.durationLabel, style: TextStyle(color: context.cl.textM, fontSize: 11)),
                      SizedBox(width: 12),
                      Icon(Icons.star_rounded, size: 12, color: AppColors.primaryLight),
                      SizedBox(width: 3),
                      Text(tutorial.rating.toStringAsFixed(1), style: TextStyle(color: context.cl.textM, fontSize: 11)),
                      SizedBox(width: 12),
                      Icon(Icons.visibility_rounded, size: 12, color: context.cl.textM),
                      SizedBox(width: 3),
                      Text(_formatViews(tutorial.viewCount), style: TextStyle(color: context.cl.textM, fontSize: 11)),
                    ]),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color get _levelColor => switch (tutorial.level) {
    TutorialLevel.beginner     => AppColors.success,
    TutorialLevel.intermediate => AppColors.warning,
    TutorialLevel.advanced     => AppColors.error,
  };

  Color get _categoryColor => switch (tutorial.category) {
    TutorialCategory.valuebet    => AppColors.info,
    TutorialCategory.bankroll    => AppColors.success,
    TutorialCategory.martingale  => AppColors.warning,
    TutorialCategory.trading     => AppColors.error,
    TutorialCategory.psychology  => const Color(0xFFA78BFA),
    TutorialCategory.statistics  => AppColors.primary,
    TutorialCategory.strategie   => AppColors.primaryLight,
    TutorialCategory.analyse     => AppColors.info,
    TutorialCategory.psychologie => const Color(0xFFA78BFA),
  };

  String get _categoryEmoji => switch (tutorial.category) {
    TutorialCategory.valuebet    => '📈',
    TutorialCategory.bankroll    => '💰',
    TutorialCategory.martingale  => '🔄',
    TutorialCategory.trading     => '',
    TutorialCategory.psychology  => '🧠',
    TutorialCategory.statistics  => '📊',
    TutorialCategory.strategie   => '♟️',
    TutorialCategory.analyse     => '🔍',
    TutorialCategory.psychologie => '🧠',
  };

  String _formatViews(int v) => v >= 1000 ? '${(v / 1000).toStringAsFixed(1)}k' : '$v';
}

import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../../core/theme/app_theme.dart';

// ════════════════════════════════════════════════════════════════════════════
// PRIMITIVES
// ════════════════════════════════════════════════════════════════════════════

/// Boîte skeleton (rectangle ou cercle) avec couleur de base thématique.
class SkeletonBox extends StatelessWidget {
  final double width;
  final double height;
  final double radius;
  final bool circle;

  const SkeletonBox({
    super.key,
    this.width = double.infinity,
    required this.height,
    this.radius = 8,
    this.circle = false,
  });

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: context.cl.surface,
      borderRadius: circle ? null : BorderRadius.circular(radius),
      shape: circle ? BoxShape.circle : BoxShape.rectangle,
    ),
  );
}

// ════════════════════════════════════════════════════════════════════════════
// MATCH CARD SKELETON  (reproduit la structure de MatchCardWidget)
// ════════════════════════════════════════════════════════════════════════════

class MatchCardSkeleton extends StatelessWidget {
  const MatchCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor:      context.cl.surface,
      highlightColor: context.cl.surfaceDeep,
      period: const Duration(milliseconds: 1200),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: context.cl.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: context.cl.border, width: 0.5),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 11, 14, 14),
          child: Column(children: [

            // ── Header : badge ligue + heure ──────────────────────────
            Row(children: [
              // Badge ligue (pill)
              Container(
                height: 24, width: 110,
                decoration: BoxDecoration(
                  color: context.cl.surfaceDeep,
                  borderRadius: BorderRadius.circular(20)),
              ),
              const Spacer(),
              // Heure
              Container(
                height: 16, width: 40,
                decoration: BoxDecoration(
                  color: context.cl.surfaceDeep,
                  borderRadius: BorderRadius.circular(8)),
              ),
            ]),

            const SizedBox(height: 14),

            // ── Équipes + VS ──────────────────────────────────────────
            Row(children: [
              // Équipe domicile
              Expanded(child: Column(children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: context.cl.surfaceDeep, shape: BoxShape.circle),
                ),
                const SizedBox(height: 6),
                Container(
                  height: 10, width: 60,
                  decoration: BoxDecoration(
                    color: context.cl.surfaceDeep,
                    borderRadius: BorderRadius.circular(6)),
                ),
              ])),

              // VS / Score
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Container(
                  height: 14, width: 24,
                  decoration: BoxDecoration(
                    color: context.cl.surfaceDeep,
                    borderRadius: BorderRadius.circular(6)),
                ),
              ),

              // Équipe extérieure
              Expanded(child: Column(children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: context.cl.surfaceDeep, shape: BoxShape.circle),
                ),
                const SizedBox(height: 6),
                Container(
                  height: 10, width: 60,
                  decoration: BoxDecoration(
                    color: context.cl.surfaceDeep,
                    borderRadius: BorderRadius.circular(6)),
                ),
              ])),
            ]),

            const SizedBox(height: 14),

            // ── Badge pronostic + confiance ───────────────────────────
            Row(children: [
              Expanded(
                child: Container(
                  height: 32,
                  decoration: BoxDecoration(
                    color: context.cl.surfaceDeep,
                    borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(width: 10),
              // Jauge confiance (5 barres)
              SizedBox(
                width: 48,
                child: Column(children: [
                  Container(
                    height: 9, width: 36,
                    decoration: BoxDecoration(
                      color: context.cl.surfaceDeep,
                      borderRadius: BorderRadius.circular(4)),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: List.generate(5, (_) => Expanded(
                      child: Container(
                        height: 5,
                        margin: const EdgeInsets.symmetric(horizontal: 1),
                        decoration: BoxDecoration(
                          color: context.cl.surfaceDeep,
                          borderRadius: BorderRadius.circular(3)),
                      ),
                    )),
                  ),
                ]),
              ),
            ]),

            const SizedBox(height: 10),

            // ── Cotes H / N / A ───────────────────────────────────────
            Row(children: List.generate(3, (i) => Expanded(
              child: Container(
                height: 42,
                margin: EdgeInsets.only(right: i < 2 ? 6 : 0),
                decoration: BoxDecoration(
                  color: context.cl.surfaceDeep,
                  borderRadius: BorderRadius.circular(10)),
              ),
            ))),

          ]),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// NOTIFICATION TILE SKELETON
// ════════════════════════════════════════════════════════════════════════════

class NotifTileSkeleton extends StatelessWidget {
  const NotifTileSkeleton({super.key});

  @override
  Widget build(BuildContext context) => Shimmer.fromColors(
    baseColor:      context.cl.surface,
    highlightColor: context.cl.surfaceDeep,
    period: const Duration(milliseconds: 1200),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Icône cercle
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: context.cl.surfaceDeep, shape: BoxShape.circle),
        ),
        const SizedBox(width: 12),
        // Lignes de texte
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            height: 13, width: double.infinity,
            decoration: BoxDecoration(
              color: context.cl.surfaceDeep,
              borderRadius: BorderRadius.circular(6)),
          ),
          const SizedBox(height: 7),
          Container(
            height: 11, width: 180,
            decoration: BoxDecoration(
              color: context.cl.surfaceDeep,
              borderRadius: BorderRadius.circular(6)),
          ),
          const SizedBox(height: 5),
          Container(
            height: 11, width: 120,
            decoration: BoxDecoration(
              color: context.cl.surfaceDeep,
              borderRadius: BorderRadius.circular(6)),
          ),
        ])),
        const SizedBox(width: 12),
        // Timestamp
        Container(
          height: 11, width: 32,
          decoration: BoxDecoration(
            color: context.cl.surfaceDeep,
            borderRadius: BorderRadius.circular(6)),
        ),
      ]),
    ),
  );
}

// ════════════════════════════════════════════════════════════════════════════
// HOME PAGE SKELETON (section stats + en-tête)
// ════════════════════════════════════════════════════════════════════════════

class HomeStatsSkeleton extends StatelessWidget {
  const HomeStatsSkeleton({super.key});

  @override
  Widget build(BuildContext context) => Shimmer.fromColors(
    baseColor:      context.cl.surface,
    highlightColor: context.cl.surfaceDeep,
    period: const Duration(milliseconds: 1200),
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.cl.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.cl.border, width: 0.5)),
      child: Row(children: List.generate(4, (i) => Expanded(
        child: Row(children: [
          Expanded(child: Column(children: [
            Container(
              height: 22, width: 36,
              decoration: BoxDecoration(
                color: context.cl.surfaceDeep,
                borderRadius: BorderRadius.circular(6)),
            ),
            const SizedBox(height: 4),
            Container(
              height: 9, width: 50,
              decoration: BoxDecoration(
                color: context.cl.surfaceDeep,
                borderRadius: BorderRadius.circular(4)),
            ),
          ])),
          if (i < 3) Container(
            width: 1, height: 36,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            color: context.cl.border),
        ]),
      ))),
    ),
  );
}

// ════════════════════════════════════════════════════════════════════════════
// TUTORIAL CARD SKELETON
// ════════════════════════════════════════════════════════════════════════════

class TutorialCardSkeleton extends StatelessWidget {
  const TutorialCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) => Shimmer.fromColors(
    baseColor:      context.cl.surface,
    highlightColor: context.cl.surfaceDeep,
    period: const Duration(milliseconds: 1200),
    child: Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: context.cl.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.cl.border, width: 0.5)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          // Thumbnail
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
              color: context.cl.surfaceDeep,
              borderRadius: BorderRadius.circular(12)),
          ),
          const SizedBox(width: 12),
          // Texte
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              height: 14, width: double.infinity,
              decoration: BoxDecoration(
                color: context.cl.surfaceDeep,
                borderRadius: BorderRadius.circular(6)),
            ),
            const SizedBox(height: 8),
            Container(
              height: 11, width: 200,
              decoration: BoxDecoration(
                color: context.cl.surfaceDeep,
                borderRadius: BorderRadius.circular(6)),
            ),
            const SizedBox(height: 6),
            Container(
              height: 11, width: 140,
              decoration: BoxDecoration(
                color: context.cl.surfaceDeep,
                borderRadius: BorderRadius.circular(6)),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Container(
                height: 20, width: 60,
                decoration: BoxDecoration(
                  color: context.cl.surfaceDeep,
                  borderRadius: BorderRadius.circular(10)),
              ),
              const SizedBox(width: 8),
              Container(
                height: 20, width: 60,
                decoration: BoxDecoration(
                  color: context.cl.surfaceDeep,
                  borderRadius: BorderRadius.circular(10)),
              ),
            ]),
          ])),
        ]),
      ),
    ),
  );
}

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/utils/premium_nav.dart';
import '../../domain/entities/tutorial_entity.dart';
import '../providers/tutorial_provider.dart';

class TutorialDetailPage extends ConsumerStatefulWidget {
  final String          tutorialId;
  final TutorialEntity? preloaded;
  const TutorialDetailPage(
      {super.key, required this.tutorialId, this.preloaded});

  @override
  ConsumerState<TutorialDetailPage> createState() => _TutorialDetailPageState();
}

class _TutorialDetailPageState extends ConsumerState<TutorialDetailPage>
    with SingleTickerProviderStateMixin {
  bool _completed = false;
  late AnimationController _checkCtrl;
  late Animation<double>   _checkAnim;

  @override
  void initState() {
    super.initState();
    _completed = widget.preloaded?.isCompleted ?? false;
    _checkCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _checkAnim = CurvedAnimation(parent: _checkCtrl, curve: Curves.elasticOut);
  }

  @override
  void dispose() {
    _checkCtrl.dispose();
    super.dispose();
  }

  Future<void> _markComplete() async {
    if (_completed) return;
    HapticFeedback.heavyImpact();
    setState(() => _completed = true);
    _checkCtrl.forward();

    // Persister côté API
    try {
      await ref.read(videoProgressProvider.notifier)
          .updateProgress(widget.tutorialId, widget.preloaded?.durationSeconds ?? 0, true);
    } catch (_) {
      // Ignorer les erreurs réseau silencieusement — l'état local est déjà mis à jour
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(children: [
            Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
            SizedBox(width: 10),
            Text('Tutoriel marqué comme terminé ! 🎉',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ]),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.preloaded;
    if (t == null) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
              onPressed: () => context.pop()),
        ),
        body: Center(
          child: Text('Tutoriel introuvable',
              style: TextStyle(color: context.cl.textS)),
        ),
      );
    }

    final catColor = _categoryColor(t.category);
    final isPremiumLocked = t.isPremium;

    return Scaffold(
      backgroundColor: context.cl.bg,
      body: Stack(
        children: [
          // ── CONTENU PRINCIPAL ────────────────────────────────────────────
          CustomScrollView(
            slivers: [
              // ─── HEADER SLIVER ─────────────────────────────────────────
              _HeroHeader(tutorial: t, catColor: catColor),

              // ─── CORPS ─────────────────────────────────────────────────
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([

                    // Tags
                    Wrap(spacing: 8, runSpacing: 6, children: [
                      _Tag(label: t.levelLabel,
                          color: _levelColor(t.level)),
                      _Tag(label: t.categoryLabel,
                          color: catColor),
                      if (t.isPremium)
                        _Tag(label: '👑 Premium',
                            color: AppColors.warning),
                      if (_completed)
                        _Tag(label: '✓ Terminé',
                            color: AppColors.success),
                    ]).animate().fadeIn(duration: 300.ms, delay: 50.ms),

                    const SizedBox(height: 14),

                    // Titre
                    Text(t.title,
                        style: TextStyle(
                            color: context.cl.textP,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            height: 1.25))
                      .animate().fadeIn(duration: 300.ms, delay: 80.ms),

                    const SizedBox(height: 12),

                    // Méta stats
                    _MetaRow(tutorial: t)
                      .animate().fadeIn(duration: 300.ms, delay: 110.ms),

                    const SizedBox(height: 16),

                    // Description intro
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: catColor.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: catColor.withValues(alpha: 0.2),
                            width: 0.5)),
                      child: Text(t.description,
                          style: TextStyle(
                              color: context.cl.textS,
                              fontSize: 14,
                              height: 1.65)),
                    ).animate().fadeIn(duration: 300.ms, delay: 140.ms),

                    const SizedBox(height: 24),

                    // ── CONTENU (VERROUILLÉ OU NON) ──────────────────────
                    if (isPremiumLocked)
                      _PremiumLock(catColor: catColor)
                        .animate().fadeIn(duration: 400.ms, delay: 160.ms)
                    else ...[
                      // Vidéo
                      if (t.hasVideo && t.videoUrl != null) ...[
                        _VideoSection(url: t.videoUrl!, duration: t.durationText)
                          .animate().fadeIn(duration: 300.ms, delay: 160.ms),
                        const SizedBox(height: 24),
                      ],

                      // Article
                      if (t.articleContent != null &&
                          t.articleContent!.trim().isNotEmpty) ...[
                        _SectionDivider(label: 'Contenu du tutoriel'),
                        const SizedBox(height: 16),
                        _MarkdownRenderer(
                            content: t.articleContent!,
                            catColor: catColor)
                          .animate().fadeIn(duration: 400.ms, delay: 180.ms),
                        const SizedBox(height: 24),
                      ],

                      // Si rien à afficher
                      if (!t.hasVideo &&
                          (t.articleContent == null ||
                              t.articleContent!.trim().isEmpty))
                        _PlaceholderContent(catColor: catColor)
                          .animate().fadeIn(duration: 300.ms, delay: 160.ms),
                    ],

                    // Auteur
                    if (t.authorName != null) ...[
                      const SizedBox(height: 8),
                      _AuthorCard(name: t.authorName!)
                        .animate().fadeIn(duration: 300.ms, delay: 200.ms),
                    ],

                    const SizedBox(height: 16),
                  ]),
                ),
              ),
            ],
          ),

          // ── BOUTON STICKY BAS ────────────────────────────────────────────
          if (!isPremiumLocked)
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: _BottomBar(
                completed: _completed,
                checkAnim: _checkAnim,
                catColor:  catColor,
                onComplete: _markComplete,
              ),
            ),
        ],
      ),
    );
  }

  Color _categoryColor(TutorialCategory c) => switch (c) {
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

  Color _levelColor(TutorialLevel l) => switch (l) {
    TutorialLevel.beginner     => AppColors.success,
    TutorialLevel.intermediate => AppColors.warning,
    TutorialLevel.advanced     => AppColors.error,
  };
}

// ══════════════════════════════════════════════════════════════════════════════
// HERO HEADER
// ══════════════════════════════════════════════════════════════════════════════
class _HeroHeader extends StatelessWidget {
  final TutorialEntity tutorial;
  final Color catColor;
  const _HeroHeader({required this.tutorial, required this.catColor});

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      expandedHeight: 200,
      pinned: true,
      backgroundColor: context.cl.bg,
      elevation: 0,
      leading: Padding(
        padding: const EdgeInsets.all(8),
        child: GestureDetector(
          onTap: () => context.pop(),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.35),
              shape: BoxShape.circle),
            child: const Icon(Icons.arrow_back_ios_new_rounded,
                color: Colors.white, size: 18)),
        ),
      ),
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.parallax,
        background: Stack(children: [
          // Fond : thumbnail réseau ou gradient de couleur
          Positioned.fill(
            child: tutorial.thumbnailUrl != null
              ? Image.network(
                  tutorial.thumbnailUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => _HeaderGradient(catColor: catColor, bgColor: context.cl.bg),
                )
              : _HeaderGradient(catColor: catColor, bgColor: context.cl.bg),
          ),

          // Overlay dégradé bas pour lisibilité du texte
          Positioned.fill(child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.black54, Colors.black12, Colors.transparent],
                begin: Alignment.bottomCenter, end: Alignment.topCenter)),
          )),

          // Contenu texte
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Emoji catégorie (Hero depuis la card)
                  Hero(
                    tag: 'tutorial_thumb_${tutorial.id}',
                    child: Container(
                      width: 64, height: 64,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.3), width: 0.8)),
                      child: Center(child: Text(
                        tutorial.category.emoji,
                        style: const TextStyle(fontSize: 32))),
                    ),
                  ).animate()
                    .scale(begin: const Offset(0.55, 0.55), end: const Offset(1, 1),
                      duration: 500.ms, curve: Curves.easeOutBack)
                    .fadeIn(duration: 400.ms),
                  const SizedBox(height: 12),
                  Text(
                    tutorial.title,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700,
                        shadows: [Shadow(color: Colors.black38, blurRadius: 8, offset: Offset(0, 2))]),
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                  ).animate(delay: 120.ms)
                    .fadeIn(duration: 350.ms)
                    .slideY(begin: 0.12, end: 0, curve: Curves.easeOutCubic),
                ],
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _HeaderGradient extends StatelessWidget {
  final Color catColor, bgColor;
  const _HeaderGradient({required this.catColor, required this.bgColor});
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [catColor.withValues(alpha: 0.85), catColor.withValues(alpha: 0.4), bgColor],
        begin: Alignment.topCenter, end: Alignment.bottomCenter)),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// MÉTA ROW
// ══════════════════════════════════════════════════════════════════════════════
class _MetaRow extends StatelessWidget {
  final TutorialEntity tutorial;
  const _MetaRow({required this.tutorial});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          _MetaChip(
              icon: Icons.access_time_rounded,
              label: tutorial.durationText,
              color: AppColors.info),
          const SizedBox(width: 8),
          _MetaChip(
              icon: Icons.visibility_rounded,
              label: '${tutorial.viewCount} vues',
              color: context.cl.textM),
          const SizedBox(width: 8),
          _MetaChip(
              icon: Icons.star_rounded,
              label: tutorial.rating.toStringAsFixed(1),
              color: AppColors.warning),
        ],
      );
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _MetaChip(
      {required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: context.cl.surface,
          borderRadius: BorderRadius.circular(20),
          border:
              Border.all(color: context.cl.border, width: 0.5)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  color: context.cl.textS,
                  fontSize: 11,
                  fontWeight: FontWeight.w500)),
        ]),
      );
}

// ══════════════════════════════════════════════════════════════════════════════
// SECTION DIVIDER
// ══════════════════════════════════════════════════════════════════════════════
class _SectionDivider extends StatelessWidget {
  final String label;
  const _SectionDivider({required this.label});

  @override
  Widget build(BuildContext context) => Row(children: [
        Text(label.toUpperCase(),
            style: TextStyle(
                color: context.cl.textM,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8)),
        const SizedBox(width: 8),
        Expanded(child: Divider(color: context.cl.border, height: 1)),
      ]);
}

// ══════════════════════════════════════════════════════════════════════════════
// RENDERER MARKDOWN LÉGER
// ══════════════════════════════════════════════════════════════════════════════
class _MarkdownRenderer extends StatelessWidget {
  final String content;
  final Color catColor;
  const _MarkdownRenderer(
      {required this.content, required this.catColor});

  @override
  Widget build(BuildContext context) {
    final lines = content.split('\n');
    final widgets = <Widget>[];

    for (final raw in lines) {
      final line = raw;

      // H1
      if (line.startsWith('# ')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 8),
          child: Text(_stripInline(line.substring(2)),
              style: TextStyle(
                  color: context.cl.textP,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  height: 1.3)),
        ));
        continue;
      }

      // H2
      if (line.startsWith('## ')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 6),
          child: Text(_stripInline(line.substring(3)),
              style: TextStyle(
                  color: context.cl.textP,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  height: 1.3)),
        ));
        continue;
      }

      // H3
      if (line.startsWith('### ')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: Text(_stripInline(line.substring(4)),
              style: TextStyle(
                  color: context.cl.textP,
                  fontSize: 14,
                  fontWeight: FontWeight.w700)),
        ));
        continue;
      }

      // Blockquote
      if (line.startsWith('> ')) {
        widgets.add(Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: catColor.withValues(alpha: 0.07),
            borderRadius: const BorderRadius.only(
              topRight:    Radius.circular(8),
              bottomRight: Radius.circular(8)),
            border: Border(
                left: BorderSide(color: catColor, width: 3))),
          child: _InlineRichText(
              text: line.substring(2),
              baseStyle: TextStyle(
                  color: context.cl.textS,
                  fontSize: 14,
                  fontStyle: FontStyle.italic,
                  height: 1.6)),
        ));
        continue;
      }

      // Bullet
      if (line.startsWith('- ') ||
          line.startsWith('• ') ||
          line.startsWith('* ')) {
        final text = line.substring(2);
        widgets.add(Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 5),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 6, height: 6,
              margin: const EdgeInsets.only(top: 7, right: 10),
              decoration:
                  BoxDecoration(color: catColor, shape: BoxShape.circle)),
            Expanded(
              child: _InlineRichText(
                  text: text,
                  baseStyle: TextStyle(
                      color: context.cl.textS,
                      fontSize: 14,
                      height: 1.65)),
            ),
          ]),
        ));
        continue;
      }

      // Numbered list
      final numMatch = RegExp(r'^\d+\. (.+)').firstMatch(line);
      if (numMatch != null) {
        final num  = line.substring(0, line.indexOf('.'));
        final text = numMatch.group(1)!;
        widgets.add(Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 5),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 22, height: 22,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                color: catColor.withValues(alpha: 0.12),
                shape: BoxShape.circle),
              child: Center(child: Text(num,
                  style: TextStyle(
                      color: catColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w800)))),
            Expanded(
              child: _InlineRichText(
                  text: text,
                  baseStyle: TextStyle(
                      color: context.cl.textS,
                      fontSize: 14,
                      height: 1.65)),
            ),
          ]),
        ));
        continue;
      }

      // Divider
      if (line.trim() == '---' || line.trim() == '***') {
        widgets.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Divider(color: context.cl.border),
        ));
        continue;
      }

      // Ligne vide → espace
      if (line.trim().isEmpty) {
        widgets.add(const SizedBox(height: 8));
        continue;
      }

      // Paragraphe normal
      widgets.add(Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: _InlineRichText(
            text: line,
            baseStyle: TextStyle(
                color: context.cl.textS,
                fontSize: 14,
                height: 1.75)),
      ));
    }

    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: widgets);
  }

  String _stripInline(String s) =>
      s.replaceAll(RegExp(r'\*\*(.*?)\*\*'), r'$1')
       .replaceAll(RegExp(r'\*(.*?)\*'), r'$1')
       .replaceAll(RegExp(r'`(.*?)`'), r'$1');
}

/// Rend le texte inline avec **bold**, *italic*, `code`
class _InlineRichText extends StatelessWidget {
  final String    text;
  final TextStyle baseStyle;
  const _InlineRichText({required this.text, required this.baseStyle});

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(style: baseStyle, children: _parse(context, text)),
    );
  }

  List<InlineSpan> _parse(BuildContext context, String input) {
    final spans  = <InlineSpan>[];
    // Ordre : code, bold, italic
    final pattern = RegExp(r'`(.*?)`|\*\*(.*?)\*\*|\*(.*?)\*');
    int last = 0;

    for (final m in pattern.allMatches(input)) {
      if (m.start > last) {
        spans.add(TextSpan(text: input.substring(last, m.start)));
      }
      if (m.group(1) != null) {
        // `code`
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: context.cl.surfaceD,
              borderRadius: BorderRadius.circular(4)),
            child: Text(m.group(1)!,
                style: baseStyle.copyWith(
                    fontFamily: 'monospace',
                    fontSize: (baseStyle.fontSize ?? 14) - 1,
                    color: AppColors.primaryLight)),
          ),
        ));
      } else if (m.group(2) != null) {
        // **bold**
        spans.add(TextSpan(
            text: m.group(2),
            style: baseStyle.copyWith(
                fontWeight: FontWeight.w800,
                color: context.cl.textP)));
      } else if (m.group(3) != null) {
        // *italic*
        spans.add(TextSpan(
            text: m.group(3),
            style: baseStyle.copyWith(fontStyle: FontStyle.italic)));
      }
      last = m.end;
    }
    if (last < input.length) {
      spans.add(TextSpan(text: input.substring(last)));
    }
    return spans;
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// SECTION VIDÉO
// ══════════════════════════════════════════════════════════════════════════════
class _VideoSection extends StatelessWidget {
  final String url, duration;
  const _VideoSection({required this.url, required this.duration});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionDivider(label: 'Vidéo'),
          const SizedBox(height: 14),
          Container(
            height: 210,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF0A0E1A),
                  const Color(0xFF1C2545),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.25),
                  width: 0.8),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.10),
                  blurRadius: 20,
                  offset: const Offset(0, 6)),
              ],
            ),
            child: Stack(children: [
              // Fond décoratif
              Positioned.fill(
                child: CustomPaint(painter: _CircleBgPainter()),
              ),
              // Contenu centré
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 72, height: 72,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.4),
                          width: 1.5)),
                    child: const Icon(Icons.play_arrow_rounded,
                        color: Colors.white, size: 40))
                    .animate(onPlay: (c) => c.repeat(reverse: true))
                    .scale(begin: const Offset(1.0, 1.0), end: const Offset(1.09, 1.09),
                      duration: 1100.ms, curve: Curves.easeInOut),
                  const SizedBox(height: 12),
                  const Text('Lire la vidéo',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(duration,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 12)),
                ],
              ),
              // Badge durée haut droite
              Positioned(
                top: 12, right: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.videocam_rounded,
                        color: Colors.white70, size: 12),
                    const SizedBox(width: 4),
                    Text(duration,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600)),
                  ]),
                ),
              ),
            ]),
          ),
        ],
      );
}

class _CircleBgPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.05)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(size.width * 0.8, size.height * 0.2),
        80, paint);
    canvas.drawCircle(Offset(size.width * 0.1, size.height * 0.8),
        60, paint);
  }
  @override bool shouldRepaint(_) => false;
}

// ══════════════════════════════════════════════════════════════════════════════
// PREMIUM LOCK
// ══════════════════════════════════════════════════════════════════════════════
class _PremiumLock extends ConsumerWidget {
  final Color catColor;
  const _PremiumLock({required this.catColor});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(
        children: [
          // Aperçu flou du contenu
          Stack(
            children: [
              // Contenu "fantôme" flou
              ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _fakeTextLine(context, double.infinity),
                      const SizedBox(height: 8),
                      _fakeTextLine(context, double.infinity),
                      const SizedBox(height: 8),
                      _fakeTextLine(context, 200),
                      const SizedBox(height: 16),
                      _fakeTextLine(context, double.infinity),
                      const SizedBox(height: 8),
                      _fakeTextLine(context, 260),
                    ],
                  ),
                ),
              ),
              // Overlay + card premium
              Container(
                padding: const EdgeInsets.symmetric(vertical: 24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      context.cl.bg.withValues(alpha: 0.6),
                      context.cl.bg.withValues(alpha: 0.95),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                      child: Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: context.cl.surface.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: AppColors.warning.withValues(alpha: 0.4),
                              width: 1)),
                        child: Column(children: [
                          Container(
                            width: 64, height: 64,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFFB8860B), Color(0xFFFFD700)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight),
                              shape: BoxShape.circle,
                              boxShadow: [BoxShadow(
                                color: const Color(0xFFFFD700)
                                    .withValues(alpha: 0.3),
                                blurRadius: 16)]),
                            child: const Icon(Icons.workspace_premium_rounded,
                                color: Colors.white, size: 32)),
                          const SizedBox(height: 16),
                          const Text('Contenu Premium',
                              style: TextStyle(
                                  color: AppColors.warning,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800)),
                          const SizedBox(height: 8),
                          Text(
                            'Débloquez ce tutoriel et tous\nles contenus exclusifs avec Premium.',
                            style: TextStyle(
                                color: context.cl.textS,
                                fontSize: 13,
                                height: 1.5),
                            textAlign: TextAlign.center),
                          const SizedBox(height: 20),
                          GestureDetector(
                            onTap: () =>
                                goToPremium(context, ref),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                  vertical: 14),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFFB8860B),
                                    Color(0xFFFFD700)
                                  ]),
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: [BoxShadow(
                                  color: const Color(0xFFFFD700)
                                      .withValues(alpha: 0.3),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4))]),
                              child: const Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.workspace_premium_rounded,
                                      color: Colors.white, size: 18),
                                  SizedBox(width: 8),
                                  Text('Activer Premium — 5 000 FCFA',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w800)),
                                ]),
                            ).animate(onPlay: (c) => c.repeat())
                              .shimmer(duration: 2200.ms, delay: 800.ms, color: Colors.white24),
                          ),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      );

  Widget _fakeTextLine(BuildContext context, double width) => Container(
        height: 12, width: width,
        decoration: BoxDecoration(
          color: context.cl.borderS,
          borderRadius: BorderRadius.circular(6)));
}

// ══════════════════════════════════════════════════════════════════════════════
// PLACEHOLDER CONTENU VIDE
// ══════════════════════════════════════════════════════════════════════════════
class _PlaceholderContent extends StatelessWidget {
  final Color catColor;
  const _PlaceholderContent({required this.catColor});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: catColor.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: catColor.withValues(alpha: 0.2), width: 0.5)),
        child: Column(children: [
          const Text('📖', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 12),
          Text('Contenu en préparation',
              style: TextStyle(
                  color: context.cl.textP,
                  fontSize: 15,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('Ce tutoriel sera bientôt disponible.',
              style: TextStyle(color: context.cl.textS, fontSize: 13),
              textAlign: TextAlign.center),
        ]),
      );
}

// ══════════════════════════════════════════════════════════════════════════════
// AUTEUR
// ══════════════════════════════════════════════════════════════════════════════
class _AuthorCard extends StatelessWidget {
  final String name;
  const _AuthorCard({required this.name});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.cl.surface,
          borderRadius: BorderRadius.circular(14),
          border:
              Border.all(color: context.cl.border, width: 0.5)),
        child: Row(children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.primaryLight],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight),
              shape: BoxShape.circle),
            child: const Icon(Icons.person_rounded,
                color: Colors.white, size: 22)),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Rédigé par',
                  style: TextStyle(
                      color: context.cl.textM, fontSize: 11)),
              const SizedBox(height: 2),
              Text(name,
                  style: TextStyle(
                      color: context.cl.textP,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
            ])),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(20)),
            child: const Text('Expert',
                style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600))),
        ]),
      );
}

// ══════════════════════════════════════════════════════════════════════════════
// BOTTOM BAR — MARQUER COMME TERMINÉ
// ══════════════════════════════════════════════════════════════════════════════
class _BottomBar extends StatefulWidget {
  final bool       completed;
  final Animation<double> checkAnim;
  final Color      catColor;
  final VoidCallback onComplete;

  const _BottomBar({
    required this.completed,
    required this.checkAnim,
    required this.catColor,
    required this.onComplete,
  });

  @override
  State<_BottomBar> createState() => _BottomBarState();
}

class _BottomBarState extends State<_BottomBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _pressCtrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _pressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
      reverseDuration: const Duration(milliseconds: 150),
    );
    _scale = Tween(begin: 1.0, end: 0.97).animate(
      CurvedAnimation(parent: _pressCtrl, curve: Curves.easeOut));
  }

  @override
  void dispose() { _pressCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: EdgeInsets.fromLTRB(
              16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
          decoration: BoxDecoration(
            color: context.cl.bg.withValues(alpha: 0.85),
            border: Border(
                top: BorderSide(
                    color: context.cl.border, width: 0.5))),
          child: GestureDetector(
            onTapDown: widget.completed ? null : (_) => _pressCtrl.forward(),
            onTapUp: widget.completed ? null : (_) {
              _pressCtrl.reverse();
              HapticFeedback.mediumImpact();
              widget.onComplete();
            },
            onTapCancel: () => _pressCtrl.reverse(),
            child: ScaleTransition(scale: _scale, child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 15),
              decoration: BoxDecoration(
                gradient: widget.completed
                    ? const LinearGradient(
                        colors: [AppColors.success, Color(0xFF22C55E)])
                    : LinearGradient(
                        colors: [widget.catColor, widget.catColor.withValues(alpha: 0.8)]),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: (widget.completed ? AppColors.success : widget.catColor)
                        .withValues(alpha: 0.35),
                    blurRadius: 14,
                    offset: const Offset(0, 4)),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (widget.completed)
                    ScaleTransition(
                      scale: widget.checkAnim,
                      child: const Icon(Icons.check_circle_rounded,
                          color: Colors.white, size: 20))
                  else
                    const Icon(Icons.check_rounded,
                        color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    widget.completed ? 'Tutoriel terminé ✓' : 'Marquer comme terminé',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            )),
          ),
        ),
      ),
    );
  }
}

// ─── Tag ─────────────────────────────────────────────────────────────────────
class _Tag extends StatelessWidget {
  final String label;
  final Color  color;
  const _Tag({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
              color: color.withValues(alpha: 0.3), width: 0.5)),
        child: Text(label,
            style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w600)));
}

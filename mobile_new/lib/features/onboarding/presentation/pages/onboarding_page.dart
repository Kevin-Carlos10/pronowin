import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/router/app_router.dart' show onboardingDoneProvider;
import '../../../../core/theme/app_theme.dart';

// ─── Données slides ───────────────────────────────────────────────────────────
class _Slide {
  final String emoji;
  final String title;
  final String subtitle;
  final List<String> bullets;
  final Color color;
  final Color colorDark;

  const _Slide({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.bullets,
    required this.color,
    required this.colorDark,
  });
}

const _slides = [
  _Slide(
    emoji: '🏆',
    title: 'Bienvenue sur PronoWin',
    subtitle: 'L\'appli de pronostics sportifs N°1 en Afrique de l\'Ouest',
    bullets: [
      'Pronostics d\'experts chaque jour',
      'Analyses IA exclusives',
      'Communauté de parieurs sérieux',
    ],
    color: Color(0xFF6366F1),
    colorDark: Color(0xFF4338CA),
  ),
  _Slide(
    emoji: '🎯',
    title: 'Pronostics Experts',
    subtitle: 'Des pronostics analysés et validés par nos analystes',
    bullets: [
      'Football, basketball, tennis et plus',
      'Cotes recommandées et niveau de confiance',
      'Résultats en temps réel',
    ],
    color: AppColors.primary,
    colorDark: Color(0xFFB45309),
  ),
  _Slide(
    emoji: '🤖',
    title: 'Analyse IA Intégrée',
    subtitle: 'Notre algorithme calcule les probabilités pour chaque match',
    bullets: [
      'Score de probabilité basé sur l\'historique H2H',
      'Forme des équipes et avantage domicile',
      'Explication en français de chaque prédiction',
    ],
    color: AppColors.info,
    colorDark: Color(0xFF0369A1),
  ),
  _Slide(
    emoji: '📚',
    title: 'Formation & Tutoriels',
    subtitle: 'Apprends à parier intelligemment avec nos guides',
    bullets: [
      'Value Bet, Bankroll, Stratégie...',
      'Tutoriels vidéo et articles complets',
      'Contenu gratuit et premium disponible',
    ],
    color: AppColors.success,
    colorDark: Color(0xFF166534),
  ),
  _Slide(
    emoji: '💰',
    title: 'Gère ta bankroll',
    subtitle: 'Une bonne gestion du capital est la clé pour durer dans le temps',
    bullets: [
      'Définis ton budget de départ dans la section Bankroll',
      'Mise un % fixe — jamais tout sur un seul pari',
      'Suis ton ROI et ta progression en temps réel',
    ],
    color: Color(0xFF10B981),
    colorDark: Color(0xFF065F46),
  ),
  _Slide(
    emoji: '🚀',
    title: 'Prêt à commencer ?',
    subtitle: 'Rejoins des milliers de parieurs qui gagnent avec PronoWin',
    bullets: [
      'Accès gratuit à tous les pronostics du jour',
      'Premium pour les analyses exclusives',
      'Parrainage et récompenses à gagner',
    ],
    color: Color(0xFFEC4899),
    colorDark: Color(0xFF9D174D),
  ),
];

// ─── Page principale ──────────────────────────────────────────────────────────
class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  final _ctrl   = PageController();
  int  _current = 0;

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  void _next() {
    HapticFeedback.lightImpact();
    if (_current < _slides.length - 1) {
      _ctrl.nextPage(duration: const Duration(milliseconds: 380), curve: Curves.easeInOutCubic);
    } else {
      _finish();
    }
  }

  void _skip() {
    HapticFeedback.selectionClick();
    _finish();
  }

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_done', true);
    if (!mounted) return;
    ref.read(onboardingDoneProvider.notifier).state = true;
    context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final slide = _slides[_current];
    return Scaffold(
      backgroundColor: context.cl.bg,
      body: Stack(children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                slide.color.withValues(alpha: 0.12),
                slide.colorDark.withValues(alpha: 0.04),
                context.cl.bg,
              ],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
          ),
        ),
        Positioned(top: -60, right: -60,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            width: 220, height: 220,
            decoration: BoxDecoration(shape: BoxShape.circle,
              color: slide.color.withValues(alpha: 0.10)),
          )),
        Positioned(bottom: 80, left: -80,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            width: 260, height: 260,
            decoration: BoxDecoration(shape: BoxShape.circle,
              color: slide.colorDark.withValues(alpha: 0.07)),
          )),
        SafeArea(child: Column(children: [
          Align(alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.only(top: 8, right: 16),
              child: _current < _slides.length - 1
                  ? TextButton(onPressed: _skip,
                      child: Text('Passer', style: TextStyle(
                        color: context.cl.textM, fontSize: 14, fontWeight: FontWeight.w500)))
                  : const SizedBox(height: 40),
            )),
          Expanded(child: PageView.builder(
            controller: _ctrl,
            itemCount:  _slides.length,
            onPageChanged: (i) {
              HapticFeedback.selectionClick();
              setState(() => _current = i);
            },
            itemBuilder: (_, i) => _SlideContent(slide: _slides[i]),
          )),
          Padding(padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
            child: Column(children: [
              Row(mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_slides.length, (i) {
                  final active = i == _current;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 280),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: active ? 24 : 8, height: 8,
                    decoration: BoxDecoration(
                      color: active ? slide.color : context.cl.border,
                      borderRadius: BorderRadius.circular(4)),
                  );
                })),
              const SizedBox(height: 28),
              GestureDetector(
                onTap: _next,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [slide.color, slide.colorDark],
                      begin: Alignment.topLeft, end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [BoxShadow(
                      color: slide.color.withValues(alpha: 0.4),
                      blurRadius: 16, offset: const Offset(0, 6))],
                  ),
                  child: Center(child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(
                      _current < _slides.length - 1 ? 'Suivant' : 'Commencer !',
                      style: const TextStyle(color: Colors.white, fontSize: 16,
                          fontWeight: FontWeight.w700, letterSpacing: 0.3)),
                    const SizedBox(width: 8),
                    Icon(
                      _current < _slides.length - 1
                          ? Icons.arrow_forward_rounded
                          : Icons.rocket_launch_rounded,
                      color: Colors.white, size: 20),
                  ])),
                ),
              ),
            ])),
        ])),
      ]),
    );
  }
}

// ─── Contenu d'un slide ───────────────────────────────────────────────────────
class _SlideContent extends StatelessWidget {
  final _Slide slide;
  const _SlideContent({required this.slide});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Emoji dans un cercle coloré
          _EmojiOrb(emoji: slide.emoji, color: slide.color)
            .animate()
            .scale(
              begin: const Offset(0.7, 0.7),
              end:   const Offset(1.0, 1.0),
              duration: 450.ms,
              curve: Curves.easeOutBack,
            )
            .fadeIn(duration: 300.ms),

          const SizedBox(height: 32),

          // Titre
          Text(
            slide.title,
            style: TextStyle(
              color:      context.cl.textP,
              fontSize:   26,
              fontWeight: FontWeight.w800,
              height:     1.2,
              letterSpacing: -0.3,
            ),
            textAlign: TextAlign.center,
          ).animate().fadeIn(duration: 350.ms, delay: 80.ms)
           .slideY(begin: 0.1, end: 0, duration: 350.ms, delay: 80.ms),

          const SizedBox(height: 12),

          // Sous-titre
          Text(
            slide.subtitle,
            style: TextStyle(
              color:    context.cl.textS,
              fontSize: 15,
              height:   1.55,
            ),
            textAlign: TextAlign.center,
          ).animate().fadeIn(duration: 350.ms, delay: 140.ms),

          const SizedBox(height: 36),

          // Bullets
          ...slide.bullets.asMap().entries.map((e) =>
            _BulletRow(text: e.value, color: slide.color)
              .animate()
              .fadeIn(duration: 300.ms, delay: Duration(milliseconds: 200 + e.key * 80))
              .slideX(begin: -0.06, end: 0, duration: 300.ms, delay: Duration(milliseconds: 200 + e.key * 80)),
          ),
        ],
      ),
    );
  }
}

// ─── Orbe emoji ───────────────────────────────────────────────────────────────
class _EmojiOrb extends StatefulWidget {
  final String emoji;
  final Color  color;
  const _EmojiOrb({required this.emoji, required this.color});
  @override
  State<_EmojiOrb> createState() => _EmojiOrbState();
}

class _EmojiOrbState extends State<_EmojiOrb>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _float;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
    _float = Tween<double>(begin: -8, end: 8).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _float,
      builder: (_, child) => Transform.translate(
        offset: Offset(0, _float.value),
        child:  child,
      ),
      child: Container(
        width: 130, height: 130,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              widget.color.withValues(alpha: 0.25),
              widget.color.withValues(alpha: 0.08),
            ],
          ),
          border: Border.all(
            color: widget.color.withValues(alpha: 0.3),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color:      widget.color.withValues(alpha: 0.20),
              blurRadius: 30,
              spreadRadius: 4,
            ),
          ],
        ),
        child: Center(
          child: Text(widget.emoji, style: const TextStyle(fontSize: 58)),
        ),
      ),
    );
  }
}

// ─── Ligne bullet ──────────────────────────────────────────────────────────────
class _BulletRow extends StatelessWidget {
  final String text;
  final Color  color;
  const _BulletRow({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(
              color:  color.withValues(alpha: 0.12),
              shape:  BoxShape.circle,
              border: Border.all(color: color.withValues(alpha: 0.25), width: 0.8),
            ),
            child: Icon(Icons.check_rounded, color: color, size: 15),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color:      context.cl.textP,
                fontSize:   14,
                fontWeight: FontWeight.w500,
                height:     1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

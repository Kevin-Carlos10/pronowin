import 'package:flutter/material.dart';

class SplashScreen extends StatefulWidget {
  final Widget child;
  const SplashScreen({super.key, required this.child});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  bool _showSplash = true;
  late AnimationController _ctrl;
  late Animation<double> _logo, _fond;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    // Le logo part d'abord, puis le fond. Les deux s'effaçaient ensemble : à
    // mi-chemin, « PronoWin » flottait en transparence sur l'accueil, par-dessus
    // le compte à rebours (vidéo du 7 novembre 2026).
    _logo = Tween<double>(begin: 1, end: 0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0, 0.35, curve: Curves.easeOut),
      ),
    );
    _fond = Tween<double>(begin: 1, end: 0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.3, 1, curve: Curves.easeOut),
      ),
    );

    // L'écran de démarrage natif a déjà tenu pendant la restauration de la
    // session : 1,8 s de plus retardaient l'accueil pour rien.
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        _ctrl.forward().then((_) {
          if (mounted) setState(() => _showSplash = false);
        });
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_showSplash) return widget.child;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: [
          widget.child,
          FadeTransition(
            opacity: _fond,
            child: VueDemarrage(opaciteLogo: _logo),
          ),
        ],
      ),
    );
  }
}

/// Le logotype « PronoWin » sur fond nuit : l'écran de démarrage, repris par
/// l'écran de masquage (`main.dart`) pour qu'aucun des deux ne ressemble à un
/// verrou.
class VueDemarrage extends StatelessWidget {
  /// L'effacement du logo seul, avant celui du fond (démarrage).
  final Animation<double>? opaciteLogo;
  const VueDemarrage({super.key, this.opaciteLogo});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF0A0E1A),
      child: Center(
        child: FadeTransition(
          opacity: opaciteLogo ?? kAlwaysCompleteAnimation,
          child: RichText(
            textDirection: TextDirection.ltr,
            text: const TextSpan(
              style: TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.w900,
                letterSpacing: -1,
              ),
              children: [
                TextSpan(
                  text: 'Prono',
                  style: TextStyle(color: Colors.white),
                ),
                TextSpan(
                  text: 'Win',
                  style: TextStyle(color: Color(0xFFE5450A)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

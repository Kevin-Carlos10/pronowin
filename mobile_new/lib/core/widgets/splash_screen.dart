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
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _fade = Tween<double>(begin: 1, end: 0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));

    Future.delayed(const Duration(milliseconds: 1800), () {
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
      child: Stack(children: [
        widget.child,
        FadeTransition(opacity: _fade, child: const _SplashView()),
      ]),
    );
  }
}

class _SplashView extends StatelessWidget {
  const _SplashView();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF0A0E1A),
      child: Center(
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
    );
  }
}

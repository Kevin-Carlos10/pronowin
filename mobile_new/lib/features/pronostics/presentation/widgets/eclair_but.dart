import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/motion.dart';

/// Un but se voit : la zone du score s'illumine puis s'éteint en deux
/// secondes et demie, comme la ligne d'un match chez Sofascore (revue de
/// l'interface, 9 novembre 2026). Le chiffre changeait sans rien dire.
///
/// Seulement quand le total augmente entre deux affichages du même match : ni
/// au premier affichage, ni pour un but annulé. Rien si l'utilisateur a
/// réduit les animations.
class EclairBut extends StatefulWidget {
  final int? dom, ext;
  final Widget child;
  final BorderRadius rayon;

  const EclairBut({
    super.key,
    required this.dom,
    required this.ext,
    required this.child,
    this.rayon = const BorderRadius.all(Radius.circular(12)),
  });

  @override
  State<EclairBut> createState() => _EclairButState();
}

class _EclairButState extends State<EclairBut> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2500));

  @override
  void didUpdateWidget(EclairBut ancien) {
    super.didUpdateWidget(ancien);
    final connuAvant = ancien.dom != null && ancien.ext != null;
    final avant = (ancien.dom ?? 0) + (ancien.ext ?? 0);
    final apres = (widget.dom ?? 0) + (widget.ext ?? 0);
    if (connuAvant && apres > avant && !context.animationsReduites) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (context, enfant) {
      final intensite = _c.isAnimating ? 1 - Curves.easeIn.transform(_c.value) : 0.0;
      return DecoratedBox(
        key: intensite > 0 ? const Key('eclair-but') : null,
        decoration: BoxDecoration(
          color: context.cl.success.withValues(alpha: 0.30 * intensite),
          borderRadius: widget.rayon,
        ),
        child: enfant,
      );
    },
    child: widget.child,
  );
}

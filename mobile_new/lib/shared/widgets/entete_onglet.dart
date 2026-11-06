import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

/// Géométrie commune sous la zone sûre, pour les cinq onglets principaux.
const hauteurEnteteOnglet = 64.0;

class TitreOnglet extends StatelessWidget {
  const TitreOnglet(this.texte, {super.key});
  final String texte;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Text(texte, maxLines: 1, overflow: TextOverflow.ellipsis,
      style: TextStyle(color: context.cl.textP, fontSize: 28,
        fontWeight: FontWeight.w700, letterSpacing: -0.7, height: 1.15)),
  );
}

class ActionEntete extends StatelessWidget {
  const ActionEntete({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: 48, height: 48,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: context.cl.surface,
      shape: BoxShape.circle,
      border: Border.all(color: context.cl.border, width: 0.7),
    ),
    child: child,
  );
}

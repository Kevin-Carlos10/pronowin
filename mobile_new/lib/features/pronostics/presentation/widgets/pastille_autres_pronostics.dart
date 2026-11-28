import 'package:flutter/material.dart';
import 'package:pronowin/l10n/app_strings.dart';

import '../../../../core/theme/app_theme.dart';

/// « +1 prono » : le match a d'autres pronostics que celui de la carte
/// (plusieurs par match, 23 novembre 2026). Ils sont dans la fiche du match.
///
/// La même pastille sur les cartes des listes et sur celles de l'accueil.
class PastilleAutresPronostics extends StatelessWidget {
  final int nombre;
  const PastilleAutresPronostics({super.key, required this.nombre});

  /// Ce que le lecteur d'écran ajoute à l'annonce de la carte.
  static String annonce(BuildContext context, int nombre) => nombre > 0
      ? AppStrings.of(context).count(nombre,
          one: " {arg0} autre pronostic sur ce match.", other: " {arg0} autres pronostics sur ce match.")
      : '';

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('carte-autres-pronostics'),
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
    decoration: BoxDecoration(
      color: AppColors.primary.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(8)),
    child: Text(
      AppStrings.of(context).count(nombre, one: '+{arg0} prono', other: '+{arg0} pronos'),
      maxLines: 1,
      style: TextStyle(color: context.cl.accent, fontSize: 11, fontWeight: FontWeight.w700)),
  );
}

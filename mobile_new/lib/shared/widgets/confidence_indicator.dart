import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../features/pronostics/domain/entities/match_entity.dart';

/// Indicateur de confiance — **composant unique** de l'application.
///
/// Il en existait quatre implémentations, avec quatre échelles de libellés
/// différentes : un score de 4 s'affichait « Excellent », « Bon » ou « Fort »
/// selon l'écran. Le libellé et le pourcentage viennent désormais tous deux de
/// [MatchEntity], qui est la seule autorité sur la conversion.
class ConfidenceIndicator extends StatelessWidget {
  /// Score brut, de 1 à 5.
  final int score;

  /// Largeur de la jauge. Le libellé s'aligne dessus.
  final double width;

  /// Affiche le mot (« Excellent »…) au-dessus de la jauge.
  final bool showLabel;

  /// Remplace la jauge par le pourcentage équivalent (60 % … 95 %).
  /// Réservé aux emplacements mis en avant — carte héros, panneau de détail.
  final bool asPercent;

  const ConfidenceIndicator({
    super.key,
    required this.score,
    this.width = 48,
    this.showLabel = true,
    this.asPercent = false,
  });

  /// Vert au-dessus de 4, orange à 3, rouge en dessous. Le seuil suit la
  /// lecture métier : à partir de 4, le pronostic est considéré comme solide.
  static Color colorFor(int score) => score >= 4
      ? AppColors.success
      : score >= 3
          ? AppColors.warning
          : AppColors.error;

  @override
  Widget build(BuildContext context) {
    final couleur = colorFor(score);

    if (asPercent) {
      return TweenAnimationBuilder<double>(
        tween: Tween(
            begin: 0, end: MatchEntity.percentForConfidence(score).toDouble()),
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOutCubic,
        builder: (_, v, _) => Text('${v.round()} %',
            style: TextStyle(
                color: couleur, fontSize: 15, fontWeight: FontWeight.w800)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showLabel) ...[
          Text(MatchEntity.labelForConfidence(score),
              style: TextStyle(
                  color: couleur, fontSize: 9, fontWeight: FontWeight.w700)),
          const SizedBox(height: 3),
        ],
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: score.toDouble()),
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOutCubic,
          builder: (_, v, _) => SizedBox(
            width: width,
            height: 5,
            child: Row(
              children: List.generate(5, (i) {
                final remplissage = (v - i).clamp(0.0, 1.0);
                return Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    decoration: BoxDecoration(
                      color: remplissage > 0
                          ? couleur.withValues(alpha: 0.35 + 0.65 * remplissage)
                          : context.cl.borderS,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ],
    );
  }
}

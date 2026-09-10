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

  /// Affiche le mot (« Excellent »…) au-dessus du pourcentage.
  final bool showLabel;

  const ConfidenceIndicator({
    super.key,
    required this.score,
    this.showLabel = true,
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

    // La confiance s'affiche en pourcentage, partout.
    //
    // Ce widget rendait au choix un pourcentage ou une jauge de cinq segments,
    // selon un drapeau que chaque appelant réglait comme il l'entendait. Le
    // même score apparaissait donc « 80 % » sur un écran et « ▪▪▪▪▫ » sur le
    // suivant, sans qu'aucun des deux ne dise combien vaut un segment.
    //
    // Un pourcentage se compare, se retient et se recopie dans une
    // conversation. Une jauge, non.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showLabel) ...[
          Text(MatchEntity.labelForConfidence(score),
              style: TextStyle(
                  color: couleur, fontSize: 9, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
        ],
        TweenAnimationBuilder<int>(
          tween: IntTween(
              begin: 0, end: MatchEntity.percentForConfidence(score)),
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOutCubic,
          builder: (_, v, _) => Text('$v %',
              style: TextStyle(
                  color: couleur, fontSize: 15, fontWeight: FontWeight.w800)),
        ),
      ],
    );
  }
}

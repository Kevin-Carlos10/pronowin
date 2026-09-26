import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../features/pronostics/domain/entities/match_entity.dart';

/// Note éditoriale sur cinq. Aucun pourcentage de victoire n'est déduit.
class ConfidenceIndicator extends StatelessWidget {
  final int score;
  final bool showLabel;
  const ConfidenceIndicator({super.key, required this.score, this.showLabel = true});
  static Color colorFor(int score) => score >= 4 ? AppColors.success : score >= 3 ? AppColors.warning : AppColors.error;
  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Confiance de l’analyste : appréciation sur 5, pas une probabilité de gain.',
    child: Semantics(
      label: 'Confiance de l’analyste : ${MatchEntity.confidenceDisplay(score)}, ${MatchEntity.labelForConfidence(score)}',
      excludeSemantics: true,
      child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
        if (showLabel) ...[
          // Le libellé peut aller jusqu'à « Très élevée » : onze caractères
          // là où « Bon » en faisait trois. Il imposait au composant une
          // largeur que la rangée n'avait pas, et la carte débordait de 6,8 px
          // à 320 px / échelle 1,5 — sur les notes 1 et 5, c'est-à-dire sur
          // tous les pronostics à cinq étoiles, ceux qu'on met en avant.
          //
          // Le correctif tient entièrement dans le `Flexible` posé du côté de
          // la carte : la rangée cède de la place au lieu de déborder, et le
          // libellé se replie sur deux lignes. Vérifié en retirant tout le
          // reste — lui seul fait le travail, y compris sur « Non évaluée ».
          //
          // `textAlign` parce qu'il se replie, justement : sans lui la seconde
          // ligne se colle à gauche d'une colonne alignée à droite.
          //
          // Pas de `maxLines` ici. Il y en avait un, et la mesure a montré
          // qu'il ne servait à rien : avec ou sans, le libellé occupe 141 × 42
          // à l'échelle 1,5, qui est le plafond fixé par `maxScaleFactor` dans
          // `main.dart`. Un garde-fou dont la condition n'est jamais atteinte
          // rassure sans protéger — c'est précisément ce que ce dépôt traque.
          Text(
            MatchEntity.labelForConfidence(score),
            style: TextStyle(color: colorFor(score), fontSize: 10, fontWeight: FontWeight.w700),
            textAlign: TextAlign.end,
          ),
          const SizedBox(height: 2),
        ],
        Text(MatchEntity.confidenceDisplay(score), style: TextStyle(color: colorFor(score), fontSize: 15, fontWeight: FontWeight.w800)),
      ]),
    ),
  );
}

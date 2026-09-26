import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Le logotype « Prono**Win** » — source unique.
///
/// Il était réécrit à la main à six endroits (splash, en-tête d'accueil, écran
/// de verrouillage, paramètres, liste des pronostics, carte de partage), et les
/// copies avaient déjà divergé : `w800` ici, `w900` là, `letterSpacing` de -1,
/// de -0.5 ou absent, et un « Prono » tantôt en `Colors.white` — donc invisible
/// sur fond clair — tantôt en `textP`, qui suit le thème.
///
/// Une marque qui ne s'écrit pas deux fois pareil n'est plus tout à fait une
/// marque. Les paramètres ci-dessous couvrent les usages légitimes ; la forme,
/// elle, ne se négocie plus.
class LogotypePronoWin extends StatelessWidget {
  final double taille;

  /// Force le blanc au lieu de suivre le thème.
  ///
  /// Réservé aux fonds toujours sombres — un dégradé de marque, une image de
  /// partage — où `textP` deviendrait illisible en thème clair. Partout
  /// ailleurs, laisser la valeur par défaut.
  final bool surFondSombre;

  const LogotypePronoWin({
    super.key,
    this.taille = 24,
    this.surFondSombre = false,
  });

  @override
  Widget build(BuildContext context) {
    final couleurPrincipale =
        surFondSombre ? Colors.white : context.cl.textP;

    return RichText(
      // Le lecteur d'écran doit entendre « PronoWin », pas « Prono » puis
      // « Win » : deux fragments d'un même nom propre.
      text: TextSpan(
        style: TextStyle(
          fontSize: taille,
          fontWeight: FontWeight.w900,
          letterSpacing: -taille * 0.025,
          height: 1.1,
        ),
        children: [
          TextSpan(text: 'Prono', style: TextStyle(color: couleurPrincipale)),
          const TextSpan(text: 'Win', style: TextStyle(color: AppColors.primary)),
        ],
      ),
    );
  }
}

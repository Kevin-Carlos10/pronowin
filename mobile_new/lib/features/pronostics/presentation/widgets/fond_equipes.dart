import 'dart:ui' show ImageFilter, TileMode;

import 'package:flutter/material.dart';

/// Le fond de l'en-tête d'un match, teinté par les deux équipes, comme
/// Sofascore (vidéos du 8 novembre 2026).
///
/// Chez Sofascore, le score et les logos ne reposent pas sur un aplat : on
/// devine derrière eux les couleurs des deux clubs — rouge à gauche pour
/// Manchester United, bordeaux et bleu à droite pour Aston Villa — sous un
/// voile sombre. PronoWin posait le même dégradé bleu nuit sur tous les
/// matchs.
///
/// Plutôt que d'extraire une couleur de chaque logo, on dessine les logos
/// eux-mêmes, très agrandis, floutés et en transparence : la teinte vient
/// toute seule, avec ses nuances, et sans rien télécharger de plus.
///
/// Taille fixe (celle de l'en-tête déplié) : au repli, l'en-tête se contente
/// de la rogner. Rien n'est recalculé pendant le défilement.
class FondEquipes extends StatelessWidget {
  const FondEquipes({
    super.key,
    required this.domicile,
    required this.exterieur,
    required this.fond,
  });

  /// Les deux logos, tels qu'on les afficherait (TeamLogoWidget).
  final Widget domicile, exterieur;

  /// La couleur du voile, celle de l'en-tête.
  final Color fond;

  /// Part des logos qui transparaît sous le voile.
  static const opacite = 0.55;

  @override
  Widget build(BuildContext context) {
    // « Contraste élevé » : un aplat, sans couleur derrière le texte.
    if (MediaQuery.highContrastOf(context)) return ColoredBox(color: fond);
    return RepaintBoundary(
      child: IgnorePointer(
        child: ExcludeSemantics(
          child: LayoutBuilder(builder: (context, c) {
            final taille = c.maxWidth * 0.8;
            Widget halo(Widget logo, {required bool gauche}) => Positioned(
              key: Key(gauche ? 'halo-domicile' : 'halo-exterieur'),
              left: gauche ? -taille * 0.38 : null,
              right: gauche ? null : -taille * 0.38,
              top: -taille * 0.2,
              width: taille,
              height: taille,
              child: Opacity(
                opacity: opacite,
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 46, sigmaY: 46, tileMode: TileMode.decal),
                  child: FittedBox(child: SizedBox.square(dimension: 100, child: logo)),
                ),
              ),
            );
            return Stack(clipBehavior: Clip.hardEdge, children: [
              Positioned.fill(child: ColoredBox(color: fond)),
              halo(domicile, gauche: true),
              halo(exterieur, gauche: false),
              // Le voile : le texte reste lisible, et le bas rejoint la barre
              // d'onglets sans cassure.
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [fond.withValues(alpha: 0.2), fond.withValues(alpha: 0.75)],
                    ),
                  ),
                ),
              ),
            ]);
          }),
        ),
      ),
    );
  }
}

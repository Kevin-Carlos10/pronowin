import 'package:flutter/widgets.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// Nombre d'éléments d'une liste qui portent l'animation d'entrée.
///
/// Environ une hauteur d'écran. Au-delà, personne ne verra jamais l'animation
/// démarrer : elle ne coûterait qu'un contrôleur de plus, et — plus grave —
/// elle empêcherait la liste d'être paresseuse. Une carte construite au moment
/// où elle entre à l'écran resterait vide le temps d'un délai déjà écoulé.
const int elementsAnimes = 8;

/// Pas entre deux entrées successives. `(elementsAnimes - 1) * pas` doit rester
/// sous la demi-seconde : au-delà, l'écran paraît lent au lieu de paraître vif.
const int pasEntreeMs = 45;

/// Respect du réglage système « Réduire les animations » (iOS) /
/// « Supprimer les animations » (Android).
///
/// Ce réglage n'est pas un confort : il existe pour les personnes sujettes au
/// mal des transports vestibulaire, chez qui un mouvement répété à l'écran
/// provoque nausées et vertiges. Les deux plateformes le relèvent en revue.
///
/// La règle appliquée dans l'app :
///
/// * les animations **en boucle** (pulsation, halo, scintillement) et les
///   effets **festifs** (célébration d'un pronostic gagnant) sont supprimés —
///   ce sont eux qui posent problème ;
/// * les transitions **ponctuelles et courtes** (apparition d'une carte,
///   remplissage d'une jauge) sont réduites à une durée quasi nulle plutôt que
///   supprimées, pour que l'état final reste identique.
extension MotionContext on BuildContext {
  /// true quand l'utilisateur a demandé moins de mouvement à l'écran.
  bool get animationsReduites =>
      MediaQuery.maybeDisableAnimationsOf(this) ?? false;

  /// Durée à utiliser pour une transition ponctuelle : la durée demandée, ou
  /// une durée imperceptible si l'utilisateur a réduit les animations.
  Duration duree(Duration voulue) =>
      animationsReduites ? Duration.zero : voulue;

  /// Entrée en cascade d'un élément de liste, **bornée par sa position**.
  ///
  /// Les listes de l'application portaient chacune leur propre formule —
  /// `palier + ligue×80 + rang×60`, `80 + rang×70`, `rang×60` — toutes
  /// croissantes sans limite. Une carte en fin de liste attendait plus d'une
  /// seconde et demie avant d'apparaître, hors écran, pour personne.
  ///
  /// Au-delà de [elementsAnimes], l'élément est rendu tel quel : c'est aussi
  /// ce qu'il faut quand il arrive par défilement.
  Widget entree(Widget enfant, int index) {
    if (index >= elementsAnimes || animationsReduites) return enfant;

    return enfant
        .animate(delay: Duration(milliseconds: index * pasEntreeMs))
        .fadeIn(duration: const Duration(milliseconds: 250))
        .slideY(
          begin: 0.06, end: 0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
        );
  }

  /// Met un [AnimationController] en boucle, sauf si l'utilisateur a réduit
  /// les animations — auquel cas il est figé sur sa valeur finale.
  ///
  /// À appeler en tête de `build`. Idempotent grâce au test `isAnimating`, il
  /// réagit donc aussi au changement du réglage sans redémarrer la page.
  /// Le figer sur `1` plutôt que sur `0` est délibéré : ces boucles animent
  /// presque toujours une opacité ou une échelle, dont la valeur haute est
  /// l'état lisible (pastille pleinement visible, halo à sa taille normale).
  void boucler(AnimationController c, {bool reverse = false}) {
    if (animationsReduites) {
      if (c.isAnimating) c.stop();
      c.value = 1;
    } else if (!c.isAnimating) {
      c.repeat(reverse: reverse);
    }
  }
}

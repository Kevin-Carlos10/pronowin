import 'dart:ui' show ImageFilter;

import 'package:flutter/widgets.dart';

import '../utils/motion.dart';

/// Un nombre dont les chiffres changent avec l'effet d'iOS : seul le chiffre
/// qui change bascule verticalement, flouté et un peu rétréci, pendant que le
/// nouveau arrive net — l'équivalent de `.contentTransition(.numericText())`
/// en SwiftUI.
///
/// Écrit pour le compte à rebours de l'accueil (retour de l'utilisateur du
/// 17 octobre 2026 : l'effet « quand les secondes changent » n'était pas celui
/// d'iOS). L'ancien faisait glisser le nombre entier, les deux chiffres
/// ensemble, toutes les secondes.
///
/// [descendant] : vrai pour un décompte. Le nouveau chiffre arrive alors par le
/// haut et l'ancien sort par le bas, comme sur iOS quand le nombre diminue.
class ChiffresIos extends StatelessWidget {
  final String texte;
  final TextStyle style;
  final bool descendant;

  const ChiffresIos(this.texte, {super.key, required this.style, this.descendant = true});

  /// Durée de la bascule d'un chiffre.
  static const duree = Duration(milliseconds: 420);

  @override
  Widget build(BuildContext context) {
    // Chiffres à chasse fixe : un « 1 » plus étroit qu'un « 8 » ferait
    // bouger tout le nombre à chaque changement.
    final s = style.copyWith(fontFeatures: [
      ...?style.fontFeatures,
      const FontFeature.tabularFigures(),
    ]);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < texte.length; i++)
        // La clé suit la position depuis la droite : quand « 10 » devient
        // « 9 », c'est le chiffre des unités qui bascule, pas celui de gauche.
        _Chiffre(
          key: ValueKey(texte.length - i),
          caractere: texte[i],
          style: s,
          descendant: descendant,
          reduit: context.animationsReduites,
        ),
    ]);
  }
}

class _Chiffre extends StatelessWidget {
  static const _courbe = Cubic(0.2, 0.9, 0.25, 1);

  final String caractere;
  final TextStyle style;
  final bool descendant, reduit;

  const _Chiffre({
    super.key,
    required this.caractere,
    required this.style,
    required this.descendant,
    required this.reduit,
  });

  @override
  Widget build(BuildContext context) {
    final texte = Text(caractere, key: ValueKey(caractere), style: style);
    if (reduit) return texte;
    return AnimatedSwitcher(
      duration: ChiffresIos.duree,
      // Amorti sans rebond, comme les ressorts par défaut d'iOS. La sortie
      // joue la courbe à l'envers (`flipped`) : sans cela, l'ancien chiffre
      // ne partait qu'à la fin et se superposait au nouveau.
      switchInCurve: _courbe,
      switchOutCurve: _courbe.flipped,
      layoutBuilder: (actuel, anciens) => Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [...anciens, ?actuel],
      ),
      transitionBuilder: (enfant, animation) {
        final entrant = enfant.key == ValueKey(caractere);
        // L'entrant arrive du côté opposé à celui par où l'ancien sort.
        final depart = (entrant == descendant) ? -0.55 : 0.55;
        return AnimatedBuilder(
          animation: animation,
          child: enfant,
          builder: (context, enfant) {
            final t = animation.value; // 0 → 1 à l'entrée, 1 → 0 à la sortie
            final flou = (1 - t) * 5;
            return FractionalTranslation(
              translation: Offset(0, depart * (1 - t)),
              child: Transform.scale(
                scale: 0.72 + 0.28 * t,
                child: Opacity(
                  // L'ancien s'efface plus vite que le nouveau n'apparaît :
                  // les deux ne se superposent qu'un instant.
                  opacity: (entrant ? t : t * t).clamp(0.0, 1.0),
                  child: flou < 0.05
                      ? enfant
                      : ImageFiltered(
                          imageFilter: ImageFilter.blur(sigmaX: flou * 0.4, sigmaY: flou),
                          child: enfant,
                        ),
                ),
              ),
            );
          },
        );
      },
      child: texte,
    );
  }
}

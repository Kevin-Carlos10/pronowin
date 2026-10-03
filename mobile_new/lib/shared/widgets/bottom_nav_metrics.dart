import 'package:flutter/widgets.dart';

/// Géométrie de la barre de navigation du bas, en un seul endroit.
///
/// `MainScaffold` déclare `extendBody: true` : le contenu des pages passe
/// **derrière** la barre au lieu de s'arrêter avant elle. Chaque page à
/// défilement doit donc réserver elle-même, en bas, la place que la barre
/// occupe — sinon sa dernière ligne se retrouve masquée.
///
/// Cette place n'est pas une constante : elle vaut la hauteur de la barre, plus
/// sa marge basse, plus l'encoche inférieure de l'appareil (34 px sur un iPhone
/// à barre d'accueil, ~24 px en navigation gestuelle Android, 0 avec des
/// boutons physiques). Les pages posaient jusqu'ici un nombre écrit à la main —
/// 80 sur Compte, 100 ailleurs, 110 sur Accueil — et celui de Compte était trop
/// court de 22 px sur iPhone : la ligne « Membre depuis… » passait sous la
/// barre.
///
/// Utiliser [bottomNavSpace] plutôt qu'un nombre écrit à la main garde les
/// pages justes quand la barre change de taille, et sur les appareils dont
/// l'encoche diffère de celle du simulateur.
class BottomNavMetrics {
  const BottomNavMetrics._();

  /// Taille du libellé sous chaque icône.
  ///
  /// Il valait 10, et la barre entière tombait à 82 % au défilement : le
  /// libellé se lisait alors autour de 8 px et la cible perdait près d'un
  /// cinquième de sa surface — sur l'élément qu'on touche le plus souvent, et
  /// souvent d'une seule main.
  static const double taillePolice = 11.5;

  /// Hauteur de la barre, à l'échelle de texte de l'appareil.
  ///
  /// Elle valait 64 en dur. Quelqu'un ayant agrandi les caractères de son
  /// système voyait donc le libellé grandir dans une barre qui, elle, ne
  /// bougeait pas — jusqu'au débordement.
  ///
  /// Elle est lue par la barre **et** par [bottomNavSpace] : les listes
  /// réservent ainsi d'elles-mêmes la place réelle, sans qu'aucune page n'ait
  /// à être retouchée.
  static double hauteur(BuildContext context) {
    final rendue = MediaQuery.textScalerOf(context).scale(taillePolice);
    return _hauteurBase + (rendue - taillePolice) * 1.3;
  }

  static const double _hauteurBase = 64;

  /// Marge sous la barre, entre elle et l'encoche.
  static const double margeBasse = 4;
}

/// Place à réserver en bas d'une liste défilante pour que son dernier élément
/// reste entièrement visible au-dessus de la barre de navigation.
///
/// Le [supplement] ajoute une respiration au-delà du strict nécessaire : sans
/// lui, le dernier élément affleure la barre au lieu de s'en détacher.
double bottomNavSpace(BuildContext context, {double supplement = 16}) =>
    BottomNavMetrics.hauteur(context) +
    BottomNavMetrics.margeBasse +
    MediaQuery.of(context).padding.bottom +
    supplement;

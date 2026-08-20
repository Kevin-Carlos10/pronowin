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

  /// Hauteur de la barre elle-même (le `Container` flouté).
  static const double hauteur = 64;

  /// Marge sous la barre, entre elle et l'encoche.
  static const double margeBasse = 4;
}

/// Place à réserver en bas d'une liste défilante pour que son dernier élément
/// reste entièrement visible au-dessus de la barre de navigation.
///
/// Le [supplement] ajoute une respiration au-delà du strict nécessaire : sans
/// lui, le dernier élément affleure la barre au lieu de s'en détacher.
double bottomNavSpace(BuildContext context, {double supplement = 16}) =>
    BottomNavMetrics.hauteur +
    BottomNavMetrics.margeBasse +
    MediaQuery.of(context).padding.bottom +
    supplement;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// La nature d'un message : elle fixe sa couleur et son icône.
enum TypeMessage { succes, erreur, alerte, info }

/// Affiche un message en bas d'écran — la seule façon de le faire.
///
/// Une quarantaine de `SnackBar` étaient construits à la main, chacun avec sa
/// couleur. Les fonds vifs portaient du texte blanc illisible (succès sur
/// #22C55E : 2,28:1 ; alerte sur #F59E0B : 2,15:1), et trois écrans
/// affichaient encore ces teintes vives en thème sombre. Ici :
///
///   · succès, erreur et alerte sur des fonds pleins où le blanc dépasse 5:1
///     dans les deux thèmes ;
///   · l'information sur la surface inverse du thème, comme Material ;
///   · une icône en plus de la couleur : le type ne repose pas sur elle seule ;
///   · le message précédent est retiré, ils ne s'empilent plus.
void afficherMessage(
  BuildContext context,
  String texte, {
  TypeMessage type = TypeMessage.info,
  Duration? duree,
  Key? cle,
  SnackBarAction? action,
}) {
  final messager = ScaffoldMessenger.maybeOf(context);
  if (messager == null) return;
  afficherMessageVia(messager, texte, type: type, duree: duree, cle: cle, action: action);
}

/// Même chose, avec un messager obtenu **avant** une attente.
///
/// Après un `await`, l'écran qui a lancé l'action peut avoir disparu : son
/// `context` n'est plus utilisable, le messager de l'application, si.
void afficherMessageVia(
  ScaffoldMessengerState? messager,
  String texte, {
  TypeMessage type = TypeMessage.info,
  Duration? duree,
  Key? cle,
  SnackBarAction? action,
}) {
  if (messager == null || !messager.mounted) return;
  final schema = Theme.of(messager.context).colorScheme;
  final (fond, icone) = switch (type) {
    TypeMessage.succes => (AppColors.fondSucces, Icons.check_circle_rounded),
    TypeMessage.erreur => (AppColors.fondErreur, Icons.error_rounded),
    TypeMessage.alerte => (AppColors.fondAlerte, Icons.warning_amber_rounded),
    TypeMessage.info   => (schema.inverseSurface, Icons.info_rounded),
  };
  final encre = type == TypeMessage.info ? schema.onInverseSurface : Colors.white;
  messager
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      key: cle,
      backgroundColor: fond,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      duration: duree ?? const Duration(seconds: 4),
      action: action == null
          ? null
          : SnackBarAction(label: action.label, onPressed: action.onPressed, textColor: encre),
      content: Row(children: [
        Icon(icone, color: encre, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(texte, style: TextStyle(color: encre))),
      ]),
    ));
}

import 'package:flutter/material.dart';
import 'package:pronowin/l10n/app_strings.dart';

/// Attend que des chargements relancés soient revenus.
///
/// `ref.invalidate` rend la main tout de suite. Un `onRefresh` qui s'arrête là
/// ferme l'indicateur avant le retour de la moindre donnée : le geste paraît
/// n'avoir servi à rien, puis l'écran change tout seul une seconde plus tard.
/// Et `onRefresh: () async {}` — Performance, Statistiques — ne relançait
/// carrément rien.
///
/// Renvoie `false` si l'un des chargements a échoué. L'erreur est absorbée :
/// la laisser remonter ferait échouer le geste au lieu de le terminer.
Future<bool> attendreChargements(Iterable<Future<Object?>> chargements) async {
  var reussi = true;
  await Future.wait(chargements.map((f) => f.then<void>((_) {}, onError: (Object _) {
        reussi = false;
      })));
  return reussi;
}

/// Dit que l'actualisation a échoué, sans retirer ce qui est déjà affiché.
void signalerActualisationImpossible(BuildContext context) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(tr(context, "Actualisation impossible. Vérifie ta connexion, puis réessaie.")),
    ));
}

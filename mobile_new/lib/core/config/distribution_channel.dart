import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Canal de distribution du build.
///
/// Vaut `true` pour les builds publiés sur l'App Store ou Google Play. Ce
/// drapeau ne relève pas de l'abonnement seul : il conditionne aussi ce que
/// l'app a le droit de montrer. Les deux stores encadrent strictement
/// l'incitation aux jeux d'argent et le paiement hors achat intégré.
///
/// Ce qu'il gouverne aujourd'hui :
///  - paywall  : achat intégré au lieu du Mobile Money (Apple 3.1.1) ;
///  - prix     : tarif majoré de 50 % pour absorber la commission ;
///  - bankroll : renvoi vers le bookmaker masqué (politique jeux d'argent).
///
/// À passer au build :
///   flutter build appbundle --dart-define=STORE_BUILD=true
///   flutter build apk       --dart-define=STORE_BUILD=false
///
/// iOS est toujours un build store en pratique — il n'existe pas de
/// distribution hors App Store, donc on force la valeur.
final isStoreBuildProvider = Provider<bool>((ref) {
  if (Platform.isIOS) return true;
  return const bool.fromEnvironment('STORE_BUILD', defaultValue: false);
});

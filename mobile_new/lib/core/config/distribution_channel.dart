import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Canal de distribution du build.
///
/// Ce drapeau ne relève pas de l'abonnement seul : il conditionne aussi ce que
/// l'app a le droit de montrer. Les deux stores encadrent strictement
/// l'incitation aux jeux d'argent et le paiement hors achat intégré.
///
/// Ce qu'il gouverne :
///  - paywall  : achat intégré au lieu du Mobile Money (Apple 3.1.1) ;
///  - prix     : tarif majoré pour absorber la commission ;
///  - bankroll : renvoi vers le bookmaker masqué (politique jeux d'argent) ;
///  - offre d'affiliation « code promo » masquée (même politique) ;
///  - mise à jour : renvoi vers le store, ou vers l'APK pour le canal direct.
///
/// ── Pourquoi le défaut penche du côté « store » ────────────────────────────
///
/// La valeur par défaut était `false`. Un build lancé sans le drapeau
/// produisait donc un binaire « direct » : Mobile Money actif, renvoi
/// bookmaker visible, remise de 30 % contre l'ouverture d'un compte 1xBet.
/// Envoyé sur Play par distraction, ce n'était pas une mise à jour refusée
/// mais un motif de retrait d'application.
///
/// Il n'existe pas de défaut inoffensif ici. On choisit donc celui dont
/// l'échec est bruyant et réparable plutôt que silencieux et sanctionné :
///
///   drapeau oublié → build « store » → l'APK direct propose un achat intégré
///   indisponible. C'est cassé, ça se voit au premier lancement, et ça ne
///   viole aucune politique.
///
/// À passer au build — `tool/build.ps1` le fait pour vous :
///   flutter build appbundle --dart-define=STORE_BUILD=true
///   flutter build apk       --dart-define=STORE_BUILD=false
///
/// iOS est toujours un build store en pratique — il n'existe pas de
/// distribution hors App Store, donc on force la valeur.

/// Canal par lequel ce binaire a été distribué.
enum CanalDistribution {
  /// App Store ou Google Play : achat intégré obligatoire, aucune mention
  /// de bookmaker, mise à jour par le store.
  store,

  /// APK téléchargé depuis le site : Mobile Money, affiliation autorisée,
  /// mise à jour par téléchargement direct.
  direct,
}

const String _drapeau = String.fromEnvironment('STORE_BUILD');

/// `true` si `STORE_BUILD` a été passé explicitement à la compilation.
///
/// Sert au diagnostic : un build de production dont ce booléen est faux a été
/// fabriqué sans choisir son canal, et son comportement relève du défaut de
/// sécurité plutôt que d'une décision.
const bool canalExplicite = _drapeau == 'true' || _drapeau == 'false';

var _averti = false;

final canalDistributionProvider = Provider<CanalDistribution>((ref) {
  if (Platform.isIOS) return CanalDistribution.store;

  if (kDebugMode && !canalExplicite && !_averti) {
    _averti = true;
    debugPrint(
      '[PronoWin] STORE_BUILD non défini — ce build est traité comme un build '
      'store (défaut de sécurité). Pour un APK direct : '
      '--dart-define=STORE_BUILD=false',
    );
  }

  // Seul un « false » explicite ouvre le canal direct. Tout le reste — valeur
  // absente, vide ou mal orthographiée — retombe sur le canal store.
  return _drapeau == 'false' ? CanalDistribution.direct : CanalDistribution.store;
});

final isStoreBuildProvider = Provider<bool>(
  (ref) => ref.watch(canalDistributionProvider) == CanalDistribution.store,
);

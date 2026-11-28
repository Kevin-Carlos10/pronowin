import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// L'application iPhone, sans aucune fonction de pari.
///
/// Apple a refusé la 1.0.16 le 11 octobre 2026 : un compte de développeur
/// individuel ne peut plus distribuer d'application de jeu d'argent, même
/// simulé. Le suivi des mises (Bankroll), le bouton qui enregistre une
/// sélection et l'affichage des cotes suffisaient à classer PronoWin ainsi.
///
/// Sur iPhone, PronoWin est donc un service de pronostics, d'analyses et de
/// statistiques de football : ni mise, ni cote, ni bankroll, ni tutoriel de
/// stratégie de pari. Android — Google Play et APK direct — ne change pas.
///
/// Un seul interrupteur, lu partout, plutôt qu'un test de plateforme répété
/// dans chaque écran : les bancs d'essai le forcent pour vérifier, sur
/// Windows, ce que verra un iPhone.
///
/// ── Remis sur iPhone, par la compilation (26 novembre 2026) ───────────────
///
/// L'utilisateur ne soumet pas à Apple pour le moment, et veut le volet pari
/// sur iPhone aussi (cotes, bankroll, alerte de couverture). Il revient par
/// un interrupteur de compilation, pas par le serveur : une fonction masquée
/// à distance pendant l'examen d'Apple serait une fonction cachée (règle
/// 2.3.1). Par défaut, l'iPhone reste sans pari ; le build Codemagic passe
/// `--dart-define=SANS_PARI_IOS=false`. Avant toute soumission à Apple :
/// retirer cette valeur de codemagic.yaml (variable SANS_PARI_IOS).
const sansPariIos = bool.fromEnvironment('SANS_PARI_IOS', defaultValue: true);

final sansPariProvider = Provider<bool>((ref) => Platform.isIOS && sansPariIos);

/// [sansPariProvider] lu depuis un widget qui n'a pas de `ref`. La valeur ne
/// change pas pendant la vie de l'application : rien à écouter.
bool sansPari(BuildContext context) =>
    ProviderScope.containerOf(context, listen: false).read(sansPariProvider);

/// Les catégories de tutoriels qui enseignent à parier : absentes sur iPhone.
const categoriesTutorielsPari = {'valuebet', 'bankroll', 'martingale', 'trading'};

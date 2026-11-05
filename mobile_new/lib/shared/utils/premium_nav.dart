import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/config/distribution_channel.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';

/// « Compléter le profil » (prénom, nom, date de naissance, téléphone) avant
/// l'écran Premium : seulement dans l'APK direct, qui paie par Mobile Money.
///
/// Sur l'App Store et Google Play, le paywall s'ouvre directement (refus
/// Apple du 2 novembre 2026) : le relecteur, venu tester l'abonnement, est
/// tombé sur ce formulaire, et un achat intégré n'a besoin d'aucune de ces
/// informations (règle 5.1.1).
bool profilACompleterAvantPremium(WidgetRef ref) {
  if (ref.read(isStoreBuildProvider)) return false;
  final authState = ref.read(authProvider);
  return authState is AuthAuthenticated && !authState.user.isProfileComplete;
}

/// Navigue vers le premium, en passant d'abord par la complétion du profil
/// quand elle est requise.
void goToPremium(BuildContext context, WidgetRef ref, {Map<String, dynamic>? extra}) {
  if (profilACompleterAvantPremium(ref)) {
    // La destination est passée en `extra` : sans elle, l'utilisateur qui
    // vient de remplir son profil retombait sur l'écran d'où il venait au
    // lieu du paywall qu'il cherchait à atteindre.
    context.push('/compte/completer-profil', extra: '/compte/activer-premium');
  } else {
    context.push('/compte/activer-premium', extra: extra);
  }
}

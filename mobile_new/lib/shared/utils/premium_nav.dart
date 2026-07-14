import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';

/// Navigue vers le premium si le profil est complet,
/// sinon redirige vers la page de complétion de profil.
void goToPremium(BuildContext context, WidgetRef ref, {Map<String, dynamic>? extra}) {
  final authState = ref.read(authProvider);
  if (authState is AuthAuthenticated && !authState.user.isProfileComplete) {
    context.push('/compte/completer-profil');
  } else {
    context.push('/compte/activer-premium', extra: extra);
  }
}

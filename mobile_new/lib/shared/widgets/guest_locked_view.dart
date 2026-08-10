import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';

/// Écran affiché à la place d'un onglet réservé (Bankroll, Compte) quand
/// l'utilisateur navigue en invité — évite de construire la vraie page
/// (et ses appels API authentifiés) tant qu'il n'est pas connecté.
class GuestLockedView extends StatelessWidget {
  final IconData icon;
  final String   title;
  final String   message;
  final String   from;
  // Lien secondaire optionnel vers du contenu réellement accessible sans
  // compte (ex. Paramètres/CGU) — évite de bloquer un invité sur des pages
  // que le routeur autorise déjà en mode invité.
  final String?  secondaryLabel;
  final String?  secondaryRoute;

  const GuestLockedView({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    required this.from,
    this.secondaryLabel,
    this.secondaryRoute,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: secondaryRoute != null
          ? AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              automaticallyImplyLeading: false,
              actions: [
                IconButton(
                  tooltip: secondaryLabel,
                  icon: Icon(Icons.settings_rounded, color: context.cl.textS),
                  onPressed: () => context.push(secondaryRoute!),
                ),
              ],
            )
          : null,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 84, height: 84,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.primary, AppColors.primaryLight],
                      begin: Alignment.topLeft, end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.35),
                      blurRadius: 20, offset: const Offset(0, 8))]),
                  child: Icon(icon, color: Colors.white, size: 38),
                ),
                const SizedBox(height: 24),
                Text(title, textAlign: TextAlign.center, style: TextStyle(
                  color: context.cl.textP, fontSize: 19, fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                Text(message, textAlign: TextAlign.center, style: TextStyle(
                  color: context.cl.textS, fontSize: 13.5, height: 1.5)),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity, height: 52,
                  child: ElevatedButton(
                    onPressed: () => context.push('/auth/email?from=${Uri.encodeComponent(from)}'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                    child: const Text('Se connecter / Créer un compte',
                      style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

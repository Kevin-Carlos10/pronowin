import 'package:pronowin/l10n/app_strings.dart';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/date_formatter.dart';

/// Ce qu'on montre après un achat sur l'App Store ou Google Play.
///
/// L'achat intégré réutilisait la confirmation du Mobile Money : « Preuve
/// soumise ! Ta demande est en cours de vérification », « Activation sous
/// immédiate », « Compris, j'attends la validation » — alors que le serveur
/// venait de vérifier l'achat auprès du store et d'activer le Premium.
/// L'acheteur, et l'examinateur d'Apple, lisaient qu'il fallait attendre
/// quelque chose qui était déjà fait.
class ConfirmationPremiumActive extends StatelessWidget {
  const ConfirmationPremiumActive({super.key, required this.expireLe, required this.onContinuer});

  /// La fin de la période payée, telle que le store l'a confirmée.
  final DateTime expireLe;
  final VoidCallback onContinuer;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: context.cl.bg,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
    ),
    padding: const EdgeInsets.fromLTRB(24, 12, 24, 36),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 40, height: 4,
        decoration: BoxDecoration(color: context.cl.border, borderRadius: BorderRadius.circular(2))),
      const SizedBox(height: 28),
      Container(
        width: 72, height: 72,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: AppColors.degradeMarque,
            begin: Alignment.topLeft, end: Alignment.bottomRight),
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.4), blurRadius: 20, offset: const Offset(0, 8))],
        ),
        child: const Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 36),
      ),
      const SizedBox(height: 20),
      Text(tr(context, "Premium activé !"), textAlign: TextAlign.center,
        style: TextStyle(color: context.cl.textP, fontSize: 22, fontWeight: FontWeight.w800)),
      const SizedBox(height: 10),
      Text(tr(context, "Tous les pronostics VIP et l'analyse statistique de chaque match sont débloqués."),
        textAlign: TextAlign.center,
        style: TextStyle(color: context.cl.textS, fontSize: 14, height: 1.4)),
      const SizedBox(height: 16),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.cl.success.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.cl.success.withValues(alpha: 0.25))),
        child: Text(
          tr(context, "Actif jusqu'au {arg0}, renouvelé automatiquement. Résiliable à tout moment depuis les réglages de ton compte store.",
            [AppDateFormatter.transactionDate(expireLe.toLocal())]),
          textAlign: TextAlign.center,
          style: TextStyle(color: context.cl.textS, fontSize: 12, height: 1.4)),
      ),
      const SizedBox(height: 24),
      SizedBox(
        width: double.infinity, height: 52,
        child: ElevatedButton.icon(
          onPressed: onContinuer,
          icon: const Icon(Icons.check_rounded, size: 20),
          label: Text(tr(context, "Découvrir le Premium"),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        ),
      ),
    ]),
  );
}

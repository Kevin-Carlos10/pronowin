import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';

class CurrentPlanBanner extends StatelessWidget {
  final bool isPremium;
  final int  daysLeft;
  final VoidCallback? onRenew;

  const CurrentPlanBanner({
    super.key,
    required this.isPremium,
    required this.daysLeft,
    this.onRenew,
  });

  // ─── États ────────────────────────────────────────────────────────────────
  bool get _isExpired  => isPremium && daysLeft <= 0;
  bool get _isUrgent   => isPremium && daysLeft > 0 && daysLeft <= 7;
  @override
  Widget build(BuildContext context) {
    if (_isExpired) return _ExpiredBanner(onRenew: onRenew);
    if (!isPremium) return _FreeBanner();
    return _PremiumBanner(daysLeft: daysLeft, isUrgent: _isUrgent, onRenew: onRenew);
  }
}

// ─── Bannière Gratuit ─────────────────────────────────────────────────────────
class _FreeBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: context.cl.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: context.cl.border, width: 0.5)),
    child: Row(children: [
      Container(width: 46, height: 46,
        decoration: BoxDecoration(
          color: context.cl.textM.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12)),
        child: Icon(Icons.person_rounded, color: context.cl.textM, size: 24)),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Plan Gratuit', style: TextStyle(
          color: context.cl.textP, fontSize: 15, fontWeight: FontWeight.w700)),
        Text('3 pronostics par jour · Tutoriels de base',
          style: TextStyle(color: context.cl.textM, fontSize: 12)),
      ])),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: context.cl.textM.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20)),
        child: Text('Gratuit', style: TextStyle(
          color: context.cl.textM, fontSize: 11, fontWeight: FontWeight.w600))),
    ]),
  );
}

// ─── Bannière Premium actif ───────────────────────────────────────────────────
class _PremiumBanner extends StatelessWidget {
  final int daysLeft;
  final bool isUrgent;
  final VoidCallback? onRenew;

  const _PremiumBanner({required this.daysLeft, required this.isUrgent, this.onRenew});

  @override
  Widget build(BuildContext context) {
    final accentColor = isUrgent ? AppColors.warning : AppColors.success;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isUrgent
            ? [const Color(0xFF2A1A00), const Color(0xFF1A1000)]
            : [const Color(0xFF1A2040), const Color(0xFF0D1530)],
          begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accentColor.withValues(alpha: 0.4), width: 1)),
      child: Column(children: [
        Row(children: [
          Container(width: 46, height: 46,
            decoration: BoxDecoration(
              color: AppColors.primaryLight.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12)),
            child: Icon(
              isUrgent ? Icons.timer_rounded : Icons.workspace_premium_rounded,
              color: AppColors.primaryLight, size: 24)),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Plan Premium Actif', style: const TextStyle(
              color: Color(0xFFE2E8F0), fontSize: 15, fontWeight: FontWeight.w700)),
            Text(
              isUrgent
                ? '⚠️ Expire dans $daysLeft jour${daysLeft > 1 ? 's' : ''}'
                : '$daysLeft jour${daysLeft > 1 ? 's' : ''} restant${daysLeft > 1 ? 's' : ''}',
              style: TextStyle(color: accentColor, fontSize: 12, fontWeight: FontWeight.w500)),
          ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: accentColor.withValues(alpha: 0.3))),
            child: Text(isUrgent ? 'Bientôt' : 'Actif', style: TextStyle(
              color: accentColor, fontSize: 11, fontWeight: FontWeight.w700))),
        ]),

        // Barre de progression des jours restants (sur 30)
        const SizedBox(height: 14),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Jours restants', style: const TextStyle(
              color: Color(0xFF8892AA), fontSize: 11)),
            Text('$daysLeft / 30j', style: TextStyle(
              color: accentColor, fontSize: 11, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 6),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: (daysLeft / 30).clamp(0.0, 1.0)),
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeOutCubic,
            builder: (_, v, _) => ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: v,
                minHeight: 5,
                backgroundColor: const Color(0xFF2A2A40),
                valueColor: AlwaysStoppedAnimation<Color>(accentColor),
              ),
            ),
          ),
        ]),

        // Bouton renouveler (si urgence)
        if (isUrgent && onRenew != null) ...[
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onRenew,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Renouveler maintenant'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.warning,
                side: BorderSide(color: AppColors.warning.withValues(alpha: 0.5)),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
        ],
      ]),
    );
  }
}

// ─── Bannière Premium expiré ──────────────────────────────────────────────────
class _ExpiredBanner extends StatelessWidget {
  final VoidCallback? onRenew;
  const _ExpiredBanner({this.onRenew});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFF2A0A0A), Color(0xFF1A0505)],
        begin: Alignment.topLeft, end: Alignment.bottomRight),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.error.withValues(alpha: 0.4), width: 1)),
    child: Column(children: [
      Row(children: [
        Container(width: 46, height: 46,
          decoration: BoxDecoration(
            color: AppColors.error.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.workspace_premium_rounded,
            color: AppColors.error, size: 24)),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Premium expiré', style: TextStyle(
            color: Color(0xFFE2E8F0), fontSize: 15, fontWeight: FontWeight.w700)),
          const Text('Votre accès Premium a expiré',
            style: TextStyle(color: AppColors.error, fontSize: 12)),
        ])),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: AppColors.error.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20)),
          child: const Text('Expiré', style: TextStyle(
            color: AppColors.error, fontSize: 11, fontWeight: FontWeight.w700))),
      ]),
      if (onRenew != null) ...[
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: onRenew,
            icon: const Icon(Icons.workspace_premium_rounded, size: 18),
            label: const Text('Réactiver Premium'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ],
    ]),
  );
}

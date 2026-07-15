import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';

class PlanCardWidget extends StatelessWidget {
  final String       name;
  final num          price;
  final bool         isCurrent, isPopular, isPremium;
  final List<String> features, lockedFeatures;

  const PlanCardWidget({
    super.key,
    required this.name,
    required this.price,
    required this.isCurrent,
    required this.isPopular,
    required this.isPremium,
    required this.features,
    required this.lockedFeatures,
  });

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 14),
    decoration: BoxDecoration(
      color: context.cl.surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: isPopular ? AppColors.primary : context.cl.border,
        width: isPopular ? 1.5 : 0.5),
      boxShadow: isPopular ? [
        BoxShadow(color: AppColors.primary.withValues(alpha: 0.10), blurRadius: 20, offset: const Offset(0, 4))
      ] : null,
    ),
    child: Column(children: [
      // ─── Header ───────────────────────────────────────────────────
      Stack(children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: isPremium
              ? LinearGradient(
                  colors: [const Color(0xFF1A2040), const Color(0xFF0D1530)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight)
              : null,
            color: isPremium ? null : context.cl.surfaceD,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
          ),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                if (isPremium) ...[
                  const Icon(Icons.workspace_premium_rounded,
                    color: AppColors.primaryLight, size: 18),
                  const SizedBox(width: 6),
                ],
                Text(name, style: TextStyle(
                  color: isPremium ? const Color(0xFFE2E8F0) : context.cl.textP,
                  fontSize: 18, fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 4),
              Text(isPremium ? 'Accès total · 30 jours' : 'Accès limité',
                style: TextStyle(color: isPremium ? const Color(0xFF8892AA) : context.cl.textS, fontSize: 12)),
            ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              TweenAnimationBuilder<int>(
                tween: IntTween(begin: 0, end: price.toInt()),
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeOutCubic,
                builder: (_, v, _) => Text(
                  price == 0 ? '0' : v.toString(),
                  style: const TextStyle(
                    color: AppColors.primaryLight, fontSize: 28, fontWeight: FontWeight.w800)),
              ),
              Text(price == 0 ? 'Gratuit' : 'FCFA / mois',
                style: TextStyle(color: isPremium ? const Color(0xFF8892AA) : context.cl.textS, fontSize: 12)),
            ]),
          ]),
        ),
        if (isPopular)
          Positioned(top: -1, right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(10))),
              child: const Text('Populaire', style: TextStyle(
                color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
            )),
      ]),

      // ─── Features ─────────────────────────────────────────────────
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(children: [
          ...features.map((f)       => _Feature(text: f, enabled: true)),
          ...lockedFeatures.map((f) => _Feature(text: f, enabled: false)),
          if (isCurrent) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.success.withValues(alpha: 0.3), width: 0.5)),
              child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.check_circle_rounded, color: AppColors.success, size: 16),
                SizedBox(width: 6),
                Text('Ton plan actuel', style: TextStyle(
                  color: AppColors.success, fontSize: 13, fontWeight: FontWeight.w600)),
              ]),
            ),
          ],
        ]),
      ),
    ]),
  );
}

class _Feature extends StatelessWidget {
  final String text; final bool enabled;
  const _Feature({required this.text, required this.enabled});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      Icon(enabled ? Icons.check_rounded : Icons.close_rounded,
        color: enabled ? AppColors.success : context.cl.textM, size: 16),
      const SizedBox(width: 10),
      Text(text, style: TextStyle(
        color:      enabled ? context.cl.textS : context.cl.textM,
        fontSize:   13,
        decoration: enabled ? null : TextDecoration.lineThrough)),
    ]),
  );
}

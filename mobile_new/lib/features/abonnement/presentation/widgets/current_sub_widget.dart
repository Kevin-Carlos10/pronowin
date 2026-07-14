import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/plan_entity.dart';

class CurrentSubWidget extends StatelessWidget {
  final SubscriptionEntity subscription;
  const CurrentSubWidget({super.key, required this.subscription});

  @override
  Widget build(BuildContext context) {
    final daysLeft = subscription.daysLeft;
    final progress = daysLeft / 30;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary.withValues(alpha: 0.15), AppColors.primary.withValues(alpha: 0.05)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3), width: 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.workspace_premium_rounded, color: AppColors.primaryLight, size: 20),
          const SizedBox(width: 8),
          const Text('Abonnement actif', style: TextStyle(
            color: AppColors.primaryLight, fontSize: 13, fontWeight: FontWeight.w600)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text('● Actif', style: TextStyle(color: AppColors.success, fontSize: 11)),
          ),
        ]),
        SizedBox(height: 12),
        Row(children: [
          Text('$daysLeft jours restants', style: TextStyle(
            color: context.cl.textP, fontSize: 20, fontWeight: FontWeight.w800)),
          Spacer(),
          Text(_formatDate(subscription.endDate),
            style: TextStyle(color: context.cl.textS, fontSize: 12)),
        ]),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress.clamp(0.0, 1.0),
            minHeight: 6,
            backgroundColor: context.cl.surfaceD,
            valueColor: AlwaysStoppedAnimation<Color>(
              daysLeft > 10 ? AppColors.success : AppColors.warning),
          ),
        ),
      ]),
    );
  }

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')}/${d.year}';
}

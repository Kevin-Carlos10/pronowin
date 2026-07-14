import 'package:flutter/material.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/transaction_entity.dart';

class TransactionTileWidget extends StatelessWidget {
  final TransactionEntity tx;
  const TransactionTileWidget({super.key, required this.tx});

  @override
  Widget build(BuildContext context) {
    final isDeposit = tx.isDeposit;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: context.cl.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.cl.border, width: 0.5),
      ),
      child: Row(
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: _statusColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(_icon, color: _statusColor, size: 18),
          ),
          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${isDeposit ? "Dépôt" : "Retrait"} · ${tx.provider}',
                  style: TextStyle(color: context.cl.textP, fontSize: 13, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Row(children: [
                  _StatusBadge(status: tx.status),
                  const SizedBox(width: 8),
                  Text(
                    AppDateFormatter.transactionDate(tx.createdAt),
                    style: TextStyle(color: context.cl.textM, fontSize: 11),
                  ),
                ]),
              ],
            ),
          ),

          Text(
            tx.formattedAmount,
            style: TextStyle(
              color: isDeposit ? AppColors.success : AppColors.error,
              fontSize: 14, fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Color get _statusColor => switch (tx.status) {
    TransactionStatus.completed => tx.isDeposit ? AppColors.success : AppColors.error,
    TransactionStatus.pending   => AppColors.warning,
    TransactionStatus.failed    => AppColors.error,
    TransactionStatus.cancelled => const Color(0xFF8892AA),
  };

  IconData get _icon => switch (tx.status) {
    TransactionStatus.completed => tx.isDeposit ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
    TransactionStatus.pending   => Icons.schedule_rounded,
    TransactionStatus.failed    => Icons.cancel_rounded,
    TransactionStatus.cancelled => Icons.block_rounded,
  };
}

class _StatusBadge extends StatelessWidget {
  final TransactionStatus status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      TransactionStatus.completed => ('Complété',  AppColors.success),
      TransactionStatus.pending   => ('En attente', AppColors.warning),
      TransactionStatus.failed    => ('Échoué',    AppColors.error),
      TransactionStatus.cancelled => ('Annulé',    context.cl.textM),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
    );
  }
}

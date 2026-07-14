import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../providers/subscription_provider.dart';

class PromoCodeWidget extends ConsumerStatefulWidget {
  final VoidCallback? onApply;
  const PromoCodeWidget({super.key, this.onApply});

  @override
  ConsumerState<PromoCodeWidget> createState() => _PromoCodeWidgetState();
}

class _PromoCodeWidgetState extends ConsumerState<PromoCodeWidget> {
  final _ctrl = TextEditingController();

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final promoState = ref.watch(promoProvider);

    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cl.surface, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.cl.border, width: 0.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.local_offer_rounded, color: AppColors.primaryLight, size: 18),
          SizedBox(width: 8),
          Text('Code Promo / 1xBet', style: TextStyle(color: context.cl.textP, fontSize: 14, fontWeight: FontWeight.w600)),
        ]),
        SizedBox(height: 4),
        Text('Entrez votre code partenaire pour accéder à Premium gratuitement.', style: TextStyle(color: context.cl.textS, fontSize: 12)),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _ctrl,
              style: TextStyle(color: context.cl.textP, fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 1),
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                hintText: 'Ex: XBET2025',
                hintStyle: const TextStyle(letterSpacing: 0),
                suffixIcon: promoState is PromoValid
                    ? const Icon(Icons.check_circle_rounded, color: AppColors.success)
                    : null,
              ),
              onChanged: (_) { if (ref.read(promoProvider) is PromoValid) ref.read(promoProvider.notifier).reset(); }, // ignore: unused_result
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: promoState is PromoLoading
                  ? null
                  : () {
                      HapticFeedback.selectionClick();
                      ref.read(promoProvider.notifier).validate(_ctrl.text);
                    },
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(70, 52),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              child: promoState is PromoLoading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Vérifier'),
            ),
          ),
        ]),
        if (promoState is PromoValid) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.success.withValues(alpha: 0.3), width: 0.5),
            ),
            child: Row(children: [
              Icon(Icons.check_circle_rounded, color: AppColors.success, size: 18),
              SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(promoState.code.description, style: TextStyle(color: AppColors.success, fontSize: 12, fontWeight: FontWeight.w600)),
                Text('${promoState.code.durationDays} jours Premium offerts', style: TextStyle(color: context.cl.textS, fontSize: 11)),
              ])),
            ]),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity, height: 48,
            child: ElevatedButton.icon(
              onPressed: () {
                HapticFeedback.mediumImpact();
                ref.read(subscribeProvider.notifier).subscribe(
                  planId: 'premium', paymentMethod: 'promo_code',
                  promoCode: promoState.code.code,
                );
                widget.onApply?.call();
              },
              icon: const Icon(Icons.workspace_premium_rounded, size: 18),
              label: const Text('Activer le code promo'),
            ),
          ),
        ],
        if (promoState is PromoInvalid)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(children: [
              const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 16),
              const SizedBox(width: 8),
              Text(promoState.message, style: const TextStyle(color: AppColors.error, fontSize: 12)),
            ]),
          ),
      ]),
    );
  }
}

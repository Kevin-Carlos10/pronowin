import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../features/auth/presentation/providers/auth_provider.dart';
import '../../../../shared/utils/premium_nav.dart';
import '../providers/subscription_provider.dart';
import '../widgets/plan_card_widget.dart';
import '../widgets/current_plan_banner.dart';
import '../../../../shared/widgets/pw_button.dart';

class AbonnementPage extends ConsumerWidget {
  const AbonnementPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subAsync  = ref.watch(currentSubscriptionProvider);
    final authState = ref.watch(authProvider);
    final isPremium = authState is AuthAuthenticated && authState.user.isPremium;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Row(children: [
          Container(width: 32, height: 32,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.primaryLight],
                begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(9),
              boxShadow: [const BoxShadow(color: Color(0x59023E8A),
                blurRadius: 8, offset: Offset(0, 3))]),
            child: const Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 17)),
          const SizedBox(width: 10),
          RichText(text: TextSpan(
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: context.cl.textP),
            children: const [
              TextSpan(text: 'Abonne'),
              TextSpan(text: 'ment', style: TextStyle(color: AppColors.primaryLight)),
            ],
          )),
        ]),
      ),
      body: subAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
        error:   (e, _) => _ErrorView(onRetry: () => ref.invalidate(currentSubscriptionProvider)),
        data: (sub) {
          final premiumPrice = (sub['premium_price'] as num?)?.toDouble() ?? 5000.0;
          final daysLeft     = (sub['days_left']     as num?)?.toInt()    ?? 0;
          final promoCode    = sub['promo_code'] as String? ?? 'PRONOWIN2025';
          final pendingProof = sub['pending_proof'] as Map<String, dynamic>?;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
            children: [

              CurrentPlanBanner(
                isPremium: isPremium,
                daysLeft: daysLeft,
                onRenew: () => goToPremium(context, ref, extra: sub),
              ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.08, end: 0),
              const SizedBox(height: 16),

              if (pendingProof != null) ...[
                _PendingProofBanner(proof: pendingProof)
                  .animate().fadeIn(duration: 350.ms, delay: 80.ms),
                const SizedBox(height: 4),
              ],

              const _SectionLabel('PLANS DISPONIBLES')
                .animate().fadeIn(duration: 300.ms, delay: 100.ms),
              PlanCardWidget(
                name: 'Plan Gratuit', price: 0, isCurrent: !isPremium,
                features:        const ['3 pronostics par jour', 'Tutoriels basiques', 'Notifications matchs'],
                lockedFeatures:  const ['Pronostics VIP', 'Statistiques avancées', 'Sans publicité'],
                isPopular: false, isPremium: false,
              ).animate().fadeIn(duration: 350.ms, delay: 150.ms)
               .slideY(begin: 0.08, end: 0),
              PlanCardWidget(
                name: 'Plan Premium',
                price: premiumPrice,
                isCurrent: isPremium,
                features: const [
                  'Pronostics VIP illimités', 'Tous les tutoriels',
                  'Statistiques avancées', 'Sans publicité', 'Support prioritaire',
                ],
                lockedFeatures: const [],
                isPopular: true, isPremium: true,
              ).animate().fadeIn(duration: 350.ms, delay: 220.ms)
               .slideY(begin: 0.08, end: 0),

              if (!isPremium && pendingProof == null) ...[
                const SizedBox(height: 8),
                PwButton(
                  label: 'Activer Premium maintenant',
                  icon: Icons.workspace_premium_rounded,
                  onPressed: () {
                    HapticFeedback.mediumImpact();
                    goToPremium(context, ref, extra: sub);
                  },
                ).animate()
                 .fadeIn(duration: 350.ms, delay: 300.ms)
                 .slideY(begin: 0.1, end: 0)
                 .then(delay: 500.ms)
                 .shimmer(duration: 1800.ms, color: AppColors.primaryLight.withValues(alpha: 0.4))
                 .animate(onPlay: (c) => c.repeat())
                 .shimmer(duration: 3000.ms, delay: 2000.ms,
                     color: AppColors.primaryLight.withValues(alpha: 0.2)),
                const SizedBox(height: 24),
                _FaqSection(promoCode: promoCode)
                  .animate().fadeIn(duration: 350.ms, delay: 380.ms),
              ],

              // ─── Renouveler si premium encore actif ─────────────────
              if (isPremium && pendingProof == null && daysLeft <= 30) ...[
                const SizedBox(height: 4),
                _RenewBanner(
                  daysLeft: daysLeft,
                  onRenew: () => goToPremium(context, ref, extra: sub),
                ).animate().fadeIn(duration: 350.ms, delay: 340.ms),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorView({required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(child: Column(
    mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.error_outline_rounded, color: context.cl.textM, size: 40),
      const SizedBox(height: 12),
      Text('Impossible de charger l\'abonnement', style: TextStyle(color: context.cl.textS)),
      const SizedBox(height: 12),
      ElevatedButton(onPressed: onRetry, child: const Text('Réessayer')),
    ],
  ));
}

class _PendingProofBanner extends StatelessWidget {
  final Map<String, dynamic> proof;
  const _PendingProofBanner({required this.proof});
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.warning.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.warning.withValues(alpha: 0.3))),
    child: Row(children: [
      const Icon(Icons.hourglass_top_rounded, color: AppColors.warning, size: 22),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Preuve en cours de vérification', style: TextStyle(
          color: AppColors.warning, fontSize: 13, fontWeight: FontWeight.w600)),
        Text(
          (proof['type'] as String?) == 'payment_screenshot'
              ? 'Validation sous 30 min ouvrables'
              : 'Validation sous 2 heures ouvrables',
          style: TextStyle(color: context.cl.textS, fontSize: 12)),
      ])),
    ]),
  );
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(label, style: TextStyle(
      color: context.cl.textS, fontSize: 11,
      fontWeight: FontWeight.w600, letterSpacing: 1)),
  );
}

class _RenewBanner extends StatelessWidget {
  final int daysLeft;
  final VoidCallback onRenew;
  const _RenewBanner({required this.daysLeft, required this.onRenew});

  @override
  Widget build(BuildContext context) {
    final isUrgent = daysLeft <= 7;
    final color    = isUrgent ? AppColors.warning : AppColors.info;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.25))),
      child: Row(children: [
        Icon(Icons.refresh_rounded, color: color, size: 20),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            isUrgent ? 'Renouvelez vite !' : 'Renouveler l\'abonnement',
            style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600)),
          Text(
            isUrgent
              ? 'Plus que $daysLeft jour${daysLeft > 1 ? 's' : ''} — ne perdez pas tes accès Premium.'
              : 'Ajoute 30 jours dès maintenant pour ne jamais être interrompu.',
            style: TextStyle(color: context.cl.textS, fontSize: 11, height: 1.4)),
        ])),
        const SizedBox(width: 8),
        TextButton(
          onPressed: onRenew,
          style: TextButton.styleFrom(foregroundColor: color, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
          child: const Text('Renouveler', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
        ),
      ]),
    );
  }
}

class _FaqSection extends StatelessWidget {
  final String promoCode;
  const _FaqSection({required this.promoCode});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const _SectionLabel('FAQ'),
      _FaqItem('Comment payer ?',
        'Envoie 5 000 FCFA sur notre numéro MobCash, prends une capture d\'écran et soumets-la.'),
      _FaqItem("C'est quoi le code promo 1xBet ?",
        'Crée ton compte 1xBet avec le code $promoCode, prends une capture de ton profil et soumets-la.'),
      const _FaqItem('Délai d\'activation ?',
        'Paiement direct : 30 minutes. Code 1xBet : 2 heures ouvrables.'),
      const _FaqItem('Renouvellement automatique ?',
        'Non. Tu reçois une notification 3 jours avant l\'expiration.'),
    ],
  );
}

class _FaqItem extends StatefulWidget {
  final String q, a;
  const _FaqItem(this.q, this.a);
  @override State<_FaqItem> createState() => _FaqItemState();
}
class _FaqItemState extends State<_FaqItem> {
  bool _open = false;
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () {
      HapticFeedback.selectionClick();
      setState(() => _open = !_open);
    },
    child: Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: context.cl.surface, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.cl.border, width: 0.5)),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        child: Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(children: [
            Expanded(child: Text(widget.q, style: TextStyle(
              color: context.cl.textP, fontSize: 13, fontWeight: FontWeight.w500))),
            Icon(_open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
              color: context.cl.textM, size: 20),
          ]),
        ),
        if (_open) Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: context.cl.border, width: 0.5))),
          child: Text(widget.a, style: TextStyle(
            color: context.cl.textS, fontSize: 12, height: 1.5)),
        ),
      ]),
      ),
    ),
  );
}

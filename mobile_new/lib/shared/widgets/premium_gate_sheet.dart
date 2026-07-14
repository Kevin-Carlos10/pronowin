import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';

// Appeler depuis n'importe où pour afficher la modale d'upgrade Premium.
// [matchLabel] : ex. "PSG vs Real Madrid" — affiché en contexte.
Future<void> showPremiumGateSheet(BuildContext context, {String? matchLabel}) {
  HapticFeedback.mediumImpact();
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    builder: (_) => _PremiumGateSheet(matchLabel: matchLabel),
  );
}

class _PremiumGateSheet extends ConsumerWidget {
  final String? matchLabel;
  const _PremiumGateSheet({this.matchLabel});

  static const _benefits = [
    (Icons.analytics_rounded,       'Pronostics VIP exclusifs',      'Accès à tous les pronostics d\'experts, y compris les analyses IA détaillées'),
    (Icons.show_chart_rounded,      'Cotes & probabilités complètes', 'Cotes H/N/A, probabilité IA, historique H2H et forme des équipes'),
    (Icons.workspace_premium_rounded,'Taux de réussite supérieur',    'Nos pronostics Premium affichent +68% de réussite sur les 30 derniers jours'),
    (Icons.notifications_active_rounded, 'Alertes match prioritaires','Notifications 1h avant le coup d\'envoi pour ne jamais rater une opportunité'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.read(authProvider);
    final profileComplete = authState is! AuthAuthenticated || authState.user.isProfileComplete;

    return Container(
      decoration: BoxDecoration(
        color: context.cl.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
        20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 40, height: 4,
            margin: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: context.cl.border,
              borderRadius: BorderRadius.circular(2)),
          ),

          // Header gradient
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primary.withValues(alpha: 0.15),
                  AppColors.primaryLight.withValues(alpha: 0.07),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.25), width: 0.8),
            ),
            child: Column(children: [
              Container(
                width: 56, height: 56,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.primary, AppColors.primaryLight]),
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.4),
                    blurRadius: 16, offset: const Offset(0, 6))],
                ),
                child: const Icon(Icons.lock_open_rounded,
                  color: Colors.white, size: 28),
              ).animate().scale(
                begin: const Offset(0.7, 0.7),
                end: const Offset(1.0, 1.0),
                duration: 400.ms, curve: Curves.easeOutBack),

              const SizedBox(height: 14),
              Text('Contenu Premium', style: TextStyle(
                color: context.cl.textP, fontSize: 18,
                fontWeight: FontWeight.w800, letterSpacing: -0.3)),
              const SizedBox(height: 6),
              if (matchLabel != null)
                Text(matchLabel!, style: TextStyle(
                  color: AppColors.primary, fontSize: 13,
                  fontWeight: FontWeight.w600))
              else
                Text('Débloquez l\'accès à tous les pronostics VIP',
                  style: TextStyle(color: context.cl.textS, fontSize: 13),
                  textAlign: TextAlign.center),
            ]),
          ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.05, end: 0),

          const SizedBox(height: 20),

          // Bénéfices
          ..._benefits.asMap().entries.map((e) {
            final (icon, title, subtitle) = e.value;
            return _BenefitRow(icon: icon, title: title, subtitle: subtitle)
              .animate(delay: Duration(milliseconds: 80 + e.key * 60))
              .fadeIn(duration: 250.ms)
              .slideX(begin: -0.04, end: 0);
          }),

          const SizedBox(height: 20),

          // Prix badge
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: context.cl.surfaceD,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: context.cl.border, width: 0.7)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('À partir de ', style: TextStyle(
                  color: context.cl.textS, fontSize: 13)),
                Text('5 000 XOF', style: const TextStyle(
                  color: AppColors.primary, fontSize: 16,
                  fontWeight: FontWeight.w900)),
                Text(' / mois', style: TextStyle(
                  color: context.cl.textS, fontSize: 13)),
              ],
            ),
          ).animate(delay: 320.ms).fadeIn(duration: 250.ms),

          const SizedBox(height: 14),

          // CTA
          SizedBox(
            width: double.infinity,
            height: 54,
            child: GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                Navigator.of(context).pop();
                if (profileComplete) {
                  context.push('/compte/activer-premium');
                } else {
                  context.push('/compte/completer-profil');
                }
              },
              child: Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.primary, AppColors.primaryLight],
                    begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(27),
                  boxShadow: [BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.45),
                    blurRadius: 18, offset: const Offset(0, 7))],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(Icons.workspace_premium_rounded,
                      color: Colors.white, size: 20),
                    SizedBox(width: 8),
                    Text('Passer Premium', style: TextStyle(
                      color: Colors.white, fontSize: 15,
                      fontWeight: FontWeight.w700, letterSpacing: 0.2)),
                  ],
                ),
              ).animate(onPlay: (c) => c.repeat())
               .shimmer(duration: 2400.ms, delay: 800.ms, color: Colors.white24),
            ),
          ).animate(delay: 380.ms)
           .fadeIn(duration: 300.ms)
           .slideY(begin: 0.08, end: 0, curve: Curves.easeOutCubic),

          const SizedBox(height: 10),

          // Lien secondaire
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Peut-être plus tard', style: TextStyle(
              color: context.cl.textM, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

class _BenefitRow extends StatelessWidget {
  final IconData icon;
  final String   title;
  final String   subtitle;
  const _BenefitRow({required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 38, height: 38,
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.2), width: 0.7)),
        child: Icon(icon, color: AppColors.primary, size: 18)),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: TextStyle(
          color: context.cl.textP, fontSize: 13, fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(subtitle, style: TextStyle(
          color: context.cl.textS, fontSize: 11, height: 1.4)),
      ])),
    ]),
  );
}

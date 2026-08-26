import 'package:flutter/material.dart';
import '../../core/utils/motion.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../features/abonnement/presentation/providers/subscription_provider.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../features/pronostics/presentation/providers/bilan_premium_provider.dart';

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
    (Icons.analytics_rounded,       'Pronostics VIP exclusifs',      'Accès à tous les pronostics d\'experts, y compris les analyses statistiques détaillées'),
    // « H2H » et « H/N/A » étaient deux sigles sur la même ligne, dans l'écran
    // qui demande de payer — le pire endroit pour perdre le lecteur.
    (Icons.show_chart_rounded,      'Cotes & probabilités complètes', 'Cotes 1/N/2, probabilité estimée, confrontations directes et forme des équipes'),
    // Le taux de réussite ne figure plus dans cette liste : il y était écrit
    // en dur (« +68 % de réussite sur les 30 derniers jours »), donc exact
    // seulement par accident — sur l'écran qui demande de payer. Il est
    // désormais mesuré, et affiché sous la liste par `_TauxReussiteReel`, qui
    // se tait quand l'échantillon ne permet rien d'affirmer.
    (Icons.notifications_active_rounded, 'Alertes match prioritaires','Notifications 1h avant le coup d\'envoi pour ne jamais rater une opportunité'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.read(authProvider);
    final profileComplete = authState is! AuthAuthenticated || authState.user.isProfileComplete;
    final tarifs = ref.watch(tarifsPremiumProvider);

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

          const _TauxReussiteReel(),

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
                // « XOF » est un code bancaire ; le prix d'un abonnement se lit
                // en FCFA, comme partout ailleurs dans l'app.
                //
                // Ce montant valait « 5 000 » en dur — un chiffre qui ne
                // correspondait à aucune formule : ni 6 000 (mensuel), ni
                // 4 200 (avec code), ni 4 500 ni 3 150 (annuels ramenés au
                // mois). La feuille qui décide l'utilisateur annonçait donc un
                // prix inexistant, et l'écran suivant le démentait.
                Text('${tarifs.minMensuelFormate} FCFA', style: const TextStyle(
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
                  context.push('/compte/completer-profil', extra: '/compte/activer-premium');
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
              ).animate(onPlay: (c) { if (!context.animationsReduites) c.repeat(); })
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

/// Taux de réussite réel des pronostics Premium, ou rien.
///
/// « Rien » est un état de plein droit ici, et c'est tout l'intérêt : sur un
/// échantillon trop mince, trois pronostics gagnés donnent « 100 % », ce qui
/// serait la même promesse creuse que le « +68 % » codé en dur qu'on remplace.
/// Le serveur tranche (`echantillon_suffisant`), l'écran obéit.
///
/// Le détail gagnés / perdus accompagne toujours le pourcentage : un taux seul
/// ne se vérifie pas, avec « 34 gagnés sur 47 » en face il se vérifie.
class _TauxReussiteReel extends ConsumerWidget {
  const _TauxReussiteReel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bilan = ref.watch(bilanPremiumProvider).valueOrNull;
    if (bilan == null || !bilan.affichable) return const SizedBox.shrink();

    final taux = bilan.tauxReussite!;
    final couleur = taux >= 60 ? AppColors.success : context.cl.textP;

    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: couleur.withValues(alpha: 0.30), width: 0.8),
      ),
      child: Row(children: [
        Icon(Icons.workspace_premium_rounded, color: couleur, size: 20),
        const SizedBox(width: 11),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$taux % de réussite',
              style: TextStyle(color: couleur, fontSize: 15,
                  fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(
              '${bilan.gagnes} gagnés sur ${bilan.pronosticsTranches} '
              'pronostics VIP tranchés — ${bilan.periodeJours} derniers jours',
              style: TextStyle(color: context.cl.textM, fontSize: 11, height: 1.3)),
          ]),
        ),
      ]),
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

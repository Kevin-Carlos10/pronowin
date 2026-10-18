import 'package:pronowin/l10n/app_strings.dart';
import 'package:flutter/material.dart';
import '../../core/utils/motion.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../features/abonnement/presentation/providers/subscription_provider.dart';
import '../../features/abonnement/presentation/providers/iap_provider.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../features/pronostics/presentation/providers/bilan_premium_provider.dart';

// Appeler depuis n'importe où pour afficher la modale d'upgrade Premium.
// [matchLabel] : ex. "PSG vs Real Madrid" — affiché en contexte.
Future<void> showPremiumGateSheet(BuildContext context, {String? matchLabel}) {
  HapticFeedback.mediumImpact();
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    builder: (_) => _PremiumGateSheet(matchLabel: matchLabel),
  );
}

class _PremiumGateSheet extends ConsumerWidget {
  final String? matchLabel;
  const _PremiumGateSheet({this.matchLabel});

  static const _benefits = [
    (
      Icons.insights_rounded,
      'La sélection et son analyse',
      'Consulte le pronostic, la cote retenue et les explications de l’analyste.',
    ),
    (
      Icons.workspace_premium_rounded,
      'Tous les pronostics VIP',
      'Explore les sélections Premium publiées, au-delà de ce match.',
    ),
    (
      Icons.query_stats_rounded,
      'Des chiffres pour comparer',
      'Mets la confiance annoncée en perspective avec les données disponibles du match.',
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final profileComplete =
        authState is! AuthAuthenticated || authState.user.isProfileComplete;
    final sub = ref.watch(currentSubscriptionProvider).valueOrNull ?? const {};
    final price = premiumMonthlyPriceLabel(ref, sub);
    final contenu = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF101827), Color(0xFF293047)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: const Color(0xFFE9B96B).withValues(alpha: 0.4),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE9B96B).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.workspace_premium_rounded,
                      color: Color(0xFFFFD99A),
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'PRONOWIN PREMIUM',
                      style: TextStyle(
                        color: Color(0xFFFFD99A),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                tr(context, "Va plus loin dans l’analyse"),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  height: 1.12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.7,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                tr(
                  context,
                  "Comprends la sélection, examine les chiffres et forge ton avis.",
                ),
                style: const TextStyle(
                  color: Color(0xFFCDD4E2),
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
              if (matchLabel != null && matchLabel!.trim().isNotEmpty) ...[
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.sports_soccer_rounded,
                        color: Color(0xFFFFD99A),
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tr(context, "L’analyse que tu consultes"),
                              style: const TextStyle(
                                color: Color(0xFFCDD4E2),
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              matchLabel!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.lock_outline_rounded,
                        color: Color(0xFFCDD4E2),
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 22),
        Text(
          tr(context, "Ce que tu débloques"),
          style: TextStyle(
            color: context.cl.textP,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 14),
        ..._benefits.map(
          (b) => _BenefitRow(icon: b.$1, title: b.$2, subtitle: b.$3),
        ),
        const _TauxReussiteReel(),
        const SizedBox(height: 8),
      ],
    );

    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.92,
        ),
        decoration: BoxDecoration(
          color: context.cl.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      tr(context, "Découvrir Premium"),
                      style: TextStyle(
                        color: context.cl.textM,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: tr(context, "Fermer"),
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, size: 21),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: context.animationsReduites
                    ? contenu
                    : contenu
                          .animate()
                          .fadeIn(duration: 280.ms)
                          .slideY(
                            begin: 0.02,
                            end: 0,
                            curve: Curves.easeOutCubic,
                          ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
              decoration: BoxDecoration(
                color: context.cl.surface,
                border: Border(top: BorderSide(color: context.cl.border)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Google Play sans abonnement en vente : pas de prix.
                  if (!premiumIndisponibleSurPlay(ref)) Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      Text(
                        tr(context, "Abonnement mensuel"),
                        style: TextStyle(color: context.cl.textS, fontSize: 12),
                      ),
                      Text(
                        price,
                        style: TextStyle(
                          color: context.cl.textP,
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        tr(context, " / mois"),
                        style: TextStyle(color: context.cl.textS, fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFB63D00),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 16,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        final router = GoRouter.of(context);
                        Navigator.of(context).pop();
                        if (profileComplete) {
                          router.push('/compte/activer-premium');
                        } else {
                          router.push(
                            '/compte/completer-profil',
                            extra: '/compte/activer-premium',
                          );
                        }
                      },
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Text(
                              tr(context, "Découvrir les offres Premium"),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.arrow_forward_rounded, size: 19),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    tr(context, "Choisis ton offre à l’étape suivante."),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: context.cl.textM, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
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
    final couleur = taux >= 60 ? context.cl.success : context.cl.textP;

    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: couleur.withValues(alpha: 0.30), width: 0.8),
      ),
      child: Row(
        children: [
          Icon(Icons.workspace_premium_rounded, color: couleur, size: 20),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr(context, "{arg0} % de réussite", [taux]),
                  style: TextStyle(
                    color: couleur,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  tr(
                    context,
                    "{arg0} gagnés sur {arg1} pronostics VIP tranchés — {arg2} derniers jours",
                    [
                      bilan.gagnes,
                      bilan.pronosticsTranches,
                      bilan.periodeJours,
                    ],
                  ),
                  style: TextStyle(
                    color: context.cl.textM,
                    fontSize: 11,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BenefitRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _BenefitRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.2),
              width: 0.7,
            ),
          ),
          child: Icon(icon, color: AppColors.primary, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr(context, title),
                style: TextStyle(
                  color: context.cl.textP,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                tr(context, subtitle),
                style: TextStyle(
                  color: context.cl.textS,
                  fontSize: 11,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

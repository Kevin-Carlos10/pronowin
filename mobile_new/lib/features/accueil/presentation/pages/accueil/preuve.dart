// Bandeau de preuve et récapitulatif de la veille — extrait de accueil_page.dart.
//
// `part` et non un fichier autonome : ces classes sont privées à la
// bibliothèque (préfixe `_`) et doivent le rester. Un import classique
// aurait imposé de les rendre publiques, donc visibles de partout.
part of '../accueil_page.dart';

class _ProofBand extends ConsumerWidget {
  const _ProofBand();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final perf = ref.watch(performance30Provider).valueOrNull;
    if (perf == null) return const SizedBox.shrink();

    final total = (perf['total'] as num?)?.toInt() ?? 0;
    // Sous 10 pronostics réglés, un pourcentage n'a aucune valeur statistique
    // et se retourne contre nous à la première mauvaise série.
    if (total < 10) return const SizedBox.shrink();

    final wins = (perf['wins'] as num?)?.toInt() ?? 0;
    final roi  = (perf['roi'] as num?)?.toDouble() ?? 0;
    final positif = roi > 0;

    return GestureDetector(
      onTap: () => context.push('/performance'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: context.cl.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: (positif ? AppColors.success : context.cl.border)
                  .withValues(alpha: positif ? 0.35 : 1),
              width: 0.8),
        ),
        child: Row(
          children: [
            Icon(Icons.verified_rounded,
                color: positif ? AppColors.success : context.cl.textM, size: 17),
            const SizedBox(width: 9),
            Expanded(
              child: RichText(
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                text: TextSpan(
                  style: TextStyle(color: context.cl.textM, fontSize: 12),
                  children: [
                    TextSpan(text: '$total derniers pronostics · '),
                    TextSpan(
                        text: '$wins gagnés',
                        style: TextStyle(
                            color: context.cl.textP,
                            fontWeight: FontWeight.w800)),
                    const TextSpan(text: ' · '),
                    TextSpan(
                      text: '${positif ? '+' : ''}${roi.toStringAsFixed(1)} %',
                      style: TextStyle(
                          color:
                              positif ? AppColors.success : AppColors.error,
                          fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: context.cl.textM, size: 18),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// BILAN D'HIER — refermer la journée précédente
// ══════════════════════════════════════════════════════════════════════════════
/// Sans ça, celui qui a suivi les pronostics d'hier soir ne sait pas s'il a
/// gagné en ouvrant l'app le matin — il doit aller fouiller l'historique.
class _YesterdayRecap extends ConsumerWidget {
  const _YesterdayRecap();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(hierProvider).valueOrNull;
    if (list == null || list.isEmpty) return const SizedBox.shrink();

    final regles = list
        .map((e) => e as Map<String, dynamic>)
        .where((p) => p['result'] != null)
        .toList();
    if (regles.isEmpty) return const SizedBox.shrink();

    final gagnes = regles.where((p) => p['result'] == 'WIN').length;
    final tout = gagnes == regles.length;

    return GestureDetector(
      onTap: () => context.push('/historique'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: context.cl.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.cl.border, width: 0.8),
        ),
        child: Row(
          children: [
            Icon(tout ? Icons.emoji_events_rounded : Icons.history_rounded,
                color: tout ? AppColors.success : context.cl.textM, size: 17),
            const SizedBox(width: 9),
            Expanded(
              child: Text.rich(
                TextSpan(
                  style: TextStyle(color: context.cl.textM, fontSize: 12),
                  children: [
                    const TextSpan(text: 'Hier · '),
                    TextSpan(
                      text: '$gagnes sur ${regles.length}',
                      style: TextStyle(
                          color: gagnes * 2 >= regles.length
                              ? AppColors.success
                              : AppColors.error,
                          fontWeight: FontWeight.w800),
                    ),
                    const TextSpan(text: ' pronostic'),
                    TextSpan(text: regles.length > 1 ? 's gagnés' : ' gagné'),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: context.cl.textM, size: 18),
          ],
        ),
      ),
    );
  }
}

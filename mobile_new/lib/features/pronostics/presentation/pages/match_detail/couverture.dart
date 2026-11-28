// « Couvrir ma mise » — l'alerte de couverture dans la fiche du match
// (26 novembre 2026). La carte elle-même est partagée avec le détail d'un
// combiné : `bankroll/presentation/widgets/carte_couverture.dart`.
//
// `part` et non un fichier autonome : la fiche garde ses classes privées.
part of '../match_detail_page.dart';

/// La couverture de sa mise sur un pronostic, maintenant (serveur).
final couvertureMiseProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>?, String>((ref, pronosticId) async {
  try {
    final r = await ref.read(dioProvider).get('/bankroll/couverture/$pronosticId');
    return Map<String, dynamic>.from(r.data as Map);
  } catch (_) {
    return null;
  }
});

/// Pour une sélection enregistrée dans la bankroll et encore ouverte :
/// l'évènement inverse, sa cote du moment, combien miser dessus et ce qui est
/// alors garanti, au choix entre gain égal et mise remboursée ; puis
/// « J'ai couvert ».
///
/// Rien sans mise ouverte, pour un marché qui n'a pas d'inverse exact, une
/// fois le match terminé, et sur l'iPhone sans pari. Porte sa propre marge.
class _CarteCouverture extends ConsumerWidget {
  final String pronosticId;
  final MatchEntity match;
  const _CarteCouverture({required this.pronosticId, required this.match});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(sansPariProvider) || match.status == MatchStatus.finished) {
      return const SizedBox.shrink();
    }
    if (!ref.watch(hasBetOnPronosticProvider(pronosticId))) return const SizedBox.shrink();
    final d = ref.watch(couvertureMiseProvider(pronosticId)).valueOrNull;
    if (d == null) return const SizedBox.shrink();
    final enregistree = d['enregistree'] is Map;
    if (!enregistree && !(d['disponible'] == true || d['raison'] == 'cote')) return const SizedBox.shrink();
    return CarteCouverture(
      donnees: d,
      cle: pronosticId,
      apresEnregistrement: () => ref.invalidate(couvertureMiseProvider(pronosticId)),
    );
  }
}

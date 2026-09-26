/// Jusqu'à quand propose-t-on d'enregistrer une mise ?
///
/// Miroir de `backend/src/services/verrou_pari.ts`. Le serveur refuse ; cet
/// écran ne doit pas proposer ce qui sera refusé — un bouton qui mène à une
/// erreur est pire qu'un bouton absent.
///
/// ── Ce que l'écran laissait faire ─────────────────────────────────────────
///
/// La carte d'accueil masquait le bouton « Miser » sur `status == 'finished'`
/// seulement. Pendant un match **en direct**, avec le score affiché juste à
/// côté, le bouton restait là. Le serveur, lui, ne vérifiait rien du tout : la
/// mise était enregistrée.
///
/// La page détail, elle, était déjà correcte — elle n'affiche le bouton que
/// sur `MatchStatus.upcoming`. C'est exactement le motif qui revient : une
/// règle appliquée à un endroit, oubliée à l'autre.
///
/// ── Pourquoi la date compte autant que le statut ──────────────────────────
///
/// `status` vient d'une synchronisation périodique côté serveur. Entre le coup
/// d'envoi et la synchronisation suivante, un match commencé porte encore
/// « à venir ». L'heure de coup d'envoi ne se périme pas.
///
/// Un banc compare cette règle à celle du backend sur les mêmes cas ; si l'une
/// des deux change seule, il tombe.
library;

/// Statuts qui signifient que le match n'est plus à venir.
const _plusAVenir = {'live', 'finished', 'suspended', 'postponed'};

/// Peut-on encore proposer d'enregistrer une mise sur ce pronostic ?
///
/// [resultat] est `null` tant que le pronostic n'est pas réglé.
/// [statutMatch] arrive tel que l'API l'écrit, dans n'importe quelle casse.
/// [dateMatch] est l'heure du coup d'envoi ; `null` si l'API ne l'a pas donnée.
bool pariEncoreOuvert({
  required String? resultat,
  required String? statutMatch,
  required DateTime? dateMatch,
  DateTime? maintenant,
}) {
  if (resultat != null && resultat.isNotEmpty) return false;

  if (_plusAVenir.contains((statutMatch ?? '').toLowerCase())) return false;

  if (dateMatch != null) {
    final t = maintenant ?? DateTime.now();
    if (!dateMatch.isAfter(t)) return false;
  }

  return true;
}

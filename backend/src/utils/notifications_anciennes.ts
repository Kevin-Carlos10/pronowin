/**
 * Les notifications déjà enregistrées, réécrites comme celles d'aujourd'hui.
 *
 * Les premières notifications portaient un émoji et une majuscule
 * (« 🏆 Pronostic Gagnant ! »), un accord fautif (« Votre bankroll est mis à
 * jour ! ») et le code ISO de la devise (« +525 XOF »). Le code a été corrigé
 * depuis, mais l'historique les garde : dans la liste, elles côtoyaient les
 * nouvelles (« Pronostic gagnant ! ») et l'écran paraissait écrit par deux
 * mains (vidéo du 5 octobre 2026).
 *
 * La base n'est pas réécrite : l'harmonisation se fait à la lecture, et ne
 * touche que les anciens textes **du système**, connus un par un — un message
 * rédigé depuis le panneau, émoji compris, reste tel quel.
 */
const ANCIEN_TITRE = new RegExp(
  '^(?:⚠️|⚠|⚽|✅|❌|🎉|🏆|👥|💰|🔄)\\s+('
  + [
    'Compte suspendu', 'Match dans 1 heure !', 'Match en direct !',
    'Versement effectué !', 'Demande refusée', 'Versement refusé',
    'Pronostic Gagnant !', 'Pronostic Perdant', 'Pronostic remboursé',
    'Bienvenue Premium !', 'Premium activé !', 'Nouveau filleul !',
    'Parrainage récompensé !', 'Commission L\\d+ reçue !',
  ].join('|')
  + ')$', 'u');

export function harmoniserNotification<T extends { title: string; body: string }>(n: T): T {
  let title = n.title;
  const m = ANCIEN_TITRE.exec(title);
  if (m) {
    title = m[1]
      .replace('Pronostic Gagnant', 'Pronostic gagnant')
      .replace('Pronostic Perdant', 'Pronostic perdant');
  }
  const body = n.body
    .replace('Votre bankroll est mis à jour', 'Votre bankroll est mise à jour')
    .replace(/(\d) (?:XOF|XAF)\b/g, '$1 FCFA');
  return title === n.title && body === n.body ? n : { ...n, title, body };
}

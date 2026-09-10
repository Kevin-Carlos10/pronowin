/**
 * Traduction des recommandations d'API-Football.
 *
 * Le champ `advice` arrive en anglais et était relayé tel quel jusqu'à
 * l'écran : « Combo Double chance : draw or Barcelona and -2.5 goals » au
 * milieu d'une interface française, précisément dans l'encart censé expliquer
 * *pourquoi* parier. C'est l'endroit où il est le plus coûteux de perdre le
 * lecteur.
 *
 * La grammaire du fournisseur est régulière — relevée sur des réponses réelles :
 *
 *     Winner : Alaves
 *     Double chance : Atletico Madrid or draw
 *     Double chance : draw or Real Madrid
 *     Combo Double chance : draw or Barcelona and -2.5 goals
 *     Combo Winner : Barcelona and +1.5 goals
 *     No predictions available
 *
 * On la traduit donc par analyse, et non par table de correspondance : les noms
 * d'équipes sont arbitraires et ne doivent surtout pas être touchés.
 *
 * **Une forme inconnue est renvoyée intacte, pas approximée.** Mieux vaut une
 * phrase anglaise lisible qu'une traduction fausse sur un conseil de pari — et
 * l'avertissement journalisé fait remonter la forme manquante.
 */

/** Seuil de buts : « -2.5 goals » → « moins de 2.5 buts ». */
function seuilButs(signe: string, nombre: string): string {
  const sens = signe === '-' ? 'moins' : 'plus';
  // La virgule décimale est la convention francophone.
  return `${sens} de ${nombre.replace('.', ',')} but${parseFloat(nombre) >= 2 ? 's' : ''}`;
}

/** « draw » est le seul terme non nominal des positions d'équipe. */
function equipe(nom: string): string {
  return nom.trim() === 'draw' ? 'match nul' : nom.trim();
}

export function traduireRecommandation(advice: string | null | undefined): string | null {
  if (advice == null) return null;
  const texte = advice.trim();
  if (texte === '') return null;

  // ── Aucun conseil ────────────────────────────────────────────────────────
  if (/^no predictions? available$/i.test(texte)) {
    return 'Aucune recommandation disponible';
  }
  if (/^no bet$/i.test(texte)) {
    return 'Aucun pari conseillé';
  }

  // ── Combiné double chance ────────────────────────────────────────────────
  let m = texte.match(
    /^Combo Double chance\s*:\s*(.+?)\s+or\s+(.+?)\s+and\s+([+-])([\d.]+)\s+goals?$/i);
  if (m) {
    return `Double chance : ${equipe(m[1])} ou ${equipe(m[2])}, ` +
           `combiné avec ${seuilButs(m[3], m[4])}`;
  }

  // ── Combiné vainqueur ────────────────────────────────────────────────────
  m = texte.match(/^Combo Winner\s*:\s*(.+?)\s+and\s+([+-])([\d.]+)\s+goals?$/i);
  if (m) {
    return `Vainqueur : ${equipe(m[1])}, combiné avec ${seuilButs(m[2], m[3])}`;
  }

  // ── Double chance simple ─────────────────────────────────────────────────
  m = texte.match(/^Double chance\s*:\s*(.+?)\s+or\s+(.+?)$/i);
  if (m) {
    return `Double chance : ${equipe(m[1])} ou ${equipe(m[2])}`;
  }

  // ── Vainqueur simple ─────────────────────────────────────────────────────
  m = texte.match(/^Winner\s*:\s*(.+?)$/i);
  if (m) {
    return `Vainqueur : ${equipe(m[1])}`;
  }

  // ── Seuil de buts seul ───────────────────────────────────────────────────
  m = texte.match(/^([+-])([\d.]+)\s+goals?$/i);
  if (m) {
    const s = seuilButs(m[1], m[2]);
    return s.charAt(0).toUpperCase() + s.slice(1);
  }

  console.warn(`[Recommandation] Forme non traduite : « ${texte} »`);
  return texte;
}

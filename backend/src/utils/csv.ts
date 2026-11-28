/**
 * Une cellule CSV qu'un tableur lit comme du texte, et seulement comme du texte.
 *
 * Les exports entouraient chaque valeur de guillemets — `"${v}"` — sans
 * doubler ceux qu'elle contenait. Un pseudo comme `Le "boss"` décalait donc
 * toutes les colonnes suivantes de sa ligne.
 *
 * Plus grave : une valeur qui commence par `=`, `+`, `-` ou `@` est une
 * formule pour Excel, LibreOffice ou Google Sheets, guillemets ou pas. Le
 * pseudo est choisi par l'utilisateur ; un pseudo comme
 * `=HYPERLINK("https://…";"Voir")` s'exécutait dans le tableur de
 * l'administrateur qui ouvrait l'export (constat A16 de l'audit du
 * 24 septembre 2026). La parade recommandée par l'OWASP est de préfixer ces
 * valeurs d'une apostrophe, que le tableur n'affiche pas et qui force le
 * texte.
 *
 * Les nombres ne sont pas préfixés : un montant négatif doit rester un nombre.
 * Un numéro de téléphone (`+226…`) est une chaîne, il l'est — c'est ce qui
 * l'empêche d'être converti en nombre et d'y perdre son indicatif.
 */
export function celluleCsv(valeur: unknown): string {
  if (valeur === null || valeur === undefined) return '""';
  if (typeof valeur === 'number' || typeof valeur === 'bigint') return String(valeur);
  let texte = (valeur instanceof Date ? valeur.toISOString() : String(valeur))
    .replace(/\r\n|\r|\n/g, ' ');
  if (/^[=+\-@\t\r]/.test(texte)) texte = "'" + texte;
  return '"' + texte.replace(/"/g, '""') + '"';
}

/** Une ligne CSV, séparée par des virgules. */
export function ligneCsv(valeurs: unknown[]): string {
  return valeurs.map(celluleCsv).join(',');
}

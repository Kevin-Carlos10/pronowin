/**
 * L'extrait d'un texte, coupé à un mot entier et terminé par « … ».
 *
 * Les résumés d'actualités étaient tranchés au 300ᵉ caractère, en plein mot
 * et sans points de suspension (« … la sélection affrontera la Belgi ») :
 * le lecteur ne savait pas si le texte s'arrêtait là ou s'il manquait la
 * suite (vidéo du 5 octobre 2026).
 *
 * Les marques de coupure des flux (« [...] », « [&#8230;] ») deviennent un
 * simple « … ».
 */
export function extraitTexte(texte: string | null | undefined, max = 300): string {
  let t = (texte ?? '')
    .replace(/\s*\[(?:\.\.\.|…|&#8230;|&hellip;)\]\s*$/u, '…')
    .replace(/\s+/g, ' ')
    .trim();
  if (t.length <= max) return t;

  const motEntier = t[max] === ' ';
  t = t.slice(0, max);
  const espace = t.lastIndexOf(' ');
  // Un mot unique plus long que l'extrait reste coupé, faute de mieux.
  if (!motEntier && espace > max / 2) t = t.slice(0, espace);
  return t.replace(/[\s,;:.\-–—…]+$/u, '') + '…';
}

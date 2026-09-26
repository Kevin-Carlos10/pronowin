/**
 * Le code d'un fichier, sans ses commentaires.
 *
 * Les commentaires de ce projet citent volontairement ce qui a été supprimé :
 * c'est ce qui rend les corrections compréhensibles des mois plus tard. Un
 * contrôle qui lit le fichier entier se valide donc sur sa propre explication.
 *
 * Le détail des quatre fois où le piège s'est refermé en une seule séance est
 * dans `mobile_new/test/aides/code_seul.dart`.
 *
 * Lire le code reste un pis-aller : il dit ce qui est écrit, pas ce qui se
 * produit. Quand un comportement peut être exercé, l'exercer vaut mieux.
 */
export function codeSeul(source: string): string {
  return source
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .split('\n')
    .filter((l) => {
      const t = l.trimStart();
      return !t.startsWith('//') && !t.startsWith('*');
    })
    .join('\n');
}

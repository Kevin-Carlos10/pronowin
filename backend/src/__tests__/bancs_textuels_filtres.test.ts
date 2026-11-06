import fs from 'fs';
import path from 'path';

/**
 * Un contrôle qui lit du code ne doit pas lire ses propres commentaires.
 *
 * ── Le piège, et pourquoi il est propre à ce dépôt ────────────────────────
 *
 * Beaucoup de contrôles ici lisent une source et y cherchent une phrase : un
 * libellé retiré, une valeur qui ne doit plus être écrite en dur, un texte qui
 * doit être affiché.
 *
 * Or les commentaires de ce projet **citent volontairement** ce qui a été
 * supprimé — c'est ce qui rend les corrections compréhensibles des mois plus
 * tard. Un contrôle qui lit le fichier entier se valide donc sur sa propre
 * explication.
 *
 * Il s'est refermé quatre fois dans une seule séance, sur des contrôles
 * écrits le jour même :
 *
 *   · « optimales » cherché dans toute la page, alors que le commentaire
 *     expliquait pourquoi ce mot avait été retiré ;
 *   · « 30 jours » trouvé dans un sous-titre voisin, laissant la confirmation
 *     se taire sans que rien ne tombe ;
 *   · « canLaunchUrl » interdit partout, alors que le commentaire doit le
 *     nommer pour dire pourquoi il est écarté ;
 *   · un domaine mort cité dans l'explication de son propre retrait.
 *
 * Dans un sens le contrôle échoue sur du code juste ; dans l'autre il passe
 * sur du code faux. Le second est le plus coûteux : il donne une confiance
 * qui n'est adossée à rien.
 *
 * ── Ce que ce contrôle exige ──────────────────────────────────────────────
 *
 * Qu'un banc cherchant une **phrase** dans une source passe par `codeSeul`.
 *
 * Les assertions sur un identifiant — `bandeauCotes(`, `AppConstants.domaine`
 * — ne sont pas visées : un commentaire les reproduit rarement à l'identique,
 * et les exiger filtrées alourdirait sans rien protéger. Le critère est donc
 * la prose : deux mots séparés par une espace.
 *
 * ── Ce que cela ne remplace pas ───────────────────────────────────────────
 *
 * Lire le code reste un pis-aller. Il dit ce qui est écrit, pas ce qui se
 * produit — c'est tout l'objet de T3 dans l'audit. Quand un comportement peut
 * être exercé, l'exercer vaut mieux que de chercher sa trace.
 */
const RACINE = path.join(__dirname, '..', '..', '..');

const DOSSIERS = [
  path.join(RACINE, 'mobile_new', 'test'),
  path.join(RACINE, 'backend', 'src', '__tests__'),
];

/** Un banc lit-il une source du projet ? */
const LIT_UNE_SOURCE = /readAsStringSync|readFileSync/;

/** Le filtrage est-il appliqué, sous une forme ou une autre ? */
const FILTRE = /codeSeul|pipeCodeSeul|startsWith\('\/\/'\)|startsWith\("\/\/"\)/;

/**
 * Une assertion portant sur de la prose : la chaîne attendue contient deux
 * mots séparés par une espace, minuscules accentuées comprises.
 */
const PROSE = /(?:contains|toContain)\('([^']*[a-zà-ÿ] [a-zà-ÿ][^']*)'\)/g;

function bancs(): string[] {
  return DOSSIERS.flatMap((d) =>
    fs.existsSync(d)
      ? fs
          .readdirSync(d)
          .filter((n) => n.endsWith('_test.dart') || n.endsWith('.test.ts'))
          .map((n) => path.join(d, n))
      : [],
  );
}

describe('les contrôles textuels ignorent les commentaires', () => {
  const fichiers = bancs();

  it('il y a bien des bancs à examiner', () => {
    // Un parcours vide rendrait le contrôle suivant vrai pour rien — c'est
    // exactement la forme de faux positif qu'il combat.
    expect(fichiers.length).toBeGreaterThan(50);
  });

  it('aucun ne cherche une phrase dans une source non filtrée', () => {
    const fautifs: string[] = [];

    for (const f of fichiers) {
      const source = fs.readFileSync(f, 'utf8');
      if (!LIT_UNE_SOURCE.test(source)) continue;
      if (FILTRE.test(source)) continue;

      const phrases = [...source.matchAll(PROSE)]
        .map((m) => m[1])
        .filter((p) => p.length >= 8);

      if (phrases.length > 0) {
        fautifs.push(`${path.basename(f)} — ${phrases.length} assertion(s)`);
      }
    }

    expect(fautifs).toEqual([]);
  });

  it("l'aide de filtrage existe des deux côtés", () => {
    // Exiger le motif sans le fournir obligerait chacun à le réécrire, et
    // deux écritures du même filtrage finiraient par diverger.
    expect(fs.existsSync(
      path.join(RACINE, 'mobile_new', 'test', 'aides', 'code_seul.dart'),
    )).toBe(true);
    expect(fs.existsSync(path.join(__dirname, 'aides', 'code_seul.ts'))).toBe(true);
  });
});

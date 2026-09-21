import fs from 'fs';
import path from 'path';

/**
 * Un pourcentage affiché par le site doit être un pourcentage que l'application
 * sait produire.
 *
 * ── Ce qui était écrit ────────────────────────────────────────────────────
 *
 * L'aperçu « Pronostics » de la page d'accueil montrait trois lignes :
 *
 *     Real Madrid vs Barcelone — Confiance 78 %  ·  Cote 1.72
 *     Bayern vs Dortmund       — Confiance 55 %  ·  Cote 2.10
 *     Juventus vs Milan        — Confiance 71 %  ·  Cote 1.95
 *
 * Or la confiance est un entier de 1 à 5, converti par une table fixe —
 * 60, 70, 80, 90, 95. Aucun des trois nombres n'était atteignable. En
 * production, seuls les scores 3 à 5 sont publiés : 80, 90 et 95.
 *
 * ── Pourquoi cela comptait ────────────────────────────────────────────────
 *
 * `server.js` pose lui-même la règle, quinze lignes au-dessus de l'aperçu :
 * « Chaque chiffre cité ici doit exister dans le produit : c'est la page qui
 * vend, donc celle où une approximation devient un engagement. »
 *
 * Elle n'était pas appliquée juste en dessous. C'est la forme la plus commune
 * du défaut traqué dans ce dépôt : une règle énoncée à un endroit et oubliée à
 * quelques lignes de là.
 *
 * Un aperçu a le droit d'illustrer une mise en page. Dès qu'il porte un nombre,
 * il affirme — et sur une page qui vend du pari, un pourcentage de confiance
 * inventé est exactement ce qui fixe une attente fausse avant le premier euro
 * misé.
 *
 * ── Ce que ce banc tient ──────────────────────────────────────────────────
 *
 * Il lit les **deux** sources : la liste du site et la table de l'application.
 * Aucune valeur n'est recopiée ici. Changer la table côté application sans
 * revoir le site, ou l'inverse, fait tomber le contrôle — ce qu'une constante
 * écrite dans le banc n'aurait pas permis.
 */
const RACINE = path.join(__dirname, '..', '..', '..');
const SITE = path.join(RACINE, 'website', 'server.js');
const ENTITE = path.join(
  RACINE, 'mobile_new', 'lib', 'features', 'pronostics',
  'domain', 'entities', 'match_entity.dart',
);

/** Le code seul : les commentaires citent les valeurs retirées, à dessein. */
function codeSeul(source: string): string {
  return source
    .split('\n')
    .filter((l) => {
      const t = l.trimStart();
      return !t.startsWith('//') && !t.startsWith('///') && !t.startsWith('*');
    })
    .join('\n');
}

/** Les pourcentages que l'application peut afficher, lus dans sa table. */
function pourcentagesDuProduit(): number[] {
  const dart = codeSeul(fs.readFileSync(ENTITE, 'utf8'));
  const table = /_confidencePercentByScore\s*=\s*\{([^}]*)\}/.exec(dart);
  if (!table) throw new Error('table de conversion introuvable dans match_entity.dart');

  return [...table[1].matchAll(/\d+\s*:\s*(\d+)/g)].map((m) => Number(m[1]));
}

/** Les pourcentages que le site annonce, lus dans ses données. */
function pourcentagesDuSite(): number[] {
  const js = codeSeul(fs.readFileSync(SITE, 'utf8'));
  return [...js.matchAll(/Confiance\s+(\d+)\s*%/g)].map((m) => Number(m[1]));
}

describe('les chiffres du site existent dans le produit', () => {
  it('la table de conversion est bien lue', () => {
    // Sans cette vérification, une table introuvable rendrait le contrôle
    // suivant vrai pour rien — la forme de faux positif la plus courante ici.
    //
    // Contrôlée sans citer aucune valeur : ce banc affirme plus haut ne rien
    // recopier, et une sentinelle écrite `toContain(95)` aurait démenti cette
    // phrase tout en tombant le jour d'un simple réglage de l'échelle.
    const p = pourcentagesDuProduit();
    expect(p.length).toBeGreaterThanOrEqual(5);
    expect(p.every((v) => v > 0 && v <= 100)).toBe(true);
    expect([...p].sort((x, y) => x - y)).toEqual(p);
  });

  it('le site annonce bien des pourcentages de confiance', () => {
    expect(pourcentagesDuSite().length).toBeGreaterThan(0);
  });

  it("aucun pourcentage annoncé n'est hors de l'échelle", () => {
    const possibles = pourcentagesDuProduit();
    const inatteignables = pourcentagesDuSite().filter((v) => !possibles.includes(v));

    expect(inatteignables).toEqual([]);
  });

  it('la règle reste écrite là où elle doit être relue', () => {
    // Le banc dit « non » ; le commentaire dit « pourquoi ». Retirer l'un des
    // deux laisse la moitié du travail : on saurait que c'est interdit sans
    // savoir ce qu'on a le droit d'écrire à la place.
    const js = fs.readFileSync(SITE, 'utf8');
    expect(js).toContain('doit exister dans le produit');
  });
});

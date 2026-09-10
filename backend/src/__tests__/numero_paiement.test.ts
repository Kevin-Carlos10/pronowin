import fs from 'fs';
import path from 'path';

/**
 * Le numéro de paiement n'a qu'une source : la table `payment_methods`.
 *
 * Constaté depuis l'administration : masquer le seul opérateur affichait
 * `+226 74 70 30 70` dans l'application, alors que le numéro configuré était
 * `22645568158`. **Deux numéros différents** — et c'est vers celui-là que les
 * abonnés envoyaient leur argent.
 *
 * La cause tient en une ligne : `findMany({ where: { isActive: true } })` rend
 * zéro ligne aussi bien quand la table est vide que lorsque tout a été masqué
 * volontairement. Le repli sur `process.env.MOBCASH_ORANGE` ne pouvait pas
 * distinguer les deux, et choisissait toujours d'afficher quelque chose.
 *
 * L'application avait déjà perdu son propre repli pour cette raison exacte.
 * Son commentaire dit même que le serveur écarte les entrées sans téléphone
 * « pour qu'une installation mal configurée n'affiche aucun moyen de paiement
 * plutôt qu'un faux numéro ». Le serveur faisait l'inverse.
 *
 * Ce contrôle lit la source plutôt que d'exécuter la requête : ce qu'on veut
 * interdire, c'est qu'un second gisement de numéros réapparaisse ici — pas un
 * comportement d'exécution qu'un futur repli contournerait tout aussi bien.
 */
const SOURCE = path.join(__dirname, '..', 'services', 'payment_method.service.ts');

/** Le fichier sans ses commentaires : ils citent `MOBCASH_ORANGE` pour
 *  expliquer le défaut, et un contrôle qui se valide sur sa propre prose ne
 *  contrôle rien. */
function codeSeul(): string {
  return fs.readFileSync(SOURCE, 'utf8')
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .split('\n')
    .filter((l) => !l.trimStart().startsWith('//'))
    .join('\n');
}

describe('source unique du numéro de paiement', () => {
  it('aucun numéro ne vient de l\'environnement', () => {
    const code = codeSeul();

    expect(code).not.toMatch(/MOBCASH/);
    expect(code).not.toMatch(/process\.env/);
  });

  it('aucune liste de repli n\'est déclarée', () => {
    const code = codeSeul();

    // Le nom exact importe peu : ce qui doit disparaître, c'est un tableau de
    // méthodes écrit dans le fichier, quel que soit son nom.
    expect(code).not.toMatch(/REPLI/);
    expect(code).not.toMatch(/orange_money['"]?\s*,/);
  });

  it('zéro ligne active rend une liste vide, pas autre chose', () => {
    const code = codeSeul();

    // La forme `lignes.length ? lignes : X` est précisément celle qui ne sait
    // pas distinguer « table vide » de « tout masqué ».
    expect(code).not.toMatch(/lignes\.length\s*\?/);
    expect(code).toMatch(/return\s+lignes\s*;/);
  });

  it('une base injoignable ne devine pas un numéro', () => {
    const code = codeSeul();
    const attrape = code.slice(code.indexOf('} catch'));

    expect(attrape).toMatch(/return\s*\[\s*\]\s*;/);
  });
});

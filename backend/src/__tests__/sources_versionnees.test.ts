import fs from 'fs';
import path from 'path';

/**
 * Ce qu'un commit doit suffire à reconstruire.
 *
 * ── Ce qui manquait ───────────────────────────────────────────────────────
 *
 * `.gitignore` excluait `backend/prisma/migrations/` et
 * `mobile_new/pubspec.lock`, tous deux rangés sous « Build / Generated ».
 *
 * Trente migrations existaient sur le disque et **aucune** dans le dépôt —
 * y compris celle qui a ajouté `ussd_template` et qui tourne en production.
 * Un clone neuf recevait `schema.prisma` sans le moyen de construire la base
 * qui lui correspond : `prisma migrate deploy` n'avait rien à appliquer.
 *
 * ── Pourquoi le classement était l'erreur ─────────────────────────────────
 *
 * Une migration n'est pas un artefact produit. C'est la source de l'évolution
 * du schéma, et c'est elle que la production exécute. On peut régénérer un
 * `dist/` ; on ne régénère pas l'histoire d'une base.
 *
 * Quant au verrou de dépendances : ne pas le versionner est la règle d'une
 * bibliothèque, dont les versions sont résolues par qui l'utilise. Ceci est
 * une application. Sans verrou, deux constructions du même commit peuvent
 * embarquer des versions différentes — et un défaut apparu en production
 * n'est pas reproductible sur le poste qui l'a produit.
 *
 * ── Ce que ce contrôle tient ──────────────────────────────────────────────
 *
 * Que ces chemins ne redeviennent pas invisibles. La règle avait été écrite
 * une fois, dans la bonne intention, et rien ne l'a plus jamais relue.
 */
const RACINE = path.join(__dirname, '..', '..', '..');

/** Les règles actives de `.gitignore`, commentaires et lignes vides retirés. */
function reglesIgnorees(): string[] {
  return fs
    .readFileSync(path.join(RACINE, '.gitignore'), 'utf8')
    .split('\n')
    .map((l) => l.trim())
    .filter((l) => l.length > 0 && !l.startsWith('#'));
}

describe('un commit reconstruit la base et les dépendances', () => {
  it("les migrations Prisma ne sont plus ignorées", () => {
    const fautives = reglesIgnorees().filter((r) => r.includes('prisma/migrations'));
    expect(fautives).toEqual([]);
  });

  it('le verrou de dépendances Flutter ne l\'est plus non plus', () => {
    const fautives = reglesIgnorees().filter((r) => r.includes('pubspec.lock'));
    expect(fautives).toEqual([]);
  });

  it('les deux fichiers existent réellement', () => {
    // Retirer la règle sans que le fichier soit là ne reconstruit rien.
    expect(fs.existsSync(path.join(RACINE, 'mobile_new', 'pubspec.lock'))).toBe(true);
    expect(fs.existsSync(
      path.join(RACINE, 'backend', 'prisma', 'migrations', 'migration_lock.toml'),
    )).toBe(true);
  });

  it("l'historique des migrations n'est pas vide", () => {
    const dossier = path.join(RACINE, 'backend', 'prisma', 'migrations');
    const migrations = fs
      .readdirSync(dossier)
      .filter((n) => fs.statSync(path.join(dossier, n)).isDirectory());

    expect(migrations.length).toBeGreaterThan(0);

    // Chaque dossier doit porter son SQL : un dossier vide passerait le
    // décompte sans rien reconstruire.
    for (const m of migrations) {
      expect(fs.existsSync(path.join(dossier, m, 'migration.sql'))).toBe(true);
    }
  });

  it("le classement « Build / Generated » ne les reprend pas", () => {
    // La cause première : rangées avec `dist/` et `.dart_tool/`, elles ont
    // paru régénérables. Le contrôle vise la section, pas seulement la ligne.
    // Découpé ligne par ligne, et non par recherche de tirets : la première
    // version s'arrêtait sur ceux du titre lui-même, ce qui la rendait vide.
    // Elle restait verte quand on remettait la règle — vérifié par injection.
    const lignes = fs
      .readFileSync(path.join(RACINE, '.gitignore'), 'utf8')
      .split('\n')
      .map((l) => l.trim());

    const debut = lignes.findIndex((l) => l.includes('Build / Generated'));
    expect(debut).toBeGreaterThan(-1);

    const suite = lignes.slice(debut + 1);
    const fin = suite.findIndex((l) => l.startsWith('#') && l.includes('──'));
    const section = suite.slice(0, fin === -1 ? suite.length : fin);

    // Les commentaires citent le chemin retiré pour expliquer pourquoi il
    // l'a été ; seules les règles actives comptent.
    const actives = section.filter((l) => l.length > 0 && !l.startsWith('#'));
    expect(actives.filter((l) => l.includes('prisma/migrations'))).toEqual([]);
  });
});

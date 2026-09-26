import * as fs from 'fs';
import * as path from 'path';
import { execFileSync } from 'child_process';

/**
 * Aucun fichier source ne doit contenir de texte mal décodé.
 *
 * `pronostics.service.ts` a vécu depuis le commit initial avec ses accents
 * corrompus : « Le match est termin茅. Consultez le r茅sultat de votre
 * pronostic. » partait en notification push à tous les utilisateurs ayant mis
 * le match en favori. Le fichier compilait, les tests passaient, l'API
 * répondait 200 — le défaut n'était visible que sur le téléphone, dans la
 * liste des notifications, et personne ne l'a lu pendant six semaines.
 *
 * La corruption vient d'un fichier UTF-8 relu dans un jeu de caractères
 * chinois puis réenregistré : `é` (octets C3 A9) devient `茅`, `·` devient
 * `路`. Un éditeur mal configuré, un copier-coller à travers un terminal, un
 * script qui réécrit sans préciser l'encodage — il suffit d'une fois.
 *
 * Ce contrôle balaie tout le dépôt, pas seulement le backend : la faute peut
 * frapper une vue EJS, un fichier Dart ou un gabarit du site aussi bien qu'un
 * service TypeScript. Il vit ici parce que c'est ici qu'elle a frappé, et
 * parce que c'est la seule suite qui tourne sur l'ensemble du dépôt.
 */

/** Idéogrammes CJK et ponctuation pleine largeur : jamais dans du code français. */
const CJK = /[　-〿一-鿿＀-￯]/;

/**
 * Séquences typiques d'UTF-8 relu en Latin-1 / CP1252.
 *
 * L'autre grande famille de corruption. Volontairement restreinte à des
 * suites qui n'ont aucun sens en français, pour ne pas accuser un texte
 * légitime.
 */
const LATIN1 = /Ã[©¨ ¢ª§«»]|â€[™œ“]|Â[«»°·]/;

const RACINE = path.resolve(__dirname, '..', '..', '..');

const EXTENSIONS = new Set([
  '.ts', '.js', '.mjs', '.cjs', '.dart', '.ejs', '.json',
  '.html', '.css', '.md', '.yaml', '.yml',
]);

/**
 * Les fichiers suivis par git, filtrés sur les extensions de source.
 *
 * Le premier jet parcourait l'arborescence avec une liste de dossiers à
 * ignorer. Il a accusé `sauvegarde_depot_retrait_20260812_083257/` — une copie
 * du dépôt datant d'août, déjà ignorée par git, que personne ne déploie. Une
 * liste écrite à la main est toujours en retard d'un dossier ; `git ls-files`
 * dit exactement ce qui part en production.
 */
function fichiersSources(): string[] {
  const sortie = execFileSync('git', ['ls-files', '-z'], {
    cwd: RACINE,
    encoding: 'utf8',
    maxBuffer: 32 * 1024 * 1024,
  });
  return sortie
    .split('\0')
    .filter((f) => f && EXTENSIONS.has(path.extname(f)))
    .map((f) => path.join(RACINE, f))
    .filter((f) => fs.existsSync(f));
}

describe('encodage des sources', () => {
  const fichiers = fichiersSources();

  it('trouve des fichiers à contrôler', () => {
    // Une arborescence mal résolue rendrait ce contrôle vert et vide.
    expect(fichiers.length).toBeGreaterThan(200);
  });

  it('aucun fichier ne contient de texte mal décodé', () => {
    const fautes: string[] = [];

    for (const fichier of fichiers) {
      // Ce fichier-ci cite les formes corrompues pour les expliquer.
      if (fichier === __filename) continue;

      const lignes = fs.readFileSync(fichier, 'utf8').split('\n');
      lignes.forEach((ligne, i) => {
        const motif = CJK.test(ligne) ? 'CJK' : LATIN1.test(ligne) ? 'Latin-1' : null;
        if (!motif) return;
        fautes.push(
          `${path.relative(RACINE, fichier)}:${i + 1} [${motif}] ${ligne.trim().slice(0, 90)}`,
        );
      });
    }

    expect(fautes).toEqual([]);
  });
});

import fs from 'fs';
import path from 'path';

/**
 * L'avis `uuid` qui reste, et pourquoi il n'est pas corrigé.
 *
 * ── Ce qui a été corrigé ──────────────────────────────────────────────────
 *
 * L'audit relevait 16 avis sur les dépendances de production : 1 critique,
 * 2 élevés, 13 modérés. Six des sept causes racines avaient un correctif sans
 * rupture ; il a été appliqué. Il reste huit entrées, toutes modérées, et
 * toutes remontant au **même** avis :
 *
 *     uuid — absence de contrôle de bornes sur un tampon, en v3/v5/v6
 *
 * `@google-cloud/storage`, `firestore`, `gaxios`, `google-gax`,
 * `retry-request` et `teeny-request` n'y figurent que parce qu'ils en
 * dépendent. Huit lignes, un seul défaut.
 *
 * ── Pourquoi il n'est pas corrigé ─────────────────────────────────────────
 *
 * npm ne propose qu'un chemin : `firebase-admin` de 12 à 14, deux versions
 * majeures, qui touchent l'authentification, la messagerie et Firestore —
 * c'est-à-dire la connexion, les notifications et la base.
 *
 * Or l'avis vise `v3`, `v5` et `v6` appelés avec un tampon fourni. Le code
 * applicatif n'importe jamais `uuid`, et le seul appel de toute la chaîne
 * Google est `uuid.v4`, qui n'est pas concerné.
 *
 * Deux montées majeures pour un défaut qu'aucun chemin n'atteint, ce serait
 * échanger un risque théorique contre un risque réel.
 *
 * ── Ce que ce banc tient ──────────────────────────────────────────────────
 *
 * Cette conclusion dépend d'un fait qui peut changer : personne n'appelle
 * v3/v5/v6. Le jour où quelqu'un s'en sert — pour un identifiant déterministe,
 * par exemple — l'avis redevient atteignable et la décision doit être reprise.
 *
 * Ce contrôle le dira. Sans lui, l'analyse resterait vraie sur le papier et
 * fausse dans le code, ce qui est exactement la forme de défaut que ce projet
 * traque.
 */
const SRC = path.join(__dirname, '..');

/** Tous les fichiers TypeScript de l'application, tests exclus. */
function sources(dossier: string): string[] {
  return fs.readdirSync(dossier, { withFileTypes: true }).flatMap((e) => {
    const p = path.join(dossier, e.name);
    if (e.isDirectory()) return e.name === '__tests__' ? [] : sources(p);
    return e.name.endsWith('.ts') ? [p] : [];
  });
}

describe('avis uuid : la raison de ne pas le corriger tient toujours', () => {
  const fichiers = sources(SRC);

  it('il y a bien des sources à examiner', () => {
    // Un parcours vide rendrait les contrôles suivants vrais pour rien.
    expect(fichiers.length).toBeGreaterThan(20);
  });

  it("l'application n'appelle pas uuid en v3, v5 ou v6", () => {
    const fautifs: string[] = [];
    for (const f of fichiers) {
      const code = fs
        .readFileSync(f, 'utf8')
        .split('\n')
        .filter((l) => !l.trimStart().startsWith('//') && !l.trimStart().startsWith('*'))
        .join('\n');

      if (/\buuid\s*\.\s*v[356]\b/.test(code) || /\b(v3|v5|v6)\s*as\s+uuid/.test(code)) {
        fautifs.push(path.relative(SRC, f));
      }
    }

    expect(fautifs).toEqual([]);
  });

  it("elle n'importe même pas uuid", () => {
    // Le contrôle large : tant que le paquet n'entre pas dans le code
    // applicatif, l'avis reste hors de portée quoi qu'il arrive en aval.
    const fautifs = fichiers.filter((f) => {
      const code = fs.readFileSync(f, 'utf8');
      return /from\s+['"]uuid['"]|require\(\s*['"]uuid['"]\s*\)/.test(code);
    });

    expect(fautifs.map((f) => path.relative(SRC, f))).toEqual([]);
  });
});

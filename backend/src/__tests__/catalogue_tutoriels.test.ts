import * as fs from 'fs';
import * as path from 'path';

/**
 * Le catalogue de repli ne doit ni verrouiller ni ressusciter.
 *
 * `tutorial.service.ts` porte une liste `DEMO_TUTORIALS` servie quand la
 * requête Prisma échoue. Le `catch` est large : n'importe quelle erreur de
 * base la déclenche, pas seulement une table vide. C'est donc un second
 * catalogue, écrit à la main, que personne ne relit — et qui a divergé.
 *
 * Deux divergences constatées le même jour :
 *
 *   - deux tutoriels y restaient `is_premium: true` alors que la table de
 *     production ne verrouille plus rien. Les vidéos sont des intégrations
 *     YouTube, et en faire payer l'accès contrevient aux conditions de la
 *     plateforme qui les héberge. Un incident Postgres suffisait à remettre
 *     le paywall en service ;
 *
 *   - « Stratégie des handicaps asiatiques », retiré de la table parce que
 *     la vignette de sa vidéo affichait les marques PINNACLE, PS3838,
 *     PIWI247 et 1XBET dans le build destiné à Google Play, y figurait
 *     encore. Le repli l'aurait remis en ligne.
 *
 * ── Ce que ce contrôle vaut, et ce qu'il ne vaut pas ──────────────────────
 *
 * Il ne peut pas comparer le repli à la table : celle-ci vit en production.
 * Il vérifie la règle qui tient aujourd'hui — aucun contenu tiers derrière un
 * paywall — et signale nommément le tutoriel retiré.
 *
 * Le jour où PronoWin produira ses propres vidéos, un tutoriel Premium
 * redeviendra légitime : ce test devra alors distinguer les vidéos maison des
 * intégrations tierces, au lieu d'interdire le drapeau. Le changer sera un
 * acte délibéré, ce qui est exactement le but.
 */

const FICHIER = path.resolve(__dirname, '..', 'services', 'tutorial.service.ts');

describe('catalogue de repli des tutoriels', () => {
  const source = fs.readFileSync(FICHIER, 'utf8');

  it('la liste de repli existe toujours', () => {
    // Si elle disparaît ou change de nom, les contrôles ci-dessous
    // deviendraient verts en n'inspectant plus rien.
    expect(source).toContain('const DEMO_TUTORIALS');
    expect(source.match(/id: 'tut_\d+'/g)?.length ?? 0).toBeGreaterThan(0);
  });

  it('aucun tutoriel de repli n\'est marqué Premium', () => {
    const premium = source.match(/is_premium:\s*true/g) ?? [];
    expect(premium).toEqual([]);
  });

  it('le tutoriel retiré du catalogue n\'y figure plus', () => {
    expect(source).not.toContain('handicaps asiatiques\'');
  });
});

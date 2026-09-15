import * as fs from 'fs';
import * as path from 'path';

/**
 * Le catalogue de repli a été retiré, et il ne doit pas revenir.
 *
 * ── Ce qu'il était ────────────────────────────────────────────────────────
 *
 * `tutorial.service.ts` portait une liste `DEMO_TUTORIALS`, servie quand la
 * requête Prisma échouait. Le `catch` était large : n'importe quelle erreur de
 * base la déclenchait. Une table vide, elle, n'y passait jamais — elle rend
 * `[]`, qui est un état vide légitime que l'écran sait annoncer.
 *
 * Le seul cas où ce repli sortait était donc une **panne**. L'utilisateur
 * recevait alors un catalogue qui n'est pas le nôtre — d'autres titres,
 * d'autres identifiants, à la place des quatre tutoriels réels — et personne
 * n'était averti de la panne. Un identifiant inconnu rendait de même un
 * tutoriel de démonstration, que l'utilisateur ne pouvait retrouver dans
 * aucune liste.
 *
 * ── Pourquoi le supprimer plutôt que le surveiller ────────────────────────
 *
 * C'était un second catalogue, écrit à la main, que personne ne relisait. Il a
 * divergé trois fois, et il a fallu un banc à chaque fois :
 *
 *   - ses compteurs étaient inventés — 4 823 vues et 4,7 étoiles en dur, pour
 *     une application qui comptait six comptes ;
 *
 *   - deux tutoriels y restaient `is_premium: true` alors que la table ne
 *     verrouille plus rien. Les vidéos sont des intégrations YouTube, et en
 *     faire payer l'accès contrevient aux conditions de la plateforme qui les
 *     héberge : un incident Postgres suffisait à remettre le paywall en
 *     service ;
 *
 *   - « Stratégie des handicaps asiatiques », retiré de la table parce que la
 *     vignette de sa vidéo affichait les marques PINNACLE, PS3838, PIWI247 et
 *     1XBET dans le build destiné à Google Play, y figurait encore. Le repli
 *     l'aurait remis en ligne.
 *
 * Un repli qu'il faut corriger pour qu'il cesse de mentir vaut moins qu'une
 * erreur franche. Ce banc garde donc son absence, et le silence qu'il créait.
 */

const FICHIER = path.resolve(__dirname, '..', 'services', 'tutorial.service.ts');

describe('catalogue des tutoriels', () => {
  const source = fs.readFileSync(FICHIER, 'utf8');

  it('aucun catalogue écrit en dur ne subsiste', () => {
    expect(source).not.toContain('const DEMO_TUTORIALS');
    expect(source.match(/id: 'tut_\d+'/g) ?? []).toEqual([]);
  });

  it('une panne de base remonte au lieu d\'être déguisée', () => {
    // Le `catch (_)` rendait un catalogue. Il doit désormais relancer, pour
    // que l'application affiche son état d'erreur et propose de réessayer.
    expect(source).not.toContain('} catch (_) {');

    const relances = source.match(/throw e;/g) ?? [];
    expect(relances.length).toBeGreaterThanOrEqual(2);
  });

  it('la panne laisse une trace dans les journaux', () => {
    // Le défaut n'était pas seulement de servir autre chose : c'était de le
    // faire sans que personne ne l'apprenne.
    expect(source).toContain('[Tutoriels]');
  });

  it('un identifiant inconnu est un échec, pas un autre tutoriel', () => {
    expect(source).toContain('Tutoriel introuvable.');
    expect(source).not.toContain('DEMO_TUTORIALS.find');
  });

  it('le tutoriel retiré du catalogue ne réapparaît pas', () => {
    // Il avait été retiré de la table, puis ressuscité par le repli. Le
    // contrôle reste : c'est une marque tierce dans un build Google Play.
    expect(source).not.toContain('handicaps asiatiques');
  });
});

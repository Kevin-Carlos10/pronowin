import fs from 'fs';
import path from 'path';

import {
  acteurAutorise, cheminRelatif, exigenceDe, niveauAccorde,
} from '../utils/permissions_admin';

/**
 * Chaque route d'administration est rattachée à une permission.
 *
 * L'API applique elle-même les permissions des sous-administrateurs, route
 * par route (`utils/permissions_admin.ts`). Une route qu'elle ne sait pas
 * classer est refusée à tout sous-admin : c'est sûr, mais c'est aussi une
 * page qui cesse de fonctionner pour eux, sans autre signe qu'un 403.
 *
 * Ce banc recense donc les routes réellement déclarées dans `src/routes/`,
 * montées là où `index.ts` les monte, et exige que chacune soit classée.
 * Ajouter une route d'administration sans la déclarer fait échouer `npm test`
 * plutôt que la production.
 */
const SRC = path.join(__dirname, '..');

function routesAdmin(): Array<{ methode: string; chemin: string }> {
  const index = fs.readFileSync(path.join(SRC, 'index.ts'), 'utf8');

  // import usersAdminRoutes from './routes/users_admin.routes';
  const fichierDe = new Map<string, string>();
  for (const m of index.matchAll(/import\s+(\w+)\s+from\s+'\.\/routes\/([\w.]+)'/g)) {
    fichierDe.set(m[1], m[2]);
  }

  const routes: Array<{ methode: string; chemin: string }> = [];
  // app.use(`${v1}/admin/users`, usersAdminRoutes);  — éventuellement avec un limiteur
  for (const m of index.matchAll(/app\.use\(`\$\{v1\}([^`]*)`,\s*(?:\w+,\s*)?(\w+)\)/g)) {
    const [, montage, nom] = m;
    const fichier = fichierDe.get(nom);
    if (!fichier) continue;
    const source = fs.readFileSync(path.join(SRC, 'routes', fichier + '.ts'), 'utf8');
    const toutAdmin = /r\.use\(\s*adminMiddleware\s*\)/.test(source);

    for (const ligne of source.split('\n')) {
      const d = ligne.match(/r\.(get|post|put|patch|delete)\s*\(\s*'([^']+)'/);
      if (!d) continue;
      if (!toutAdmin && !/adminMiddleware/.test(ligne)) continue;
      const chemin = (montage + d[2]).replace(/:[A-Za-z]+/g, 'x1').replace(/\/+$/, '');
      routes.push({ methode: d[1].toUpperCase(), chemin });
    }
  }
  return routes;
}

describe('permissions d\'administration : couverture des routes', () => {
  const routes = routesAdmin();

  it('le recensement trouve bien les routes d\'administration', () => {
    // Sans ce point, un recensement cassé (0 route) ferait passer le suivant.
    expect(routes.length).toBeGreaterThan(60);
    expect(routes).toEqual(expect.arrayContaining([
      { methode: 'PATCH', chemin: '/subscriptions/admin/proofs/x1' },
      { methode: 'GET',   chemin: '/admin/users' },
    ]));
  });

  it.each(routesAdmin().map((r) => [r.methode, r.chemin]))(
    '%s %s est classée',
    (methode, chemin) => {
      expect(exigenceDe(methode, chemin)).not.toBeNull();
    },
  );
});

describe('permissions d\'administration : décisions', () => {
  const sub = (perms: string[]) => ({ id: 's', nom: 'S', role: 'sub' as const, perms });

  it('le niveau accordé est le plus élevé, pas le premier', () => {
    expect(niveauAccorde(['users:read', 'users:delete', 'users:write'], 'users')).toBe('delete');
    // Rétrocompatibilité du panneau : une clé nue vaut « write ».
    expect(niveauAccorde(['users'], 'users')).toBe('write');
    expect(niveauAccorde(['users:read'], 'pronostics')).toBeNull();
    expect(niveauAccorde(['users:admin'], 'users')).toBeNull();
  });

  it.each([
    // [perms, méthode, chemin, attendu]
    [['users:read'],        'GET',    '/admin/users/export/csv',           true],
    [['users:read'],        'PATCH',  '/admin/users/abc/suspend',          false],
    [['users:write'],       'PATCH',  '/admin/users/abc/suspend',          true],
    [['users:write'],       'DELETE', '/admin/users/abc/premium',          true],
    [['abonnements:read'],  'PATCH',  '/subscriptions/admin/proofs/p1',    false],
    [['abonnements:write'], 'PATCH',  '/subscriptions/admin/proofs/p1',    true],
    [['transactions:read'], 'GET',    '/admin/history',                    true],
    [['historique:read'],   'PATCH',  '/admin/history/t1',                 false],
    [['tutoriels:write'],   'DELETE', '/admin/tutorials/t1',               false],
    [['tutoriels:delete'],  'DELETE', '/admin/tutorials/t1',               true],
    [['pronostics:read'],   'POST',   '/pronostics/admin/scores',          true],
    [['pronostics:read'],   'PATCH',  '/pronostics/admin/pronostic/p/publish', false],
    [[],                    'GET',    '/admin/stats/online',               true],
    [[],                    'GET',    '/admin/stats/revenue',              false],
    [['statistiques:read'], 'GET',    '/admin/stats/revenue',              true],
    [['users:delete'],      'PUT',    '/admin/app-config',                 false],
    [['users:delete'],      'PATCH',  '/admin/profile/password',           false],
  ])('%j : %s %s → %s', (perms, methode, chemin, attendu) => {
    expect(acteurAutorise(sub(perms as string[]), methode as string, chemin as string).ok)
      .toBe(attendu);
  });

  it('l\'administrateur principal passe partout', () => {
    const main = { id: 'main', nom: 'P', role: 'main' as const, perms: [] };
    expect(acteurAutorise(main, 'PUT', '/admin/app-config').ok).toBe(true);
    expect(acteurAutorise(main, 'GET', '/admin/inconnue').ok).toBe(true);
  });

  it('le chemin est ramené à sa forme relative', () => {
    expect(cheminRelatif('/api/v1/admin/users?page=2')).toBe('/admin/users');
    expect(cheminRelatif('/api/v1/subscriptions/admin/proofs/')).toBe('/subscriptions/admin/proofs');
    expect(cheminRelatif('/admin/users')).toBe('/admin/users');
  });
});

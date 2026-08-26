import express from 'express';
import request from 'supertest';

/**
 * `POST /admin/create` crée un compte administrateur, avec le rôle envoyé dans
 * le corps — `super_admin` compris. Son contrôle s'écrivait :
 *
 *     if (secret !== process.env.ADMIN_SETUP_SECRET) { ...403... }
 *
 * En-tête absent d'un côté, variable non définie de l'autre, cela compare
 * `undefined !== undefined` : **faux**. Le garde laissait passer.
 *
 * Rien ne rendait ce cas improbable. `ADMIN_SETUP_SECRET` ne figurait pas dans
 * `.env.example`, que le README demande de recopier tel quel, et dont la
 * deuxième ligne est `NODE_ENV=development` — donc pas de 404 non plus. Un
 * déploiement fait en suivant la documentation ouvrait la création de comptes
 * administrateurs à tout internet.
 *
 * Ces contrôles s'exécutent au lieu de lire la source : c'est une égalité entre
 * deux `undefined` qui était en cause, et seule une exécution la démontre.
 */
jest.mock('../services/admin_auth.service', () => ({
  AdminAuthService: class {
    async login() { return { token: 'x' }; }
    async createAdmin(d: any) { return { id: 'cree', ...d }; }
  },
}));
jest.mock('../middleware/admin.middleware', () => ({
  adminMiddleware: (_r: any, res: any) => res.status(401).json({ message: 'non' }),
}));
jest.mock('../services/app_config.service', () => ({ lireConfig: async () => ({}), ecrireConfig: async () => ({}) }));
jest.mock('../services/payment_method.service', () => ({}));

const ENV_INITIAL = { ...process.env };
afterEach(() => { process.env = { ...ENV_INITIAL }; });

/**
 * Monte le routeur avec l'environnement voulu.
 *
 * L'environnement reste en place jusqu'à la fin du test : le garde lit
 * `process.env` **au moment de la requête**, pas au chargement du module. Le
 * restaurer ici faisait échouer les cas nominaux pour une raison qui n'avait
 * rien à voir avec le code testé.
 */
function appAvec(env: Record<string, string | undefined>) {
  for (const [k, v] of Object.entries(env)) {
    if (v === undefined) delete process.env[k];
    else process.env[k] = v;
  }
  jest.resetModules();
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const routes = require('../routes/admin.routes').default;
  const app = express();
  app.use(express.json());
  app.use('/admin', routes);
  return app;
}

const CORPS = { email: 'a@b.c', password: 'x', name: 'n', role: 'super_admin' };

describe('amorçage administrateur — le garde échoue fermé', () => {
  it('le cas de la faille : aucun secret configuré, aucun en-tête envoyé', async () => {
    const app = appAvec({ NODE_ENV: 'development', ADMIN_SETUP_SECRET: undefined });

    const r = await request(app).post('/admin/create').send(CORPS);

    expect(r.status).not.toBe(201);
    // 404, et non 403 : tant qu'aucun secret n'est provisionné, la route ne
    // doit pas exister. Un 403 confirmerait au contraire qu'elle est là et
    // qu'il suffit de trouver le bon en-tête.
    //
    // Cette distinction n'est pas cosmétique : la première version de ce test
    // acceptait « 403 ou 404 », et retirer le contrôle de provisionnement
    // passait alors inaperçu — le refus venait d'ailleurs.
    expect(r.status).toBe(404);
  });

  it('aucun secret configuré : même un en-tête fourni ne trouve rien', async () => {
    const app = appAvec({ NODE_ENV: 'development', ADMIN_SETUP_SECRET: undefined });

    const r = await request(app)
      .post('/admin/create').set('x-admin-setup-secret', 'devine').send(CORPS);

    expect(r.status).toBe(404);
  });

  it('secret configuré, en-tête absent : refus', async () => {
    const app = appAvec({ NODE_ENV: 'development', ADMIN_SETUP_SECRET: 'vrai-secret' });

    const r = await request(app).post('/admin/create').send(CORPS);

    expect(r.status).toBe(403);
  });

  it('secret configuré, en-tête faux : refus', async () => {
    const app = appAvec({ NODE_ENV: 'development', ADMIN_SETUP_SECRET: 'vrai-secret' });

    const r = await request(app)
      .post('/admin/create').set('x-admin-setup-secret', 'faux').send(CORPS);

    expect(r.status).toBe(403);
  });

  it('secret configuré et correct : la création a lieu', async () => {
    // Le pendant indispensable : un garde qui refuse tout serait vert sur les
    // quatre contrôles précédents sans que la route serve plus à rien.
    const app = appAvec({ NODE_ENV: 'development', ADMIN_SETUP_SECRET: 'vrai-secret' });

    const r = await request(app)
      .post('/admin/create').set('x-admin-setup-secret', 'vrai-secret').send(CORPS);

    expect(r.status).toBe(201);
    expect(r.body.id).toBe('cree');
  });

  it('en production, la route n\'existe pas même avec le bon secret', async () => {
    const app = appAvec({ NODE_ENV: 'production', ADMIN_SETUP_SECRET: 'vrai-secret' });

    const r = await request(app)
      .post('/admin/create').set('x-admin-setup-secret', 'vrai-secret').send(CORPS);

    expect(r.status).toBe(404);
  });

  it('toutes les autres routes admin passent par le middleware', async () => {
    // Le middleware est remplacé par un refus systématique : si une route
    // l'oubliait, elle répondrait autre chose que 401.
    const app = appAvec({ NODE_ENV: 'development', ADMIN_SETUP_SECRET: 'vrai-secret' });

    for (const chemin of ['/admin/app-config', '/admin/payment-methods']) {
      const r = await request(app).get(chemin);
      expect(r.status).toBe(401);
    }
  });
});

import crypto from 'crypto';
import express from 'express';
import jwt from 'jsonwebtoken';
import path from 'path';
import request from 'supertest';

import {
  DELEGATION_VALIDITE_MS,
  ENTETE_DELEGATION,
  estMutation,
  lireDelegation,
  signerDelegation,
} from '../utils/delegation_admin';

/**
 * Derrière le jeton du compte de service, il y a quelqu'un.
 *
 * Les sous-administrateurs n'existent pas dans cette base : ils vivent dans les
 * fichiers du panneau, et pour joindre cette API le panneau leur donne à tous
 * le **même** jeton. Vu d'ici, dix personnes sont un seul administrateur.
 *
 * Ce jeton est posé dans leur navigateur. Un sous-administrateur peut donc le
 * lire et appeler cette API **directement**, sans passer par le panneau — donc
 * sans passer par les permissions que le panneau applique. Une restriction de
 * menu ne protège pas une API.
 *
 * Le panneau signe maintenant, à chaque appel, qui agit. La signature est posée
 * par son serveur : elle ne transite jamais par le navigateur. Une écriture
 * portant le jeton de service sans délégation valable n'est donc pas venue du
 * panneau, et elle est refusée.
 */
const SECRET = 'delegation-de-banc';
const JWT_ADMIN = 'jwt-admin-de-banc';

process.env.ADMIN_DELEGATION_SECRET = SECRET;
process.env.ADMIN_JWT_SECRET = JWT_ADMIN;

jest.mock('../lib/prisma', () => ({
  prisma: {
    admin: {
      findUnique: jest.fn().mockResolvedValue({
        id: 'compte-de-service', role: 'admin', isActive: true,
      }),
    },
  },
}));

// `require` et non `import` : le middleware refuse de se charger sans secret,
// et les imports sont hissés au-dessus des affectations d'environnement.
// eslint-disable-next-line @typescript-eslint/no-var-requires
const { adminMiddleware } = require('../middleware/admin.middleware');

const ACTEUR = {
  id: 'sub-7', nom: 'Lonfo', role: 'sub' as const,
  perms: ['pronostics:read'],
};

const jetonDeService = jwt.sign({ adminId: 'compte-de-service' }, JWT_ADMIN);

function appli() {
  const app = express();
  const repondre = (req: any, res: any) =>
    res.json({ acteur: req.acteurAdmin ?? null });
  app.post('/admin/x', adminMiddleware, repondre);
  app.get('/admin/x',  adminMiddleware, repondre);
  return app;
}

describe('délégation : ce que le middleware accepte', () => {
  it('une écriture déléguée passe, et nomme la personne', async () => {
    const r = await request(appli())
      .post('/admin/x')
      .set('Authorization', `Bearer ${jetonDeService}`)
      .set(ENTETE_DELEGATION, signerDelegation(ACTEUR, SECRET));

    expect(r.status).toBe(200);
    expect(r.body.acteur).toEqual(ACTEUR);
  });

  it('une écriture sans délégation est refusée', async () => {
    // C'est la manœuvre : lire le jeton dans ses cookies, appeler l'API
    // directement, contourner les permissions du panneau.
    const r = await request(appli())
      .post('/admin/x')
      .set('Authorization', `Bearer ${jetonDeService}`);

    expect(r.status).toBe(403);
    expect(r.body.code).toBe('DELEGATION_ABSENTE');
  });

  it('une délégation forgée est refusée', async () => {
    const r = await request(appli())
      .post('/admin/x')
      .set('Authorization', `Bearer ${jetonDeService}`)
      .set(ENTETE_DELEGATION, signerDelegation(ACTEUR, 'pas-le-bon-secret'));

    expect(r.status).toBe(403);
    expect(r.body.code).toBe('DELEGATION_SIGNATURE');
  });

  it('une délégation périmée est refusée', async () => {
    // Sans fraîcheur, une délégation captée une fois vaudrait pour toujours.
    const vieille = signerDelegation(
      ACTEUR, SECRET, Date.now() - DELEGATION_VALIDITE_MS - 1000);
    const r = await request(appli())
      .post('/admin/x')
      .set('Authorization', `Bearer ${jetonDeService}`)
      .set(ENTETE_DELEGATION, vieille);

    expect(r.status).toBe(403);
    expect(r.body.code).toBe('DELEGATION_PERIMEE');
  });

  it('une lecture sans délégation reste possible', async () => {
    // Contrepartie, et décision assumée : une lecture ne change rien, et la
    // refuser casserait toute consultation le jour d'un décalage de version
    // entre les deux services. Ce qui écrit, en revanche, doit être attribué.
    const r = await request(appli())
      .get('/admin/x')
      .set('Authorization', `Bearer ${jetonDeService}`);

    expect(r.status).toBe(200);
    expect(r.body.acteur).toBeNull();
  });
});

describe('délégation : la lecture de l\'en-tête', () => {
  const maintenant = Date.now();

  it('rend l\'acteur quand tout est en ordre', () => {
    const lu = lireDelegation(signerDelegation(ACTEUR, SECRET, maintenant),
                              SECRET, maintenant);
    expect(lu).toEqual({ ok: true, acteur: ACTEUR });
  });

  it.each([
    ['absente',   undefined],
    ['malformee', 'pas-de-point'],
    // Deux parties, donc la forme est lisible : c'est la signature qui tombe.
    // L'ordre compte — on ne veut pas analyser une charge avant de savoir
    // qu'elle vient de nous.
    ['signature', 'cGFzLWRlLWpzb24.abcdef'],
  ])('refuse une valeur %s', (cause, entete) => {
    const lu = lireDelegation(entete as any, SECRET, maintenant);
    expect(lu.ok).toBe(false);
    if (!lu.ok) expect(lu.cause).toBe(cause);
  });

  it('refuse une charge correctement signée mais illisible', () => {
    // Le seul chemin vers « malformee » : une charge qui n'est pas du JSON,
    // signée avec le bon secret. Fabriquée à la main, puisque le signataire
    // normal sérialise toujours un objet.
    const charge = Buffer.from('ceci-n-est-pas-du-json').toString('base64url');
    const sig = crypto.createHmac('sha256', SECRET).update(charge).digest('hex');
    const lu = lireDelegation(`${charge}.${sig}`, SECRET, maintenant);
    expect(lu.ok).toBe(false);
    if (!lu.ok) expect(lu.cause).toBe('malformee');
  });

  it('refuse une charge datée dans le futur', () => {
    // Une date future signale une horloge décalée ou une charge bricolée pour
    // rester valable indéfiniment.
    const futur = signerDelegation(ACTEUR, SECRET, maintenant + 60_000);
    const lu = lireDelegation(futur, SECRET, maintenant);
    expect(lu.ok).toBe(false);
    if (!lu.ok) expect(lu.cause).toBe('perimee');
  });

  it('refuse une charge incomplète', () => {
    const bancale = signerDelegation(
      { id: 'x', nom: 'y' } as any, SECRET, maintenant);
    const lu = lireDelegation(bancale, SECRET, maintenant);
    expect(lu.ok).toBe(false);
    if (!lu.ok) expect(lu.cause).toBe('incomplete');
  });

  it('sait ce qui écrit et ce qui lit', () => {
    for (const m of ['POST', 'put', 'PATCH', 'delete']) {
      expect(estMutation(m)).toBe(true);
    }
    for (const m of ['GET', 'head', 'OPTIONS']) {
      expect(estMutation(m)).toBe(false);
    }
  });
});

/**
 * Les deux dépôts doivent écrire la même chose.
 *
 * Le panneau signe dans `admin-web/lib/acteur.js`, cette API relit dans
 * `src/utils/delegation_admin.ts`. Deux fichiers, deux langages, un seul
 * format — exactement la configuration qui finit par diverger, et le jour où
 * elle diverge toute écriture d'administration est refusée.
 */
describe('accord entre le panneau et l\'API', () => {
  const panneau = require(
    path.join(__dirname, '..', '..', '..', 'admin-web', 'lib', 'acteur.js'));

  it('une délégation signée par le panneau se relit ici', () => {
    const entete = panneau.signerDelegation(ACTEUR, SECRET);
    const lu = lireDelegation(entete, SECRET);
    expect(lu.ok).toBe(true);
    if (lu.ok) expect(lu.acteur).toEqual(ACTEUR);
  });

  it('et réciproquement, octet pour octet', () => {
    // Contrepartie : deux formats différents qui se reliraient quand même —
    // par exemple si l'un ignorait la signature — passeraient le contrôle
    // ci-dessus. On compare donc les chaînes produites.
    //
    // Le nom porte des accents, et c'est délibéré. Avec un acteur purement
    // ASCII, `base64` et `base64url` rendent exactement la même chaîne : un
    // banc bâti sur un tel acteur laissait passer une divergence d'encodage
    // entre les deux dépôts — vérifié en la réintroduisant, sans rien casser.
    const t = 1_757_000_000_000;
    const acteurAccentue = {
      id: 'sub-7', nom: 'Léa Ouédraogo–Zoungrana', role: 'sub' as const,
      perms: ['pronostics:read', 'transactions:write'],
    };
    expect(panneau.signerDelegation(acteurAccentue, SECRET, t))
      .toBe(signerDelegation(acteurAccentue, SECRET, t));
  });

  it('le nom de l\'en-tête est le même des deux côtés', () => {
    expect(panneau.ENTETE_DELEGATION.toLowerCase()).toBe(ENTETE_DELEGATION);
  });
});

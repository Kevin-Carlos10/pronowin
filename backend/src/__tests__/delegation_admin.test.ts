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
 * Ce jeton a longtemps été posé dans leur navigateur : un sous-administrateur
 * pouvait le lire et appeler cette API **directement**, sans passer par les
 * permissions du panneau. Il ne quitte plus le serveur du panneau, qui signe à
 * chaque appel qui agit et avec quels droits. Une requête sans délégation
 * valable n'est pas venue du panneau et elle est refusée, lecture comprise ;
 * une requête déléguée n'obtient que ce que les permissions de l'acteur
 * autorisent.
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

// De vraies routes : l'API ne laisse plus un sous-admin appeler une route
// qu'elle ne sait pas rattacher à une permission (`permissions_admin.ts`).
const LECTURE   = '/pronostics/admin/upcoming';   // pronostics : read
const ECRITURE  = '/pronostics/admin/pronostic';  // pronostics : write
const PRINCIPAL = '/admin/app-config';            // administrateur principal

function appli() {
  const app = express();
  const repondre = (req: any, res: any) =>
    res.json({ acteur: req.acteurAdmin ?? null });
  for (const chemin of [LECTURE, ECRITURE, PRINCIPAL, '/admin/route-inconnue']) {
    app.post(chemin, adminMiddleware, repondre);
    app.get(chemin,  adminMiddleware, repondre);
  }
  return app;
}

describe('délégation : ce que le middleware accepte', () => {
  it('une lecture déléguée et permise passe, et nomme la personne', async () => {
    const r = await request(appli())
      .get(LECTURE)
      .set('Authorization', `Bearer ${jetonDeService}`)
      .set(ENTETE_DELEGATION, signerDelegation(ACTEUR, SECRET));

    expect(r.status).toBe(200);
    expect(r.body.acteur).toEqual(ACTEUR);
  });

  it('une écriture sans délégation est refusée', async () => {
    // C'est la manœuvre : lire le jeton quelque part, appeler l'API
    // directement, contourner les permissions du panneau.
    const r = await request(appli())
      .post(ECRITURE)
      .set('Authorization', `Bearer ${jetonDeService}`);

    expect(r.status).toBe(403);
    expect(r.body.code).toBe('DELEGATION_ABSENTE');
  });

  it('une lecture sans délégation est refusée aussi', async () => {
    // Elle était tolérée : le jeton du compte de service était alors dans le
    // navigateur des sous-admins, qui lisaient toute l'API — téléphones,
    // preuves de paiement, revenus — quelles que soient leurs permissions
    // (constat S1). Le jeton ne quitte plus le serveur du panneau.
    const r = await request(appli())
      .get(LECTURE)
      .set('Authorization', `Bearer ${jetonDeService}`);

    expect(r.status).toBe(403);
    expect(r.body.code).toBe('DELEGATION_ABSENTE');
  });

  it('une délégation forgée est refusée', async () => {
    const r = await request(appli())
      .post(ECRITURE)
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
      .post(ECRITURE)
      .set('Authorization', `Bearer ${jetonDeService}`)
      .set(ENTETE_DELEGATION, vieille);

    expect(r.status).toBe(403);
    expect(r.body.code).toBe('DELEGATION_PERIMEE');
  });
});

describe('délégation : les permissions sont appliquées par l\'API', () => {
  const appel = (methode: 'get' | 'post', chemin: string, acteur: any) =>
    request(appli())[methode](chemin)
      .set('Authorization', `Bearer ${jetonDeService}`)
      .set(ENTETE_DELEGATION, signerDelegation(acteur, SECRET));

  it('une écriture au-delà du niveau accordé est refusée', async () => {
    // Le panneau la refusait déjà ; l'API ne s'en remet plus à lui.
    const r = await appel('post', ECRITURE, ACTEUR);
    expect(r.status).toBe(403);
    expect(r.body.code).toBe('PERMISSION_ADMIN');
  });

  it('la même écriture passe avec le niveau requis', async () => {
    // Contrepartie : sans elle, une API qui refuserait tout passerait le point
    // précédent.
    const r = await appel('post', ECRITURE, { ...ACTEUR, perms: ['pronostics:write'] });
    expect(r.status).toBe(200);
  });

  it('une route réservée au principal est refusée à un sous-admin', async () => {
    const r = await appel('get', PRINCIPAL,
      { ...ACTEUR, perms: ['users:delete', 'pronostics:delete'] });
    expect(r.status).toBe(403);
  });

  it('une route non déclarée est refusée à un sous-admin, pas au principal', async () => {
    // Fermeture par défaut : oublier de classer une route la réserve au
    // principal au lieu de l'ouvrir à tous.
    const sub  = await appel('get', '/admin/route-inconnue',
      { ...ACTEUR, perms: ['pronostics:delete'] });
    const main = await appel('get', '/admin/route-inconnue',
      { id: 'main', nom: 'Principal', role: 'main', perms: [] });
    expect(sub.status).toBe(403);
    expect(main.status).toBe(200);
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

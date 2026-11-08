/**
 * « Donne-nous ton avis » (8 novembre 2026) : envoi depuis l'application,
 * lecture et classement dans l'administration.
 */
jest.mock('../lib/prisma', () => {
  const avis: any[] = [];
  return {
    prisma: {
      user: { findUnique: jest.fn(async ({ where }: any) =>
        where.id === 'u1' ? { email: 'kevin@exemple.bf' } : null) },
      avisUtilisateur: {
        count: jest.fn(async ({ where }: any) => avis.filter(a =>
          (where.traite === undefined || a.traite === where.traite)
          && (!where.userId || a.userId === where.userId)
          && (!where.email || a.email === where.email)).length),
        create: jest.fn(async ({ data }: any) => {
          const a = { id: `a${avis.length + 1}`, traite: false, traiteLe: null, creeLe: new Date(), user: null, ...data };
          avis.push(a);
          return { id: a.id };
        }),
        findMany: jest.fn(async ({ where }: any) =>
          avis.filter(a => where.traite === undefined || a.traite === where.traite).reverse()),
        findUnique: jest.fn(async ({ where }: any) => avis.find(a => a.id === where.id) ?? null),
        update: jest.fn(async ({ where, data }: any) => {
          const a = avis.find(x => x.id === where.id);
          Object.assign(a, data);
          return { id: a.id, traite: a.traite, message: a.message };
        }),
      },
    },
    _avis: avis,
  };
});

import express from 'express';
import request from 'supertest';

import supportRoutes from '../routes/support.routes';
import {
  envoyerAvis, listerAvisAdmin, marquerAvis, remplacerStockage, AVIS_PAR_HEURE,
} from '../services/avis_utilisateurs.service';

const { _avis } = require('../lib/prisma');

const depots: string[] = [];
beforeEach(() => {
  _avis.length = 0;
  depots.length = 0;
  remplacerStockage(async () => ({
    uploadImage: async (p) => { depots.push(p.folder); return `https://seau.s3.amazonaws.com/${p.folder}/${p.userId}/x.png`; },
    urlLectureSignee: async (url) => `${url}?signature=10min`,
  }));
});

describe('envoyer un avis', () => {
  it('un abonné connecté : son adresse de compte, la capture dans le dossier privé « avis »', async () => {
    await envoyerAvis({ userId: 'u1', message: 'Le score ne bouge plus en direct.', imageBase64: 'iVBORw0KGgo=',
      plateforme: 'ios', versionApp: '1.0.35 (51)' });
    expect(_avis[0]).toMatchObject({ userId: 'u1', email: 'kevin@exemple.bf', plateforme: 'ios', versionApp: '1.0.35 (51)' });
    expect(depots).toEqual(['avis']);
  });

  it('un invité doit laisser une adresse valable', async () => {
    await expect(envoyerAvis({ message: 'Ajoutez la Ligue 1 burkinabè.' })).rejects.toThrow(/adresse e-mail/);
    await expect(envoyerAvis({ message: 'Ajoutez la Ligue 1 burkinabè.', email: 'pas-une-adresse' })).rejects.toThrow(/invalide/);
    await envoyerAvis({ message: 'Ajoutez la Ligue 1 burkinabè.', email: 'Fan@Exemple.bf' });
    expect(_avis[0].email).toBe('fan@exemple.bf');
  });

  it('dix caractères au moins', async () => {
    await expect(envoyerAvis({ userId: 'u1', message: '  bug  ' })).rejects.toMatchObject({ statut: 422 });
  });

  it('sans stockage, la capture est refusée en clair — le message seul passe', async () => {
    remplacerStockage(async () => null);
    await expect(envoyerAvis({ userId: 'u1', message: 'Capture jointe ci-dessous.', imageBase64: 'iVBORw0KGgo=' }))
      .rejects.toMatchObject({ statut: 503 });
    await envoyerAvis({ userId: 'u1', message: 'Sans capture, cette fois.' });
    expect(_avis).toHaveLength(1);
  });

  it(`${AVIS_PAR_HEURE} par heure au plus`, async () => {
    for (let i = 0; i < AVIS_PAR_HEURE; i++) await envoyerAvis({ userId: 'u1', message: `Message numéro ${i}` });
    await expect(envoyerAvis({ userId: 'u1', message: 'Un de trop, celui-là.' })).rejects.toMatchObject({ statut: 429 });
  });

  it('la route : 201 pour un invité avec adresse, 422 sans', async () => {
    const app = express().use(express.json()).use('/support', supportRoutes);
    expect((await request(app).post('/support/avis').send({ message: 'Très bonne application !', email: 'a@b.bf' })).status).toBe(201);
    const refus = await request(app).post('/support/avis').send({ message: 'Très bonne application !' });
    expect(refus.status).toBe(422);
    expect(refus.body.message).toMatch(/adresse e-mail/);
  });
});

describe('administration', () => {
  it('les nouveaux d’abord, la capture par adresse signée, puis classés', async () => {
    await envoyerAvis({ userId: 'u1', message: 'Premier message envoyé.', imageBase64: 'iVBORw0KGgo=' });
    await envoyerAvis({ userId: 'u1', message: 'Deuxième message envoyé.' });
    const liste = await listerAvisAdmin({ filtre: 'nouveaux', page: 1 });
    expect(liste.nouveaux).toBe(2);
    expect(liste.avis.map(a => a.message)).toEqual(['Deuxième message envoyé.', 'Premier message envoyé.']);
    expect(liste.avis[1].capture).toMatch(/signature=10min$/);
    expect(liste.avis[0].capture).toBeNull();

    await marquerAvis(liste.avis[0].id, true);
    expect((await listerAvisAdmin({ filtre: 'nouveaux', page: 1 })).avis).toHaveLength(1);
    expect((await listerAvisAdmin({ filtre: 'traites', page: 1 })).avis[0].traite).toBe(true);
    expect(await marquerAvis('inconnu', true)).toBeNull();
  });
});

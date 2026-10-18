/**
 * Actualités de l'accueil (18 octobre 2026) : les résumés de match rejoignent
 * le flux, et les images des médias ne sont plus reprises — le serveur les
 * relayait en se faisant passer pour leur site.
 */
import express from 'express';
import request from 'supertest';

jest.mock('../services/rss.service', () => ({
  fetchRssNews: async () => [{
    id: 'rss_1', titre: 'Mercato : un transfert record se prépare', resume: 'Résumé du flux.',
    categorie: 'RMC Sport', emoji: '📻', image_url: null, source_url: 'https://rmcsport.bfmtv.com/a',
    source: 'RMC Sport', date: 'Il y a 2h', created_at: new Date(Date.now() - 2 * 3600_000).toISOString(),
    is_pinned: false, from_rss: true,
  }],
}));
jest.mock('../services/resumes_match.service', () => ({
  resumesPourActualites: async () => [{
    id: 'resume_r1', titre: 'Bayer Leverkusen s\'impose face à SC Freiburg (2-1)', titre_en: 'Bayer Leverkusen beat SC Freiburg 2-1',
    resume: 'Score à la mi-temps : 1-1.', resume_en: 'Half-time: 1-1.', categorie: 'Bundesliga', emoji: '⚽',
    image_url: null, source_url: null, is_pinned: false, created_at: new Date(Date.now() - 30 * 60_000).toISOString(),
    from_rss: false, type: 'resume_match', match_id: 'm1',
  }],
}));

// eslint-disable-next-line @typescript-eslint/no-require-imports
const newsRoutes = require('../routes/news.routes').default;
const app = express().use('/actualites', newsRoutes);

it('le résumé d\'un match rejoint le flux, à sa place dans l\'ordre chronologique', async () => {
  const r = await request(app).get('/actualites');
  expect(r.status).toBe(200);
  expect(r.body.map((a: any) => a.id)).toEqual(['resume_r1', 'rss_1']);
  expect(r.body[0]).toMatchObject({ categorie: 'Bundesliga', match_id: 'm1', date: 'Il y a 30 min', titre_en: 'Bayer Leverkusen beat SC Freiburg 2-1' });
});

it('aucune image de média reprise ; le relais d\'images ne répond plus', async () => {
  const r = await request(app).get('/actualites');
  expect(r.body.every((a: any) => a.image_url === null)).toBe(true);
  expect(JSON.stringify(r.body)).not.toContain('image-proxy');
  const relais = await request(app).get('/actualites/image-proxy?url=https%3A%2F%2Fimages.bfmtv.com%2Fx.jpg');
  expect(relais.status).toBe(410);
});

it('la page Actualités demande jusqu\'à 50 articles ; au-delà, 50 ; l\'accueil reste à 20', async () => {
  // Deux articles au total ici : la limite borne, elle n'invente rien.
  expect((await request(app).get('/actualites?limite=50')).body).toHaveLength(2);
  expect((await request(app).get('/actualites?limite=abc')).status).toBe(200);
  expect((await request(app).get('/actualites?limite=1')).body).toHaveLength(1);
});

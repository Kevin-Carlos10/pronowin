/**
 * Actualités de l'accueil (18 octobre 2026) : les résumés de match rejoignent
 * le flux. Les images des médias passaient par un relais qui se faisait
 * passer pour leur site ; inutile, elles sont données à leur adresse
 * d'origine (20 octobre 2026).
 */
import express from 'express';
import request from 'supertest';

jest.mock('../services/rss.service', () => ({
  fetchRssNews: async () => [{
    id: 'rss_1', titre: 'Mercato : un transfert record se prépare', resume: 'Résumé du flux.',
    categorie: 'RMC Sport', emoji: '📻', image_url: 'https://io-fsly-bfmtv.cdn.nextradiotv.com/x/800x0/images/a.jpg',
    source_url: 'https://rmcsport.bfmtv.com/a',
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

it('l\'image du média à son adresse d\'origine, jamais relayée ; le relais ne répond plus', async () => {
  const r = await request(app).get('/actualites');
  expect(r.body.find((a: any) => a.id === 'rss_1').image_url)
    .toBe('https://io-fsly-bfmtv.cdn.nextradiotv.com/x/800x0/images/a.jpg');
  expect(r.body.find((a: any) => a.id === 'resume_r1').image_url).toBeNull();
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

describe('l\'image jointe au flux du média', () => {
  const { imageDuFlux } = jest.requireActual('../services/rss.service');
  it('pièce jointe image (RMC Sport), vignette ou contenu média', () => {
    expect(imageDuFlux({ enclosure: { url: 'https://cdn.example/a.jpg', type: 'image/jpeg' } })).toBe('https://cdn.example/a.jpg');
    expect(imageDuFlux({ 'media:thumbnail': { $: { url: 'https://cdn.example/b.jpg' } } })).toBe('https://cdn.example/b.jpg');
    expect(imageDuFlux({ 'media:content': { $: { url: 'https://cdn.example/c.jpg' } } })).toBe('https://cdn.example/c.jpg');
  });
  it('ni pièce jointe d\'un autre type, ni adresse non chiffrée, ni rien', () => {
    expect(imageDuFlux({ enclosure: { url: 'https://cdn.example/a.mp3', type: 'audio/mpeg' } })).toBeNull();
    expect(imageDuFlux({ enclosure: { url: 'http://cdn.example/a.jpg', type: 'image/jpeg' } })).toBeNull();
    expect(imageDuFlux({})).toBeNull();
  });
});

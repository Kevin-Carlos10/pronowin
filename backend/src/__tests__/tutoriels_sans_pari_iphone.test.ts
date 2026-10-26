/**
 * Version iPhone : aucun tutoriel de pari (vidéo de l'utilisateur du
 * 17 octobre 2026 : « Psychologie du parieur » s'affichait sur iPhone, avec
 * une vignette « dans les paris sportifs », pendant l'examen d'Apple).
 */
import { requeteIphone, tutorielDePari } from '../utils/sans_pari';

const tutos = [
  { id: 'vb',   category: 'valuebet',    title: 'Comprendre le Value Bet' },
  { id: 'br',   category: 'bankroll',    title: 'Bankroll Management' },
  { id: 'xg',   category: 'analyse',     title: 'Statistiques avancées : xG et pressing',
    description: 'Lire un match au-delà du score.' },
  { id: 'psy',  category: 'psychologie', title: 'Psychologie du parieur',
    description: 'Les biais qui faussent le jugement.' },
];

jest.mock('../services/tutorial.service', () => ({
  TutorialService: jest.fn().mockImplementation(() => ({
    getAll: async () => tutos,
    getOne: async (id: string) => tutos.find(t => t.id === id),
    getProgress: async () => tutos.map(t => ({ tutorial_id: t.id, is_completed: false, tutorial: t })),
  })),
}));

// eslint-disable-next-line import/first
import { getAll, getOne, getProgress } from '../controllers/tutorial.controller';

function appel(entetes: Record<string, string>, params: Record<string, string> = {}) {
  const res: any = { statut: 200, corps: undefined as any };
  res.status = (c: number) => { res.statut = c; return res; };
  res.json = (c: any) => { res.corps = c; return res; };
  const req: any = { headers: entetes, query: {}, params, userId: 'u1' };
  return { req, res };
}

describe('tutorielDePari', () => {
  it('par catégorie ou par les mots du titre et de la description', () => {
    expect(tutos.filter(tutorielDePari).map(t => t.id)).toEqual(['vb', 'br', 'psy']);
    expect(tutorielDePari({ category: 'analyse', title: 'Gérer ses mises' })).toBe(true);
    expect(tutorielDePari({ category: 'analyse', title: 'Lire les cotes' })).toBe(true);
    expect(tutorielDePari({ category: 'analyse', title: 'Pressing', title_en: 'Sports betting biases' })).toBe(true);
  });

  it('sans faux positif sur des mots voisins', () => {
    for (const titre of ['Le pressing haut', 'Comprendre le xG', 'Côte à côte : 4-4-2 et 3-5-2', 'Paris Saint-Germain : le jeu de position']) {
      // « Paris » la ville passe pour un pari : c'est voulu, mieux vaut un
      // tutoriel masqué de trop sur iPhone. Les autres ne doivent pas l'être.
      const attendu = titre.startsWith('Paris');
      expect([titre, tutorielDePari({ category: 'analyse', title: titre })]).toEqual([titre, attendu]);
    }
  });
});

describe('requeteIphone', () => {
  it('lit X-App-Plateforme, sans tenir compte de la casse', () => {
    expect(requeteIphone({ 'x-app-plateforme': 'ios' })).toBe(true);
    expect(requeteIphone({ 'x-app-plateforme': 'iOS' })).toBe(true);
    expect(requeteIphone({ 'x-app-plateforme': 'android' })).toBe(false);
    expect(requeteIphone({})).toBe(false);
    expect(requeteIphone(undefined)).toBe(false);
  });
});

describe('routes des tutoriels', () => {
  it('liste : iPhone sans les tutoriels de pari, Android complet', async () => {
    const ios = appel({ 'x-app-plateforme': 'ios' });
    await getAll(ios.req, ios.res);
    expect(ios.res.corps.map((t: any) => t.id)).toEqual(['xg']);

    const android = appel({ 'x-app-plateforme': 'android' });
    await getAll(android.req, android.res);
    expect(android.res.corps.map((t: any) => t.id)).toEqual(['vb', 'br', 'xg', 'psy']);
  });

  it('par identifiant : 404 sur iPhone pour un tutoriel de pari', async () => {
    const ios = appel({ 'x-app-plateforme': 'ios' }, { id: 'psy' });
    await getOne(ios.req, ios.res);
    expect(ios.res.statut).toBe(404);

    const iosXg = appel({ 'x-app-plateforme': 'ios' }, { id: 'xg' });
    await getOne(iosXg.req, iosXg.res);
    expect(iosXg.res.corps.id).toBe('xg');

    const android = appel({ 'x-app-plateforme': 'android' }, { id: 'psy' });
    await getOne(android.req, android.res);
    expect(android.res.corps.id).toBe('psy');
  });

  it('progression : iPhone sans les tutoriels de pari', async () => {
    const ios = appel({ 'x-app-plateforme': 'ios' });
    await getProgress(ios.req, ios.res);
    expect(ios.res.corps.map((p: any) => p.tutorial_id)).toEqual(['xg']);
  });
});

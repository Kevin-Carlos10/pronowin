/**
 * Les résumés de match dans le panneau (22 octobre 2026) : les relire, en
 * corriger le texte, les retirer du fil. Trois titres faux, ce jour-là, n'ont
 * pu être corrigés que par un script sur le serveur.
 *
 * Banc sur base locale : les filtres et la recherche sont des requêtes, on
 * les éprouve contre une vraie base.
 */
import { prisma } from '../lib/prisma';
import { listerResumesAdmin, lireResumeAdmin, modifierResume, masquerResume } from '../services/resumes_match_admin.service';
import { resumesPourActualites } from '../services/resumes_match.service';
import { decrireSurBaseLocale } from './aides/base_locale';

const marque = `banc-resumes-${Date.now()}`;
const HEURE = 3_600_000;
const matchs: string[] = [];

async function resume(o: { equipes: [string, string]; titre: string; heuresAvant: number; prono?: boolean }) {
  const m = await prisma.match.create({ data: {
    externalId: Math.floor(Math.random() * 1e9) + 1e9, source: 'API_FOOTBALL',
    league: 'UEFA Champions League', leagueCode: 'CL',
    homeTeam: `${o.equipes[0]} ${marque}`, awayTeam: o.equipes[1],
    matchDate: new Date(Date.now() - (o.heuresAvant + 3) * HEURE), status: 'FINISHED',
    homeScore: 2, awayScore: 3, hasPublishedPronostic: o.prono ?? false,
  } });
  matchs.push(m.id);
  return prisma.resumeMatch.create({ data: {
    matchId: m.id, ligue: 'UEFA Champions League', titre: `${o.titre} ${marque}`, titreEn: `${o.titre} (en)`,
    resume: 'Buts — …', resumeEn: 'Goals — …', creeLe: new Date(Date.now() - o.heuresAvant * HEURE),
  } });
}

decrireSurBaseLocale('les résumés dans le panneau', () => {
  let recent: { id: string }, ancien: { id: string };

  beforeAll(async () => {
    recent = await resume({ equipes: ['Sporting CP', 'Lask Linz'], heuresAvant: 2,
      titre: 'Lask Linz s\'impose chez Sporting CP (2-3), doublé de Luis Suárez' });
    // Quatre jours : sorti du fil.
    ancien = await resume({ equipes: ['Lille', 'Galatasaray'], heuresAvant: 96, prono: true,
      titre: 'Galatasaray s\'impose chez Lille (2-4)' });
  });
  afterAll(async () => {
    await prisma.match.deleteMany({ where: { id: { in: matchs } } });   // les résumés suivent (cascade)
  });

  // Nos matchs portent la marque dans le nom de l'équipe à domicile : la recherche les retrouve.
  const ids = async (o: Parameters<typeof listerResumesAdmin>[0]) =>
    (await listerResumesAdmin({ ...o, recherche: marque })).resumes.map(r => r.id);

  it('la liste, la recherche par équipe, et ce qui est dans le fil', async () => {
    const l = await listerResumesAdmin({ recherche: marque });
    expect(l.resumes.map(r => r.id)).toEqual([recent.id, ancien.id]);
    const [a, b] = l.resumes;
    expect(a).toMatchObject({ dansLeFil: true, masque: false, modifieLe: null,
      match: { exterieur: 'Lask Linz', score: '2-3', pronostique: false } });
    expect(b).toMatchObject({ dansLeFil: false, match: { pronostique: true } });
    expect((await listerResumesAdmin({ recherche: 'Lask Linz' })).resumes.map(r => r.id)).toContain(recent.id);
    expect(await ids({ filtre: 'dans_le_fil' })).toEqual([recent.id]);
  });

  it('corriger le titre : enregistré, daté, signé ; les retours à la ligne unifiés', async () => {
    const r = await modifierResume(recent.id, {
      titre: '  Lask Linz s\'impose chez Sporting CP (2-3), malgré le doublé de Luis Suárez  ',
      titreEn: 'Lask Linz win 3-2 at Sporting CP, despite Luis Suárez scoring twice',
      resume: 'Buts — Sporting CP : Luis Suárez (30\', 70\').\r\n\r\nPossession : 61 % – 39 %.',
      resumeEn: 'Goals — Sporting CP: Luis Suárez (30\', 70\').',
    }, 'Kevin');
    expect(r).toMatchObject({
      titre: 'Lask Linz s\'impose chez Sporting CP (2-3), malgré le doublé de Luis Suárez',
      resume: 'Buts — Sporting CP : Luis Suárez (30\', 70\').\n\nPossession : 61 % – 39 %.',
      modifiePar: 'Kevin',
    });
    expect(r!.modifieLe).not.toBeNull();
    expect(await ids({ filtre: 'modifies' })).toEqual([recent.id]);
  });

  it('un champ vide ou trop long est refusé, rien n\'est écrit', async () => {
    const avant = await lireResumeAdmin(recent.id);
    await expect(modifierResume(recent.id, { titre: '   ', titreEn: 'x', resume: 'x', resumeEn: 'x' }, 'Kevin'))
      .rejects.toMatchObject({ statut: 422, message: 'Titre : ne peut pas être vide.' });
    await expect(modifierResume(recent.id, { titre: 'x', titreEn: 'x', resume: 'x'.repeat(5001), resumeEn: 'x' }, 'Kevin'))
      .rejects.toMatchObject({ statut: 422 });
    await expect(modifierResume(recent.id, { titre: 'x', resume: 'x', resumeEn: 'x' }, 'Kevin'))
      .rejects.toMatchObject({ message: 'Titre en anglais : champ manquant.' });
    expect(await lireResumeAdmin(recent.id)).toEqual(avant);
  });

  it('retirer du fil, puis remettre : la ligne reste', async () => {
    const dansLeFil = async () => (await resumesPourActualites(50)).some(a => a.match_id === matchs[0]);
    expect(await dansLeFil()).toBe(true);
    expect(await masquerResume(recent.id, true)).toMatchObject({ masque: true, dansLeFil: false });
    expect(await dansLeFil()).toBe(false);
    expect(await ids({ filtre: 'masques' })).toEqual([recent.id]);
    expect(await ids({ filtre: 'dans_le_fil' })).toEqual([]);
    expect(await masquerResume(recent.id, false)).toMatchObject({ masque: false, dansLeFil: true });
    expect(await dansLeFil()).toBe(true);
  });

  it('un résumé qui n\'existe pas : null', async () => {
    expect(await lireResumeAdmin('inconnu')).toBeNull();
    expect(await masquerResume('inconnu', true)).toBeNull();
    expect(await modifierResume('inconnu', { titre: 'x', titreEn: 'x', resume: 'x', resumeEn: 'x' }, 'Kevin')).toBeNull();
  });
});

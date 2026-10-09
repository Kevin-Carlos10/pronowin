import { nettoyerPublications } from './aides/nettoyer_publications';
/**
 * Publier un pronostic, envoyer une notification — à une heure choisie.
 *
 * Rien ne le permettait : un pronostic prêt la veille devait être publié à la
 * main le lendemain matin.
 */
const envois: any[] = [];
const annonces: any[] = [];
jest.mock('../services/notification.service', () => {
  const vrai = jest.requireActual('../services/notification.service');
  return {
    ...vrai,
    NotificationService: class {
      async sendToSegment(segment: string, charge: any) { envois.push({ segment, ...charge }); return { segment, sent: 12 }; }
      async notifyPronosticPublished(p: any) { annonces.push(p); }
    },
  };
});

import { prisma } from '../lib/prisma';
import {
  programmerNotification, programmerPublication, annulerProgrammation, executerProgrammationsEchues,
  listerProgrammations,
} from '../services/programmations.service';
import { exigenceDe } from '../utils/permissions_admin';
import { BASE_LOCALE, decrireSurBaseLocale } from './aides/base_locale';

const MINUTE = 60_000;
const dans = (min: number, depuis = Date.now()) => new Date(depuis + min * MINUTE);

describe('ce qui se refuse avant toute écriture', () => {
  const notif = { segment: 'all', title: 'Match ce soir', body: 'Le pronostic est en ligne.' };

  it('une heure passée, imminente ou trop lointaine', async () => {
    await expect(programmerNotification({ ...notif, prevueLe: dans(-5) })).rejects.toThrow(/déjà passée/);
    await expect(programmerNotification({ ...notif, prevueLe: dans(0.5) })).rejects.toThrow(/moins d'une minute/);
    await expect(programmerNotification({ ...notif, prevueLe: dans(31 * 24 * 60) })).rejects.toThrow(/30 jours/);
    await expect(programmerNotification({ ...notif, prevueLe: new Date('n/a') })).rejects.toThrow(/invalide/);
  });

  it('une audience inconnue, ou l\'envoi de test à une seule personne', async () => {
    await expect(programmerNotification({ ...notif, segment: 'user', prevueLe: dans(60) })).rejects.toThrow(/Audience/);
    await expect(programmerNotification({ ...notif, segment: 'tout-le-monde', prevueLe: dans(60) })).rejects.toThrow(/Audience/);
  });

  it('un message vide ou trop long', async () => {
    await expect(programmerNotification({ ...notif, title: '  ', prevueLe: dans(60) })).rejects.toThrow(/obligatoires/);
    await expect(programmerNotification({ ...notif, body: 'x'.repeat(301), prevueLe: dans(60) })).rejects.toThrow(/300/);
  });

  it('chaque type relève de sa propre permission', () => {
    expect(exigenceDe('POST', '/admin/programmations/pronostics')).toMatchObject({ sections: ['pronostics'], niveau: 'write' });
    expect(exigenceDe('DELETE', '/admin/programmations/notifications/x1')).toMatchObject({ sections: ['notifications'], niveau: 'write' });
    expect(exigenceDe('GET', '/admin/programmations/notifications')).toMatchObject({ sections: ['notifications'], niveau: 'read' });
  });
});

// ─── De bout en bout, sur la base locale ─────────────────────────────────────

const marque = `banc-prog-${Date.now()}`;
const matchs: string[] = [];
const programmations: string[] = [];
let adminDeBanc: string | null = null;

async function brouillon(coupEnvoiDansMin: number, cote = 1.8) {
  // Une base vierge (celle de GitHub) n'a pas d'administrateur : le banc crée
  // le sien, et le retire à la fin.
  let admin = await prisma.admin.findFirst({ select: { id: true } });
  if (!admin) {
    admin = await prisma.admin.create({ data: { email: `${marque}@banc.local`, passwordHash: 'banc', name: 'Banc' }, select: { id: true } });
    adminDeBanc = admin.id;
  }
  const m = await prisma.match.create({ data: {
    externalId: Math.floor(Math.random() * 1e9), league: marque, leagueCode: 'BANC',
    homeTeam: `${marque}-A`, awayTeam: `${marque}-B`, matchDate: dans(coupEnvoiDansMin),
  } });
  matchs.push(m.id);
  return prisma.pronostic.create({ data: {
    matchId: m.id, analystId: admin.id, predictionType: 'win1', predictionLabel: 'A gagne',
    oddsRecommended: cote, confidenceScore: 4, confidencePct: 70,
  } });
}

afterAll(async () => {
  if (!BASE_LOCALE) return;
  await prisma.programmation.deleteMany({ where: { OR: [
    { id: { in: programmations } }, { charge: { path: ['title'], string_contains: marque } },
  ] } });
  await nettoyerPublications({ matchId: { in: matchs } });
  await prisma.match.deleteMany({ where: { id: { in: matchs } } });
  if (adminDeBanc) await prisma.admin.delete({ where: { id: adminDeBanc } });
  await prisma.$disconnect();
});

decrireSurBaseLocale('publication programmée', () => {
  it('se publie à l\'heure dite, une seule fois, et prévient les membres', async () => {
    const p = await brouillon(6 * 60);
    const prog = await programmerPublication({ pronosticId: p.id, prevueLe: dans(60), auteur: 'Banc' });
    programmations.push(prog.id);

    // Pas encore l'heure : rien ne bouge.
    await executerProgrammationsEchues(new Date());
    expect((await prisma.pronostic.findUnique({ where: { id: p.id } }))!.isPublished).toBe(false);

    // L'heure venue, deux passages rapprochés : une seule exécution.
    const heure = dans(61);
    await Promise.all([executerProgrammationsEchues(heure), executerProgrammationsEchues(heure)]);
    expect((await prisma.pronostic.findUnique({ where: { id: p.id } }))!.isPublished).toBe(true);
    expect(annonces.filter((a) => a.pronosticId === p.id)).toHaveLength(1);
    const fait = await prisma.programmation.findUnique({ where: { id: prog.id } });
    expect(fait).toMatchObject({ statut: 'executee' });
    expect(fait!.compteRendu).toMatch(/publié/);
  });

  it('une nouvelle programmation remplace la précédente', async () => {
    const p = await brouillon(6 * 60);
    const a = await programmerPublication({ matchId: p.matchId, prevueLe: dans(60) });
    const b = await programmerPublication({ pronosticId: p.id, prevueLe: dans(90) });
    programmations.push(a.id, b.id);
    const liste = await listerProgrammations('publication_pronostic', { pronosticId: p.id });
    expect(liste.aVenir.map((x) => x.id)).toEqual([b.id]);
    expect(liste.passees[0]).toMatchObject({ id: a.id, statut: 'annulee' });
    expect(liste.aVenir[0].pronostic).toMatchObject({ match: `${marque}-A – ${marque}-B` });
  });

  it('refusée après le coup d\'envoi, ou sous la cote minimale', async () => {
    const p = await brouillon(30);
    await expect(programmerPublication({ pronosticId: p.id, prevueLe: dans(28) })).rejects.toThrow(/5 minutes avant/);
    const faible = await brouillon(6 * 60, 1.1);
    await expect(programmerPublication({ pronosticId: faible.id, prevueLe: dans(60) })).rejects.toThrow();
  });

  it('un match commencé entre-temps : le pronostic reste en brouillon, et on le dit', async () => {
    const p = await brouillon(6 * 60);
    const prog = await programmerPublication({ pronosticId: p.id, prevueLe: dans(60) });
    programmations.push(prog.id);
    await prisma.match.update({ where: { id: p.matchId }, data: { status: 'LIVE' } });
    await executerProgrammationsEchues(dans(61));
    expect((await prisma.pronostic.findUnique({ where: { id: p.id } }))!.isPublished).toBe(false);
    expect(await prisma.programmation.findUnique({ where: { id: prog.id } }))
      .toMatchObject({ statut: 'echec', compteRendu: expect.stringMatching(/commencé/) });
  });
});

decrireSurBaseLocale('notification programmée', () => {
  it('part à l\'heure dite ; annulée, elle ne part pas', async () => {
    const gardee  = await programmerNotification({ segment: 'premium', title: `${marque} gardée`, body: 'ok', prevueLe: dans(30) });
    const annulee = await programmerNotification({ segment: 'all', title: `${marque} annulée`, body: 'ok', prevueLe: dans(30) });
    programmations.push(gardee.id, annulee.id);
    await annulerProgrammation(annulee.id, 'notification', 'Banc');
    await expect(annulerProgrammation(annulee.id, 'notification')).rejects.toThrow(/déjà/);
    // Le type compte : une notification ne s'annule pas par la route des pronostics.
    await expect(annulerProgrammation(gardee.id, 'publication_pronostic')).rejects.toThrow();

    await executerProgrammationsEchues(dans(31));
    expect(envois.filter((e) => e.title.startsWith(marque)).map((e) => [e.segment, e.title]))
      .toEqual([['premium', `${marque} gardée`]]);
    expect(await prisma.programmation.findUnique({ where: { id: gardee.id } }))
      .toMatchObject({ statut: 'executee', compteRendu: 'Envoyée à 12 membres.' });
  });

  it('trop en retard, elle ne part pas', async () => {
    const prog = await programmerNotification({ segment: 'all', title: `${marque} tardive`, body: 'ok', prevueLe: dans(10) });
    programmations.push(prog.id);
    await executerProgrammationsEchues(dans(10 + 90));
    expect(envois.some((e) => e.title === `${marque} tardive`)).toBe(false);
    expect(await prisma.programmation.findUnique({ where: { id: prog.id } }))
      .toMatchObject({ statut: 'echec', compteRendu: expect.stringMatching(/retard/) });
  });
});


jest.mock('../services/notification.service', () => ({ NotificationService: class {} }));
jest.mock('../services/bankroll.service', () => ({ settleBets: async () => {} }));
import { prisma } from '../lib/prisma';
import { PronosticsService } from '../services/pronostics.service';

import { BASE_LOCALE } from './aides/base_locale';
import { nettoyerPublications } from './aides/nettoyer_publications';
const suite = BASE_LOCALE ? describe : describe.skip;
const svc = new PronosticsService();
const marque = 'publication-' + Date.now();
let analystId: string;
let numero = Math.floor(Math.random() * 100000000);
async function match() {
  return prisma.match.create({ data: {
    externalId: ++numero, league: 'Audit', leagueCode: 'AUDIT',
    homeTeam: 'A', awayTeam: 'B', matchDate: new Date(Date.now() + 86400000),
  } });
}
function demande(matchId: string, publish = true) {
  return { matchId, analystId, predictionType: 'win1', predictionLabel: 'Victoire A',
    oddsHome: 2, oddsDraw: 3, oddsAway: 4, oddsRecommended: 2,
    confidenceScore: 3, confidencePct: 55, isPremium: false, publish };
}
suite('Publication immuable avec PostgreSQL', () => {
  beforeAll(async () => {
    analystId = (await prisma.admin.create({ data: { name: 'Audit',
      email: marque + '@example.invalid', passwordHash: 'non-utilisable' } })).id;
  });
  afterAll(async () => {
    if (analystId) {
      const ids = (await prisma.pronostic.findMany({ where: { analystId }, select: { matchId: true } })).map(p => p.matchId);
      await nettoyerPublications({ analystId });
      await prisma.match.deleteMany({ where: { id: { in: ids } } });
      await prisma.admin.delete({ where: { id: analystId } });
    }
    await prisma.$disconnect();
  });
  it('un brouillon se modifie, puis la publication fige une copie et la date', async () => {
    const m = await match();
    const p = await svc.upsertPronostic(demande(m.id, false));
    expect(p.publicationRecordedAt).toBeNull();
    await svc.upsertPronostic({ ...demande(m.id, false), oddsRecommended: 2.2 });
    const publie = await svc.togglePublish(p.id, true, analystId);
    expect(publie.publicationRecordedAt).not.toBeNull();
    expect((publie.publicationSnapshot as any).source).toBe('first_publication');
    expect((publie.publicationSnapshot as any).pronostic.odds_recommended).toBe(2.2);
    await expect(svc.upsertPronostic(demande(m.id))).rejects.toMatchObject({ statut: 409 });
    await expect(prisma.pronostic.update({ where: { id: p.id }, data: { oddsRecommended: 9 } })).rejects.toThrow();
    await expect(prisma.pronostic.delete({ where: { id: p.id } })).rejects.toThrow();
    const retire = await svc.togglePublish(p.id, false, analystId);
    expect(retire.publishedAt).toEqual(publie.publishedAt);
    const remis = await svc.togglePublish(p.id, true, analystId);
    expect(remis.publishedAt).toEqual(publie.publishedAt);
    const events = await prisma.pronosticPublicationEvent.findMany({ where: { pronosticId: p.id }, orderBy: { id: 'asc' } });
    expect(events.map(e => e.action)).toEqual(['publication','retrait','reaffichage']);
    expect(events.every(e => e.actor === analystId)).toBe(true);
  });
  it('retirer un perdant ne gonfle pas le bilan public et sa correction est tracée', async () => {
    const m = await match(), p = await svc.upsertPronostic(demande(m.id));
    await prisma.match.update({ where: { id: m.id }, data: { status: 'FINISHED' } });
    await prisma.pronostic.update({ where: { id: p.id }, data: { result: 'LOSS' } });
    await expect(prisma.pronostic.update({ where: { id: p.id }, data: { result: null } })).rejects.toThrow();
    const avant = await svc.getPublicStats();
    await svc.togglePublish(p.id, false, analystId);
    expect(await svc.getPublicStats()).toMatchObject({ wins: avant.wins, totalFinished: avant.totalFinished, winRate: avant.winRate });
    await prisma.pronostic.update({ where: { id: p.id }, data: { result: 'WIN' } });
    const events = await prisma.pronosticPublicationEvent.findMany({ where: { pronosticId: p.id, action: 'resultat' }, orderBy: { id: 'asc' } });
    expect(events).toHaveLength(2);
    expect((events[1].beforeState as any).result).toBe('LOSS');
    expect((events[1].afterState as any).result).toBe('WIN');
    await expect(prisma.pronosticPublicationEvent.delete({ where: { id: events[1].id } })).rejects.toThrow();
  });
  it('publier après la fin est refusé même par une écriture directe', async () => {
    const m = await match(), p = await svc.upsertPronostic(demande(m.id, false));
    await prisma.match.update({ where: { id: m.id }, data: { status: 'FINISHED' } });
    await expect(svc.togglePublish(p.id, true)).rejects.toMatchObject({ statut: 409 });
    await expect(prisma.pronostic.update({ where: { id: p.id }, data: { isPublished: true } })).rejects.toThrow();
  });
  it('une modification concurrente ne réécrit jamais la sélection publiée', async () => {
    const m = await match();
    const p = await svc.upsertPronostic(demande(m.id, false));
    await Promise.allSettled([
      svc.togglePublish(p.id, true, analystId),
      svc.upsertPronostic({ ...demande(m.id, false), oddsRecommended: 3 }),
    ]);
    const final = await prisma.pronostic.findUniqueOrThrow({ where: { id: p.id } });
    expect(final.isPublished).toBe(true);
    expect((final.publicationSnapshot as any).pronostic.odds_recommended).toBe(final.oddsRecommended);
  });
});

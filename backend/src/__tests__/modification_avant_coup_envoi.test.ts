/**
 * Un pronostic publié se modifie jusqu'au coup d'envoi (12 octobre 2026).
 *
 * Une entrée de bankroll ne garde que la cote : elle est réglée sur le
 * résultat du pronostic. Si l'analyste change la sélection, l'abonné qui
 * avait validé l'ancienne serait réglé sur un pari qu'il n'a pas joué. Ses
 * entrées sont donc annulées, la mise rendue au journal, et il est prévenu.
 * Changer la cote, la confiance ou l'analyse ne touche pas à son entrée.
 */
const mockEnvois: Array<[string, { title: string; body: string }]> = [];
jest.mock('../services/notification.service', () => ({
  NotificationService: class {
    async sendToUser(userId: string, message: { title: string; body: string }) {
      mockEnvois.push([userId, message]);
    }
  },
}));
import { prisma } from '../lib/prisma';
import { placeBet, setBudget, suggestStake, verifierMouvements } from '../services/bankroll.service';
import { PronosticsService } from '../services/pronostics.service';
import { decrireSurBaseLocale } from './aides/base_locale';
import { nettoyerPublications } from './aides/nettoyer_publications';

const svc = new PronosticsService();
const marque = 'selection-' + Date.now();
let analystId: string;
let numero = Math.floor(Math.random() * 100000000);
const comptes: string[] = [];
const matchs: string[] = [];

async function compte(suffixe: string) {
  const u = await prisma.user.create({ data: {
    pseudo: `${marque}-${suffixe}`, referralCode: `${suffixe}${Date.now()}`.slice(-14).toUpperCase(),
  } });
  comptes.push(u.id);
  await setBudget(u.id, 100000, 'XOF');
  return u.id;
}
async function publie() {
  const m = await prisma.match.create({ data: {
    externalId: ++numero, league: 'Audit', leagueCode: 'AUDIT',
    homeTeam: 'Lens', awayTeam: 'Lille', matchDate: new Date(Date.now() + 86400000),
  } });
  matchs.push(m.id);
  return svc.upsertPronostic(demande(m.id));
}
function demande(matchId: string, autres: Record<string, unknown> = {}) {
  return { matchId, analystId, predictionType: 'win1', predictionLabel: 'Victoire de Lens',
    oddsHome: 2, oddsDraw: 3, oddsAway: 4, oddsRecommended: 2,
    confidenceScore: 3, confidencePct: 55, isPremium: false, publish: true, ...autres };
}
async function miser(userId: string, pronosticId: string) {
  return placeBet(userId, pronosticId, suggestStake(100000, 3, 'XOF'));
}
const solde = async (userId: string) =>
  (await prisma.userBankroll.findUniqueOrThrow({ where: { userId } })).currentBalance;

decrireSurBaseLocale('Pronostic publié modifié avant le coup d\'envoi', () => {
  beforeAll(async () => {
    analystId = (await prisma.admin.create({ data: { name: 'Audit',
      email: marque + '@example.invalid', passwordHash: 'non-utilisable' } })).id;
  });
  beforeEach(() => { mockEnvois.length = 0; });
  afterAll(async () => {
    if (analystId) {
      await nettoyerPublications({ analystId });
      await prisma.user.deleteMany({ where: { id: { in: comptes } } });
      await prisma.match.deleteMany({ where: { id: { in: matchs } } });
      await prisma.admin.delete({ where: { id: analystId } });
    }
    await prisma.$disconnect();
  });

  it('changer la cote, la confiance ou l\'analyse garde les entrées de bankroll', async () => {
    const p = await publie();
    const u = await compte('cote');
    await miser(u, p.id);
    const apresMise = await solde(u);
    await svc.upsertPronostic(demande(p.matchId, {
      oddsRecommended: 2.3, confidenceScore: 4, confidencePct: 70, analystNote: 'Lens en forme.' }));
    expect(await prisma.bankrollBet.count({ where: { pronosticId: p.id } })).toBe(1);
    expect(await solde(u)).toBe(apresMise);
    expect(mockEnvois).toHaveLength(0);
  });

  it('changer la sélection annule les entrées, rend la mise et prévient l\'abonné', async () => {
    const p = await publie();
    const u = await compte('selection');
    const pari = await miser(u, p.id);
    expect(await solde(u)).toBe(100000 - pari.stakedAmount);

    await svc.upsertPronostic(demande(p.matchId, { predictionType: 'btts', predictionLabel: 'Les deux équipes marquent' }));

    expect(await prisma.bankrollBet.count({ where: { pronosticId: p.id } })).toBe(0);
    expect(await solde(u)).toBe(100000);
    const bankroll = await prisma.userBankroll.findUniqueOrThrow({ where: { userId: u } });
    const annulation = await prisma.bankrollMouvement.findFirst({ where: { bankrollId: bankroll.id, type: 'annulation' } });
    expect(annulation).toMatchObject({ montant: pari.stakedAmount, pariId: pari.id, soldeApres: 100000 });
    expect(await verifierMouvements(bankroll.id)).toMatchObject({ coherent: true });
    expect(mockEnvois).toHaveLength(1);
    expect(mockEnvois[0][0]).toBe(u);
    expect(mockEnvois[0][1].title).toBe('Sélection modifiée');
    expect(mockEnvois[0][1].body).toContain('Lens – Lille');

    // L'abonné peut valider la nouvelle sélection.
    await expect(miser(u, p.id)).resolves.toMatchObject({ pronosticId: p.id });
  });

  it('un marché libre qui change de valeur compte comme une nouvelle sélection', async () => {
    const m = await prisma.match.create({ data: {
      externalId: ++numero, league: 'Audit', leagueCode: 'AUDIT',
      homeTeam: 'Lens', awayTeam: 'Lille', matchDate: new Date(Date.now() + 86400000),
    } });
    matchs.push(m.id);
    const libre = { predictionType: 'other', predictionLabel: 'Plus de 8,5 corners',
      marketName: 'Corners', marketValue: 'Over 8.5' };
    const p = await svc.upsertPronostic(demande(m.id, libre));
    const u = await compte('libre');
    await miser(u, p.id);
    await svc.upsertPronostic(demande(m.id, { ...libre, predictionLabel: 'Plus de 9,5 corners', marketValue: 'Over 9.5' }));
    expect(await prisma.bankrollBet.count({ where: { pronosticId: p.id } })).toBe(0);
  });

  it('match commencé : aucune modification, les entrées restent', async () => {
    const p = await publie();
    const u = await compte('direct');
    await miser(u, p.id);
    await prisma.match.update({ where: { id: p.matchId }, data: { status: 'LIVE' } });
    await expect(svc.upsertPronostic(demande(p.matchId, { predictionType: 'draw', predictionLabel: 'Match nul' })))
      .rejects.toMatchObject({ statut: 409 });
    await expect(prisma.pronostic.update({ where: { id: p.id }, data: { confidencePct: 80 } })).rejects.toThrow();
    expect(await prisma.bankrollBet.count({ where: { pronosticId: p.id } })).toBe(1);
    expect(mockEnvois).toHaveLength(0);
  });
});

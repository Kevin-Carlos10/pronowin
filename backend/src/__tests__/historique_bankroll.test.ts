/**
 * La courbe, la semaine et « Mes statistiques » (27 novembre 2026).
 *
 * Ces trois écrans ne comptaient que les mises simples, et les deux premiers
 * seulement les cinquante dernières que l'app reçoit. Depuis la 1.0.42, les
 * combinés et les couvertures enregistrées sortent aussi du solde et y
 * reviennent : sans eux, la courbe ne finissait plus sur le résultat net
 * affiché au-dessus, et la courbe de « Mes statistiques » ne finissait pas sur
 * le solde.
 */
jest.mock('../lib/prisma', () => require('./aides/base_memoire').creerBase());
jest.mock('../services/notification.service', () => ({
  NotificationService: class { async sendToUser() { /* hors sujet */ } },
  isNotifEnabled: () => true,
  NOTIF_CATEGORIES: [],
}));

import {
  getBankrollStats, listBankrolls, listBankrollsStats, placeBet, resumeParis, setBudget, settleBets,
} from '../services/bankroll.service';
import {
  bilanSemaine, courbeResultats, historiqueSolde, resultatsRegles, totaux,
} from '../services/bankroll_historique';
import { placerCombine } from '../services/combines.service';
import { enregistrerCouverture } from '../services/couvertures_enregistrees.service';
import { getStats as statistiquesProfil } from '../controllers/profile.controller';

// eslint-disable-next-line @typescript-eslint/no-var-requires
const { _base } = require('../lib/prisma');

const JOUR = 86_400_000;
const maintenant = new Date('2026-11-27T12:00:00Z');
const ilYa = (jours: number) => new Date(maintenant.getTime() - jours * JOUR);

beforeEach(() => {
  for (const t of Object.values(_base) as Map<string, any>[]) t.clear();
});

/**
 * Six mises réglées et deux en cours :
 *
 * | mise | réglée | net   | exposé |
 * |------|--------|-------|--------|
 * | k2 combiné perdu        | il y a 20 j | −300  | 300  |
 * | b2 perdu                | il y a 8 j  | −500  | 500  |
 * | k1 combiné gagné, couvert (−600) | il y a 4 j | +1 400 | 1 100 |
 * | b5 remboursé            | il y a 3 j  | 0     | 0    |
 * | b4 gagné, couvert (−300) | il y a 2 j | +500  | 1 300 |
 * | b1 gagné, posé il y a 10 j | il y a 1 j | +1 000 | 1 000 |
 */
function poserHistorique() {
  _base.bankrolls.set('b1', { id: 'b1', userId: 'u1', totalBudget: 10000, currentBalance: 12100, currency: 'XOF' });
  const pari = (id: string, result: string | null, profit: number | null, mise: number, regle: number | null, pose = 12) =>
    _base.bankrollBets.set(id, {
      id, bankrollId: 'b1', pronosticId: `p-${id}`, stakedAmount: mise, suggestedAmount: mise, oddsUsed: 2,
      potentialGain: mise * 2, result, profit, settledAt: regle == null ? null : ilYa(regle), createdAt: ilYa(pose),
    });
  pari('b1', 'WIN', 1000, 1000, 1, 10);
  pari('b2', 'LOSS', -500, 500, 8, 9);
  pari('b3', null, null, 700, null);
  pari('b4', 'WIN', 800, 1000, 2);
  pari('b5', 'PUSH', 0, 400, 3);
  const combine = (id: string, result: string | null, profit: number | null, mise: number, regle: number | null) =>
    _base.combines.set(id, {
      id, bankrollId: 'b1', stakedAmount: mise, result, profit,
      settledAt: regle == null ? null : ilYa(regle), createdAt: ilYa(25),
    });
  combine('k1', 'WIN', 2000, 500, 4);
  combine('k2', 'LOSS', -300, 300, 20);
  combine('k3', null, null, 200, null);
  _base.couvertures.set('c1', { id: 'c1', bankrollId: 'b1', pariId: 'b4', combineId: null, mise: 300, result: 'LOSS', profit: -300 });
  _base.couvertures.set('c2', { id: 'c2', bankrollId: 'b1', pariId: null, combineId: 'k1', mise: 600, result: 'LOSS', profit: -600 });
}

describe('les mises réglées', () => {
  it('simples et combinées, dans l\'ordre du règlement ; la couverture se compte avec sa mise', async () => {
    poserHistorique();
    const regles = await resultatsRegles('b1');
    expect(regles.map((r) => [r.genre, r.net, r.mise])).toEqual([
      ['combine', -300, 300],
      ['pari', -500, 500],
      ['combine', 1400, 1100],
      ['pari', 0, 0],
      ['pari', 500, 1300],
      ['pari', 1000, 1000],
    ]);
    expect(totaux(regles)).toEqual({ profit: 2100, mise: 4200 });
  });
});

describe('la courbe du résultat net', () => {
  it('cumule depuis zéro et finit sur le résultat net', async () => {
    poserHistorique();
    const courbe = courbeResultats(await resultatsRegles('b1'));
    expect(courbe.reglees).toBe(6);
    expect(courbe.cumul_depart).toBe(0);
    expect(courbe.points.map((p) => p.cumul)).toEqual([-300, -800, 600, 600, 1100, 2100]);
    expect(courbe.points[2]).toMatchObject({ genre: 'combine', le: ilYa(4).toISOString() });
  });

  it('au-delà du maximum : les dernières mises, et le cumul qui les précède', async () => {
    poserHistorique();
    const courbe = courbeResultats(await resultatsRegles('b1'), 2);
    expect(courbe).toMatchObject({ reglees: 6, cumul_depart: 600 });
    expect(courbe.points.map((p) => p.cumul)).toEqual([1100, 2100]);
  });
});

describe('cette semaine', () => {
  it('d\'après la date du règlement, combinés et couvertures compris', async () => {
    poserHistorique();
    // b1, posé il y a dix jours et gagné hier, compte ; b2, réglé il y a huit
    // jours, non.
    expect(bilanSemaine(await resultatsRegles('b1'), maintenant)).toEqual({
      paris: 3, gagnes: 2, perdus: 0, rembourses: 1, combines: 1, combines_gagnes: 1, profit: 2900,
    });
  });

  it('rien de réglé dans la semaine : tout à zéro', async () => {
    poserHistorique();
    expect(bilanSemaine(await resultatsRegles('b1'), new Date(maintenant.getTime() + 30 * JOUR)))
      .toEqual({ paris: 0, gagnes: 0, perdus: 0, rembourses: 0, combines: 0, combines_gagnes: 0, profit: 0 });
  });
});

describe('le solde jour par jour, d\'après le journal', () => {
  const mouvement = (id: string, bankrollId: string, montant: number, le: Date) =>
    _base.mouvements.set(id, { id, bankrollId, type: 'mise', montant, soldeApres: 0, creeLe: le });

  it('trente et un jours ; chaque jour garde le solde de sa fin', async () => {
    mouvement('m0', 'b1', 10000, ilYa(40));
    mouvement('m1', 'b1', -1000, ilYa(10));
    mouvement('m2', 'b1', 2000, ilYa(1));
    const h = await historiqueSolde('b1', 'XOF', maintenant);
    expect(h).toHaveLength(31);
    expect(h[0]).toEqual({ date: '2026-10-28', balance: 10000 });
    expect(h.find((p) => p.date === '2026-11-16')!.balance).toBe(10000);
    expect(h.find((p) => p.date === '2026-11-17')!.balance).toBe(9000);
    expect(h.find((p) => p.date === '2026-11-26')!.balance).toBe(11000);
    expect(h[30]).toEqual({ date: '2026-11-27', balance: 11000 });
  });

  it('une bankroll ouverte il y a trois jours : pas de zéros avant', async () => {
    mouvement('m0', 'b2', 5000, new Date('2026-11-24T08:00:00Z'));
    mouvement('m1', 'b2', -500, new Date('2026-11-26T09:00:00Z'));
    expect(await historiqueSolde('b2', 'XOF', maintenant)).toEqual([
      { date: '2026-11-24', balance: 5000 },
      { date: '2026-11-25', balance: 5000 },
      { date: '2026-11-26', balance: 4500 },
      { date: '2026-11-27', balance: 4500 },
    ]);
  });

  it('en euros, au centime près', async () => {
    mouvement('m0', 'b3', 10.1, ilYa(2));
    mouvement('m1', 'b3', 20.2, ilYa(1));
    expect((await historiqueSolde('b3', 'EUR', maintenant)).at(-1)!.balance).toBe(30.3);
  });
});

describe('de bout en bout : les trois écrans disent la même chose que le bandeau', () => {
  const demain = new Date(Date.now() + JOUR);
  function pronostic(id: string, cote: number) {
    _base.matches.set(`m-${id}`, { id: `m-${id}`, status: 'SCHEDULED', matchDate: demain, homeTeam: `A ${id}`, awayTeam: `B ${id}` });
    _base.pronostics.set(id, {
      id, matchId: `m-${id}`, confidenceScore: 5, oddsRecommended: cote, result: null, isPublished: true, isPremium: false,
      predictionType: 'over25', marketName: 'Goals Over/Under', marketValue: 'Over 2.5', predictionLabel: 'Plus de 2,5 buts',
    });
  }

  it('mise couverte, combiné, mise simple : courbe, bilan, statistiques et solde concordent', async () => {
    _base.users.set('u1', { id: 'u1', subscriptionPlan: 'free' });
    await setBudget('u1', 100000, 'XOF');
    const id = [..._base.bankrolls.values()][0].id;
    pronostic('p1', 2); pronostic('p2', 2); pronostic('p3', 2); pronostic('p4', 2);

    // Une mise couverte qui perd : −5 000 + 7 500.
    await placeBet('u1', 'p1', 5000);
    const pari = [..._base.bankrollBets.values()][0];
    await enregistrerCouverture('u1', { pari_id: pari.id, mise: 2500, cote: 4 });
    await settleBets('p1', 'LOSS');
    // Un combiné gagné.
    const solde = () => [..._base.bankrolls.values()][0].currentBalance;
    const miseCombine = Math.floor(solde() * 0.05);
    await placerCombine('u1', [{ pronostic_id: 'p2' }, { pronostic_id: 'p3' }], miseCombine);
    await settleBets('p2', 'WIN');
    await settleBets('p3', 'WIN');
    // Une mise simple encore en cours : elle n'est pas dans le résultat.
    await placeBet('u1', 'p4', Math.floor(solde() * 0.05));

    const resume = await resumeParis(id);
    const regles = await resultatsRegles(id);
    expect(resume.profit_net).toBe(2500 + miseCombine * 3);
    expect(courbeResultats(regles).points.at(-1)!.cumul).toBe(resume.profit_net);
    expect(bilanSemaine(regles).profit).toBe(resume.profit_net);
    expect((await getBankrollStats('u1'))!.totalProfit).toBe(resume.profit_net);

    // « Mes statistiques » : le même résultat net, et une courbe qui finit
    // sur le solde réel, mise en cours déduite.
    const reponse: any = { json: jest.fn() };
    reponse.status = jest.fn(() => reponse);
    await statistiquesProfil({ userId: 'u1' } as any, reponse);
    const stats = reponse.json.mock.calls[0][0];
    expect(stats.profit_net).toBe(resume.profit_net);
    expect(stats.total_mise).toBe(5000 + 2500 + miseCombine);
    expect(stats.bankroll_history.at(-1).balance).toBe(solde());
    expect(stats.paris_gagnes).toBe(0);
    expect(stats.paris_perdus).toBe(1);
  });

  it('sans bankroll : des statistiques vides, pas une erreur', async () => {
    const reponse: any = { json: jest.fn() };
    reponse.status = jest.fn(() => reponse);
    await statistiquesProfil({ userId: 'personne' } as any, reponse);
    expect(reponse.status).not.toHaveBeenCalled();
    expect(reponse.json.mock.calls[0][0]).toMatchObject({ profit_net: 0, bankroll_history: [], pronostics_suivis: 0 });
  });
});

describe("la vue d'ensemble du panneau (28 novembre 2026)", () => {
  function avecUnPortefeuilleEnEuros() {
    poserHistorique();
    _base.users.set('u1', { id: 'u1', pseudo: 'Parieur' });
    _base.users.set('u2', { id: 'u2', pseudo: 'Parieuse' });
    _base.bankrolls.set('b2', { id: 'b2', userId: 'u2', totalBudget: 100, currentBalance: 105.5, currency: 'EUR' });
    _base.bankrollBets.set('e1', {
      id: 'e1', bankrollId: 'b2', pronosticId: 'p-e1', stakedAmount: 10, suggestedAmount: 10, oddsUsed: 1.55,
      potentialGain: 15.5, result: 'WIN', profit: 5.5, settledAt: ilYa(1), createdAt: ilYa(2),
    });
  }

  it('les totaux par devise, combinés et couvertures compris', async () => {
    avecUnPortefeuilleEnEuros();
    const st = await listBankrollsStats();
    // Les francs et les euros ne s'additionnent plus.
    expect(st.devises).toEqual([
      { devise: 'XOF', bankrolls: 1, total_budget: 10000, total_balance: 12100, total_profit: 2100, roi: 50 },
      { devise: 'EUR', bankrolls: 1, total_budget: 100, total_balance: 105.5, total_profit: 5.5, roi: 55 },
    ]);
    expect(st.combines).toEqual({ total: 3, en_attente: 1, gagnes: 1, perdus: 1 });
    expect(st.couvertures).toEqual({ total: 2, en_attente: 0 });
    // Le taux de réussite reste celui des sélections simples : 3 gagnées
    // (b1, b4, e1) sur 4 tranchées.
    expect(st.win_rate).toBe(75);
  });

  it('chaque portefeuille : profit et rendement avec ses combinés et ses couvertures', async () => {
    avecUnPortefeuilleEnEuros();
    const { data } = await listBankrolls({ page: 1, perPage: 20 });
    const b1 = data.find((r) => r.user_id === 'u1')!;
    expect(b1).toMatchObject({
      total_profit: 2100, roi: 50, wins: 2, losses: 1, total_bets: 5, pending_bets: 1,
      combines: 3, combines_en_attente: 1, couvertures: 2,
    });
    expect(data.find((r) => r.user_id === 'u2')).toMatchObject({ currency: 'EUR', total_profit: 5.5, combines: 0 });
  });
});

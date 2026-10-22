/**
 * Bankroll : montants exacts, journal des mouvements, devise verrouillée (B1),
 * mise réelle confirmée au résultat (M1), plafond d'exposition (B2) — constats
 * de l'audit du 24 septembre 2026.
 *
 * B1 — Le solde n'était qu'un nombre modifié sur place : impossible à
 *      reconstituer en cas de contestation. Les gains gardaient des centimes
 *      de franc CFA qui n'existent pas. Et changer la devise ré-étiquetait les
 *      montants : 100 000 XOF devenaient 100 000 EUR.
 * M1 — La mise enregistrée était toujours la mise conseillée ; le pari réel,
 *      placé chez le bookmaker, était invisible.
 * B2 — Chaque mise respectait le barème, mais rien ne limitait leur somme.
 */
jest.mock('../lib/prisma', () => require('./aides/base_memoire').creerBase());
jest.mock('../services/notification.service', () => ({
  NotificationService: class { async sendToUser() { /* hors sujet */ } },
}));

import {
  CONFIRMATION_DEPUIS, confirmerMise, miseAConfirmer, placeBet, setBudget, settleBets, verifierMouvements,
} from '../services/bankroll.service';
import { ecrireConfig } from '../services/app_config.service';

// eslint-disable-next-line @typescript-eslint/no-var-requires
const { _base } = require('../lib/prisma');

const demain = new Date(Date.now() + 86400000);

/** Un pronostic ouvert, note 5 (mise de 5 %), à la cote donnée. */
function pronostic(id: string, cote: number) {
  _base.matches.set(`m-${id}`, { id: `m-${id}`, status: 'scheduled', matchDate: demain });
  _base.pronostics.set(id, {
    id, matchId: `m-${id}`, confidenceScore: 5, oddsRecommended: cote, result: null });
}

const bankroll = (userId = 'u1') =>
  [..._base.bankrolls.values()].find((b: any) => b.userId === userId);
const mouvements = () => [..._base.mouvements.values()];
const pari = (pronosticId: string) =>
  [..._base.bankrollBets.values()].find((b: any) => b.pronosticId === pronosticId);

beforeEach(async () => {
  for (const t of Object.values(_base) as Map<string, any>[]) t.clear();
  delete process.env.BANKROLL_PLAFOND_EXPOSITION;
  _base.users.set('u1', { id: 'u1' });
  _base.users.set('u2', { id: 'u2' });
  await setBudget('u1', 100000, 'XOF');
});

describe('journal des mouvements et montants exacts (B1)', () => {
  it('chaque variation du solde est au journal, et leur somme vaut le solde', async () => {
    pronostic('p1', 2);
    pronostic('p2', 1.5);
    await placeBet('u1', 'p1', 5000);
    await placeBet('u1', 'p2', 4750);
    await settleBets('p1', 'WIN');
    await settleBets('p2', 'LOSS');

    expect(mouvements().map((m: any) => [m.type, m.montant])).toEqual([
      ['ouverture', 100000], ['mise', -5000], ['mise', -4750], ['reglement', 10000]]);
    expect(bankroll().currentBalance).toBe(100250);
    expect(await verifierMouvements(bankroll().id))
      .toMatchObject({ coherent: true, solde: 100250, reconstitue: 100250, ecart: 0 });
  });

  it('une écriture hors du journal se voit', async () => {
    // Le contrôle doit pouvoir échouer : sinon il ne prouve rien.
    bankroll().currentBalance += 1000;
    expect(await verifierMouvements(bankroll().id)).toMatchObject({ coherent: false, ecart: 1000 });
  });

  it('un gain potentiel est arrondi au franc inférieur, pas gardé avec des centimes', async () => {
    pronostic('p1', 1.7333);
    await placeBet('u1', 'p1', 5000);
    expect(pari('p1').potentialGain).toBe(8666); // 8 666,5 : le demi-franc n'existe pas
  });

  it('la devise ne change plus après le premier pari', async () => {
    pronostic('p1', 2);
    await placeBet('u1', 'p1', 5000);
    await expect(setBudget('u1', 150, 'EUR')).rejects.toMatchObject({ code: 'CURRENCY_LOCKED', statut: 409 });
    expect(bankroll()).toMatchObject({ currency: 'XOF', currentBalance: 95000 });
  });

  it('avant tout pari, changer de devise repart du nouveau budget', async () => {
    await setBudget('u2', 100000, 'XOF');
    await setBudget('u2', 150, 'EUR');
    expect(bankroll('u2')).toMatchObject({ currency: 'EUR', totalBudget: 150, currentBalance: 150 });
    expect((await verifierMouvements(bankroll('u2').id))?.coherent).toBe(true);
  });

  it('un budget modifié sans devise garde celle de la bankroll', async () => {
    // Le défaut « XOF » du service ré-étiquetait une bankroll en euros.
    await setBudget('u2', 150, 'EUR');
    await setBudget('u2', 200);
    expect(bankroll('u2')).toMatchObject({ currency: 'EUR', totalBudget: 200, currentBalance: 150 });
  });
});

describe('mise réelle confirmée au résultat (M1)', () => {
  beforeEach(() => pronostic('p1', 2));

  it('confirmer la mise ne déplace rien', async () => {
    await placeBet('u1', 'p1', 5000);
    await settleBets('p1', 'WIN');
    const avant = mouvements().length;

    await expect(confirmerMise('u1', pari('p1').id)).resolves.toMatchObject({ corrigee: false, mise: 5000 });
    expect(pari('p1').miseConfirmeeLe).toBeInstanceOf(Date);
    expect(mouvements()).toHaveLength(avant);
    expect(bankroll().currentBalance).toBe(105000);
  });

  it('une mise réelle plus faible sur un pari gagné rejoue la mise et le gain', async () => {
    await placeBet('u1', 'p1', 5000);
    await settleBets('p1', 'WIN');                          // 100 000 − 5 000 + 10 000
    await confirmerMise('u1', pari('p1').id, 3000);

    expect(bankroll().currentBalance).toBe(103000);        // 100 000 − 3 000 + 6 000
    expect(pari('p1')).toMatchObject({ stakedAmount: 3000, suggestedAmount: 5000, potentialGain: 6000, profit: 3000 });
    expect(mouvements().at(-1)).toMatchObject({ type: 'correction_mise', montant: -2000, soldeApres: 103000 });
    expect((await verifierMouvements(bankroll().id))?.coherent).toBe(true);
  });

  it('« je n\'ai pas misé » sur une défaite rend la mise, et le pari reste perdu', async () => {
    // Le classement ne compte que les résultats : une mise déclarée nulle ne
    // doit pas effacer une défaite.
    await placeBet('u1', 'p1', 5000);
    await settleBets('p1', 'LOSS');
    await confirmerMise('u1', pari('p1').id, 0);

    expect(bankroll().currentBalance).toBe(100000);
    expect(pari('p1')).toMatchObject({ result: 'LOSS', stakedAmount: 0, profit: 0 });
  });

  it('une seule réponse, même envoyée deux fois en même temps', async () => {
    await placeBet('u1', 'p1', 5000);
    await settleBets('p1', 'LOSS');
    const issues = await Promise.allSettled([
      confirmerMise('u1', pari('p1').id, 0), confirmerMise('u1', pari('p1').id, 0)]);

    expect(issues.filter(i => i.status === 'fulfilled')).toHaveLength(1);
    expect(bankroll().currentBalance).toBe(100000);        // la mise rendue une fois, pas deux
    await expect(confirmerMise('u1', pari('p1').id)).rejects.toMatchObject({ code: 'STAKE_ALREADY_CONFIRMED' });
  });

  it('pas avant le résultat, pas pour le pari d\'un autre, pas au-delà du solde', async () => {
    await placeBet('u1', 'p1', 5000);
    await expect(confirmerMise('u1', pari('p1').id)).rejects.toMatchObject({ code: 'BET_PENDING' });
    await settleBets('p1', 'LOSS');
    await expect(confirmerMise('u2', pari('p1').id)).rejects.toMatchObject({ statut: 404 });
    await expect(confirmerMise('u1', pari('p1').id, 10_000_000))
      .rejects.toMatchObject({ code: 'INSUFFICIENT_BALANCE' });
    expect(bankroll().currentBalance).toBe(95000);
  });
});

describe('plafond d\'exposition (B2)', () => {
  beforeEach(() => ['p1', 'p2', 'p3'].forEach(p => pronostic(p, 2)));

  it('le réglage n\'accepte qu\'un pourcentage entier de 5 à 100', async () => {
    // Sous 5 %, un seul pari noté 5 ne passerait plus jamais.
    for (const v of ['3', '101', '12.5', 'abc']) {
      await expect(ecrireConfig({ BANKROLL_PLAFOND_EXPOSITION: v })).rejects.toThrow(/5 à 100/);
    }
  });

  it('sans plafond réglé, rien ne limite la somme des mises', async () => {
    await placeBet('u1', 'p1', 5000);
    await placeBet('u1', 'p2', 4750);
    await expect(placeBet('u1', 'p3', 4512)).resolves.toBeDefined();
  });

  it('à 12 %, la troisième mise de 5 % est refusée, et passe une fois un pari réglé', async () => {
    process.env.BANKROLL_PLAFOND_EXPOSITION = '12';
    await placeBet('u1', 'p1', 5000);                      // engagé 5 000 sur 100 000
    await placeBet('u1', 'p2', 4750);                      // 9 750
    await expect(placeBet('u1', 'p3', 4512))               // 14 262 > 12 000
      .rejects.toMatchObject({ code: 'EXPOSURE_CAP', statut: 409 });
    expect(bankroll().currentBalance).toBe(90250);         // rien n'a bougé

    await settleBets('p1', 'LOSS');                        // engagé 4 750 sur 95 000
    await expect(placeBet('u1', 'p3', 4512)).resolves.toBeDefined();
  });
});

describe('quand la question est posée (M1)', () => {
  const regle = (settledAt: Date, miseConfirmeeLe: Date | null = null) =>
    ({ result: 'WIN', settledAt, miseConfirmeeLe });
  const maintenant = new Date('2026-10-20T12:00:00Z');
  const jours = (n: number) => new Date(maintenant.getTime() - n * 86400000);

  it('pour un pari réglé depuis peu, sans réponse', () => {
    expect(miseAConfirmer(regle(jours(1)), maintenant)).toBe(true);
  });

  it('plus après deux semaines, ni une fois répondu, ni avant le résultat', () => {
    expect(miseAConfirmer(regle(jours(15)), maintenant)).toBe(false);
    expect(miseAConfirmer(regle(jours(1), jours(0)), maintenant)).toBe(false);
    expect(miseAConfirmer({ result: null, settledAt: null, miseConfirmeeLe: null }, maintenant)).toBe(false);
  });

  it('pas pour les paris réglés avant la mise en service de la question', () => {
    const lancement = CONFIRMATION_DEPUIS;
    const peuApres = new Date(lancement.getTime() + 3 * 86400000);
    expect(miseAConfirmer(regle(new Date(lancement.getTime() - 3600000)), peuApres)).toBe(false);
    expect(miseAConfirmer(regle(new Date(lancement.getTime() + 3600000)), peuApres)).toBe(true);
  });
});

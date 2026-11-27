/**
 * Combinés et couvertures enregistrées (27 novembre 2026) : l'argent.
 *
 * - un combiné prend le barème de sa sélection la moins sûre (une sélection
 *   libre compte pour la note 1), sa mise sort du solde, et son règlement
 *   rend mise × produit des cotes gagnées ;
 * - une sélection perdue suffit, une remboursée ou annulée compte pour 1 ;
 * - « J'ai couvert » sort la mise sur l'inverse, qui gagne quand la sélection
 *   perd ;
 * - réinitialiser la bankroll garde engagé tout ce qui l'est encore ;
 * - le journal rend toujours compte du solde.
 */
jest.mock('../lib/prisma', () => require('./aides/base_memoire').creerBase());
jest.mock('../services/notification.service', () => ({
  NotificationService: class { async sendToUser() { /* hors sujet */ } },
  isNotifEnabled: () => true,
}));

import {
  annulerParisSelectionModifiee, placeBet, resetBankroll, resumeParis, setBudget, settleBets, verifierMouvements,
} from '../services/bankroll.service';
import {
  apercuCombine, coteTotale, derniereSelectionOuverte, etatCombine, placerCombine, reglerSelectionLibre,
} from '../services/combines.service';
import { enregistrerCouverture } from '../services/couvertures_enregistrees.service';
import { prisma } from '../lib/prisma';

// eslint-disable-next-line @typescript-eslint/no-var-requires
const { _base } = require('../lib/prisma');

const demain = new Date(Date.now() + 86400000);

/** Un pronostic publié et ouvert : note, cote, marché. */
function pronostic(id: string, cote: number, note = 5, extra: Record<string, unknown> = {}) {
  _base.matches.set(`m-${id}`, {
    id: `m-${id}`, status: 'SCHEDULED', matchDate: demain, homeTeam: `Dom ${id}`, awayTeam: `Ext ${id}`,
  });
  _base.pronostics.set(id, {
    id, matchId: `m-${id}`, confidenceScore: note, oddsRecommended: cote, result: null,
    isPublished: true, isPremium: false, predictionType: 'over25', marketName: 'Goals Over/Under', marketValue: 'Over 2.5',
    predictionLabel: 'Plus de 2,5 buts', ...extra,
  });
}

const bankroll = () => [..._base.bankrolls.values()].find((b: any) => b.userId === 'u1');
const combine = () => [..._base.combines.values()][0];
const lignes = () => [..._base.selectionsCombine.values()].sort((a: any, b: any) => a.ordre - b.ordre);
const coherent = async () => (await verifierMouvements(bankroll().id))?.coherent;

beforeEach(async () => {
  for (const t of Object.values(_base) as Map<string, any>[]) t.clear();
  _base.users.set('u1', { id: 'u1', subscriptionPlan: 'free' });
  await setBudget('u1', 100000, 'XOF');
});

describe('le calcul d\'un combiné', () => {
  it('perdu dès qu\'une sélection perd ; en attente sinon ; remboursée ou annulée = cote 1', () => {
    expect(etatCombine(1000, [{ cote: 2, result: 'LOSS' }, { cote: 3, result: null }], 'XOF')).toEqual({ result: 'LOSS', retour: 0 });
    expect(etatCombine(1000, [{ cote: 2, result: 'WIN' }, { cote: 3, result: null }], 'XOF')).toEqual({ result: null, retour: null });
    expect(etatCombine(1000, [{ cote: 2, result: 'WIN' }, { cote: 3, result: 'PUSH' }], 'XOF')).toEqual({ result: 'WIN', retour: 2000 });
    expect(etatCombine(1000, [{ cote: 2, result: null, annulee: true }, { cote: 3, result: 'WIN' }], 'XOF')).toEqual({ result: 'WIN', retour: 3000 });
    expect(etatCombine(1000, [{ cote: 2, result: 'PUSH' }, { cote: 3, result: 'PUSH' }], 'XOF')).toEqual({ result: 'PUSH', retour: 1000 });
    expect(coteTotale([1.85, 2.1, 1.5])).toBe(5.828);
  });

  it('la dernière sélection ouverte : seulement si les autres sont passées', () => {
    const l = (result: string | null, pronosticId: string | null = 'p') => ({ cote: 2, result, pronosticId });
    expect(derniereSelectionOuverte([l('WIN'), l(null, 'p2')])?.pronosticId).toBe('p2');
    expect(derniereSelectionOuverte([l('LOSS'), l(null)])).toBeNull();
    expect(derniereSelectionOuverte([l(null), l(null)])).toBeNull();
    expect(derniereSelectionOuverte([l('WIN'), l(null, null)])).toBeNull();   // sélection libre : pas de cote à lire
  });
});

describe('poser un combiné', () => {
  it('le barème de la sélection la moins sûre ; une sélection libre compte pour la note 1', async () => {
    pronostic('p1', 2, 5);
    pronostic('p2', 1.5, 3);
    expect(await apercuCombine('u1', [{ pronostic_id: 'p1' }, { pronostic_id: 'p2' }]))
      .toMatchObject({ mise: 3000, note_retenue: 3, cote_totale: 3, gain_potentiel: 9000 });
    expect(await apercuCombine('u1', [{ pronostic_id: 'p1' }, { libre: { match: 'PSG – OM', selection: 'PSG gagne', cote: 1.8 } }]))
      .toMatchObject({ mise: 1500, note_retenue: 1, cote_totale: 3.6, gain_potentiel: 5400 });
  });

  it('la mise sort du solde, au journal ; les sélections sont gardées dans l\'ordre', async () => {
    pronostic('p1', 2, 5);
    pronostic('p2', 1.5, 3);
    await placerCombine('u1', [{ pronostic_id: 'p1' }, { pronostic_id: 'p2' }], 3000);
    expect(bankroll().currentBalance).toBe(97000);
    expect(combine()).toMatchObject({ stakedAmount: 3000, oddsUsed: 3, potentialGain: 9000, noteRetenue: 3, result: null });
    expect(lignes().map((l: any) => [l.pronosticId, l.cote, l.note])).toEqual([['p1', 2, 5], ['p2', 1.5, 3]]);
    expect(await coherent()).toBe(true);
  });

  it('une mise qui ne correspond plus au barème est refusée', async () => {
    pronostic('p1', 2, 5);
    pronostic('p2', 1.5, 3);
    await expect(placerCombine('u1', [{ pronostic_id: 'p1' }, { pronostic_id: 'p2' }], 5000))
      .rejects.toMatchObject({ code: 'STAKE_CHANGED' });
    expect(bankroll().currentBalance).toBe(100000);
  });

  it('refusés : une seule sélection, plus de dix, deux fois le même match, un match commencé, un VIP verrouillé', async () => {
    pronostic('p1', 2);
    pronostic('p2', 2);
    await expect(apercuCombine('u1', [{ pronostic_id: 'p1' }])).rejects.toMatchObject({ code: 'COMBINE_SIZE' });
    const onze = Array.from({ length: 11 }, (_, i) => ({ libre: { match: `Match ${i}`, selection: 'Gagne', cote: 1.5 } }));
    await expect(apercuCombine('u1', onze)).rejects.toMatchObject({ code: 'COMBINE_SIZE' });

    _base.pronostics.set('p1b', { ..._base.pronostics.get('p1'), id: 'p1b' });
    await expect(apercuCombine('u1', [{ pronostic_id: 'p1' }, { pronostic_id: 'p1b' }])).rejects.toMatchObject({ code: 'COMBINE_SAME_MATCH' });

    _base.matches.get('m-p2').status = 'LIVE';
    await expect(apercuCombine('u1', [{ pronostic_id: 'p1' }, { pronostic_id: 'p2' }])).rejects.toMatchObject({ code: 'BET_CLOSED' });

    pronostic('vip', 2, 5, { isPremium: true });
    await expect(apercuCombine('u1', [{ pronostic_id: 'p1' }, { pronostic_id: 'vip' }])).rejects.toMatchObject({ code: 'PREMIUM_REQUIRED' });
  });
});

describe('régler un combiné', () => {
  beforeEach(async () => {
    pronostic('p1', 2, 5);
    pronostic('p2', 1.5, 5);
    await placerCombine('u1', [
      { pronostic_id: 'p1' }, { pronostic_id: 'p2' }, { libre: { match: 'PSG – OM', selection: 'PSG gagne', cote: 2 } },
    ], 1500);   // la sélection libre fixe la note 1 : 1,5 % de 100 000
  });

  it('tout passe : mise × produit des cotes, au journal', async () => {
    await settleBets('p1', 'WIN');
    await settleBets('p2', 'WIN');
    expect(combine().result).toBeNull();
    await reglerSelectionLibre('u1', combine().id, lignes()[2].id, 'WIN');
    expect(combine()).toMatchObject({ result: 'WIN', retour: 9000, profit: 7500 });
    expect(bankroll().currentBalance).toBe(100000 - 1500 + 9000);
    expect(await coherent()).toBe(true);
  });

  it('une sélection perd : perdu tout de suite, et une correction rejoue seulement la différence', async () => {
    await settleBets('p1', 'LOSS');
    expect(combine()).toMatchObject({ result: 'LOSS', retour: 0, profit: -1500 });
    await settleBets('p2', 'WIN');
    await reglerSelectionLibre('u1', combine().id, lignes()[2].id, 'PUSH');
    expect(bankroll().currentBalance).toBe(98500);

    // L'analyste corrige p1 : gagné. Il ne reste que la sélection libre, remboursée.
    await settleBets('p1', 'WIN');
    expect(combine()).toMatchObject({ result: 'WIN', retour: 4500 });
    expect(bankroll().currentBalance).toBe(98500 + 4500);
    expect(await coherent()).toBe(true);
  });

  it('le pronostic est retiré avant le coup d\'envoi : sa sélection compte pour 1, le combiné continue', async () => {
    await prisma.$transaction((tx: any) => annulerParisSelectionModifiee(tx, 'p2'));
    expect(lignes()[1]).toMatchObject({ annulee: true });
    await settleBets('p1', 'WIN');
    await reglerSelectionLibre('u1', combine().id, lignes()[2].id, 'WIN');
    expect(combine()).toMatchObject({ result: 'WIN', retour: 6000 });   // 1 500 × 2 × 1 × 2
    expect(await coherent()).toBe(true);
  });

  it('une sélection PronoWin ne se règle pas à la main', async () => {
    await expect(reglerSelectionLibre('u1', combine().id, lignes()[0].id, 'WIN'))
      .rejects.toMatchObject({ code: 'SELECTION_NOT_FREE' });
  });

  it('le bilan compte le combiné dans l\'engagé, puis dans le résultat net', async () => {
    expect((await resumeParis(bankroll().id))).toMatchObject({ mises_en_cours: 1500, combines: { total: 1, en_attente: 1 } });
    await settleBets('p1', 'LOSS');
    expect((await resumeParis(bankroll().id))).toMatchObject({ mises_en_cours: 0, profit_net: -1500, combines: { perdus: 1 } });
  });
});

describe('« J\'ai couvert »', () => {
  beforeEach(() => pronostic('p1', 2, 5));

  it('la mise sur l\'inverse sort du solde ; elle gagne quand la sélection perd', async () => {
    await placeBet('u1', 'p1', 5000);
    const pari = [..._base.bankrollBets.values()][0];
    await enregistrerCouverture('u1', { pari_id: pari.id, mise: 2500, cote: 4, strategie: 'gain_egal' });
    expect(bankroll().currentBalance).toBe(92500);
    expect([..._base.couvertures.values()][0]).toMatchObject({ selectionFr: 'Moins de 2,5 buts', mise: 2500, cote: 4 });

    await settleBets('p1', 'LOSS');
    // Mise perdue (−5 000), couverture gagnée (+7 500) : +2 500 au total.
    expect(bankroll().currentBalance).toBe(92500 + 10000);
    expect([..._base.couvertures.values()][0]).toMatchObject({ result: 'WIN', profit: 7500 });
    expect((await resumeParis(bankroll().id)).profit_net).toBe(2500);
    expect(await coherent()).toBe(true);
  });

  it('une seule couverture par mise ; pas de couverture sur un marché sans inverse ni sur une mise réglée', async () => {
    await placeBet('u1', 'p1', 5000);
    const pari = [..._base.bankrollBets.values()][0];
    await enregistrerCouverture('u1', { pari_id: pari.id, mise: 2500, cote: 4 });
    await expect(enregistrerCouverture('u1', { pari_id: pari.id, mise: 100, cote: 4 })).rejects.toMatchObject({ code: 'HEDGE_EXISTS' });

    pronostic('p2', 3, 5, { marketName: 'Exact Score', marketValue: '2:1', predictionType: 'other' });
    await placeBet('u1', 'p2', 4625);
    const autre = [..._base.bankrollBets.values()].find((b: any) => b.pronosticId === 'p2');
    await expect(enregistrerCouverture('u1', { pari_id: autre.id, mise: 100, cote: 4 })).rejects.toMatchObject({ code: 'HEDGE_MARKET' });
  });

  it('la sélection modifiée avant le coup d\'envoi : la mise et sa couverture sont rendues', async () => {
    await placeBet('u1', 'p1', 5000);
    const pari = [..._base.bankrollBets.values()][0];
    await enregistrerCouverture('u1', { pari_id: pari.id, mise: 2500, cote: 4 });
    await prisma.$transaction((tx: any) => annulerParisSelectionModifiee(tx, 'p1'));
    expect(bankroll().currentBalance).toBe(100000);
    expect(_base.couvertures.size).toBe(0);
    expect(await coherent()).toBe(true);
  });

  it('un combiné se couvre sur sa dernière sélection, contre son gain entier', async () => {
    pronostic('p2', 2, 5);
    await placerCombine('u1', [{ pronostic_id: 'p1' }, { pronostic_id: 'p2' }], 5000);
    await expect(enregistrerCouverture('u1', { combine_id: combine().id, mise: 1000, cote: 4 }))
      .rejects.toMatchObject({ code: 'HEDGE_NOT_READY' });
    await settleBets('p1', 'WIN');
    await enregistrerCouverture('u1', { combine_id: combine().id, mise: 5000, cote: 4 });
    expect([..._base.couvertures.values()][0]).toMatchObject({ pronosticId: 'p2', combineId: combine().id });

    // La dernière sélection perd : le combiné perd, la couverture gagne 20 000.
    await settleBets('p2', 'LOSS');
    expect(combine().result).toBe('LOSS');
    expect(bankroll().currentBalance).toBe(100000 - 5000 - 5000 + 20000);
    expect(await coherent()).toBe(true);
  });

  it('réinitialiser garde engagés le combiné et la couverture en cours', async () => {
    pronostic('p2', 2, 5);
    await placeBet('u1', 'p1', 5000);
    const pari = [..._base.bankrollBets.values()][0];
    await enregistrerCouverture('u1', { pari_id: pari.id, mise: 2500, cote: 4 });
    await placerCombine('u1', [{ pronostic_id: 'p2' }, { libre: { match: 'A – B', selection: 'A gagne', cote: 2 } }], 1387);   // 1,5 % de 92 500
    await resetBankroll('u1');
    expect(bankroll().currentBalance).toBe(100000 - 5000 - 2500 - 1387);
  });
});

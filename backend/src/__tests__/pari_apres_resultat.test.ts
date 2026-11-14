/**
 * On ne mise pas sur un match dont on connaît déjà l'issue.
 *
 * `placeBet` contrôlait le solde, le montant et les doublons — jamais le
 * match. On pouvait donc enregistrer une mise sur un pronostic **déjà réglé**,
 * dont le résultat est public.
 *
 * Et ce n'était pas seulement atteignable par l'API : l'écran ne masquait le
 * bouton « Miser » que sur `status == 'finished'`. Pendant un match **en
 * direct**, score affiché à côté, le bouton restait là. Le parcours normal de
 * l'application permettait de miser en connaissant une partie du résultat.
 *
 * Ce que ça abîme dépasse le compte de l'intéressé : cet historique alimente
 * le classement public. Un classement où l'on peut ajouter après coup les
 * paris gagnants ne vaut rien, et c'est lui qui donne du crédit au reste.
 */
jest.mock('../lib/prisma', () => require('./aides/base_memoire').creerBase());

jest.mock('../services/notification.service', () => ({
  NotificationService: class {
    async sendToUser() { /* rien : les notifications ne sont pas le sujet */ }
  },
}));

import { PariFerme, placeBet } from '../services/bankroll.service';
import { MESSAGE_REFUS, refusDePari } from '../services/verrou_pari';

const { _base } = require('../lib/prisma');

const HEURE = 3_600_000;

/** Pose une bankroll et un pronostic dans l'état demandé. */
function poser(opts: {
  resultat?: string | null;
  statut?:   string;
  dansCombienDHeures?: number;
}) {
  for (const t of Object.values(_base) as Map<string, any>[]) t.clear();

  _base.users.set('u1', { id: 'u1', pseudo: 'Parieur' });
  _base.userBankrolls = _base.userBankrolls ?? new Map();

  _base.bankrolls.set('b1', {
    id: 'b1', userId: 'u1', totalBudget: 10_000,
    currentBalance: 10_000, currency: 'XOF',
  });
  _base.matches.set('m1', {
    id: 'm1', homeTeam: 'PSG', awayTeam: 'OM',
    status: opts.statut ?? 'SCHEDULED',
    matchDate: new Date(Date.now() + (opts.dansCombienDHeures ?? 24) * HEURE),
  });
  _base.pronostics.set('p1', {
    id: 'p1', matchId: 'm1', confidenceScore: 4,
    oddsRecommended: 1.85, result: opts.resultat ?? null,
  });
}

const miser = (montant = 1000) => placeBet('u1', 'p1', montant);
const solde = () => _base.bankrolls.get('b1').currentBalance;

describe('la saisie ferme au coup d\'envoi', () => {
  it('un match à venir accepte la mise', async () => {
    // Contrepartie indispensable : une règle qui refuserait tout passerait
    // tous les tests ci-dessous sans rien protéger, et la bankroll serait
    // inutilisable.
    poser({ dansCombienDHeures: 24 });

    const pari = await miser(300);

    expect(pari).toBeDefined();
    expect(solde()).toBe(9700);
    expect(_base.bankrollBets.size).toBe(1);
  });

  it('un pronostic déjà gagnant est refusé', async () => {
    poser({ resultat: 'WIN', statut: 'FINISHED', dansCombienDHeures: -3 });

    await expect(miser()).rejects.toBeInstanceOf(PariFerme);
    expect(_base.bankrollBets.size).toBe(0);
    expect(solde()).toBe(10_000);
  });

  it('un pronostic réglé avant l\'heure du match est refusé aussi', async () => {
    // Isole le contrôle du résultat : le match n'a pas commencé, donc rien
    // d'autre ne ferme la saisie. Un pronostic réglé alors que le match est à
    // venir signale une correction manuelle — l'issue n'est plus incertaine.
    poser({ resultat: 'WIN', statut: 'SCHEDULED', dansCombienDHeures: 6 });

    await expect(miser()).rejects.toMatchObject({ motif: 'resultat_connu' });
    expect(_base.bankrollBets.size).toBe(0);
  });

  it('un match en direct est refusé', async () => {
    // Le cas que l'écran laissait passer : le score est déjà partiellement
    // connu, et le bouton « Miser » restait affiché.
    poser({ statut: 'LIVE', dansCombienDHeures: -1 });

    await expect(miser()).rejects.toThrow(MESSAGE_REFUS.match_commence);
    expect(_base.bankrollBets.size).toBe(0);
  });

  it('un match marqué en direct est refusé, même si l\'heure dit le contraire', async () => {
    // Les deux contrôles se recouvrent volontairement, mais chacun doit tenir
    // seul : ici l'heure autoriserait la mise, et c'est le statut qui ferme.
    // Sans ce cas, retirer « live » de la règle ne faisait tomber aucun test
    // d'intégration — vérifié en le retirant.
    poser({ statut: 'LIVE', dansCombienDHeures: 2 });

    await expect(miser()).rejects.toBeInstanceOf(PariFerme);
    expect(_base.bankrollBets.size).toBe(0);
  });

  it('un match commencé mais encore marqué « à venir » est refusé', async () => {
    // Le statut vient d'une synchronisation périodique : entre le coup
    // d'envoi et la synchronisation suivante, il dit encore SCHEDULED. Se
    // fier au seul statut laisserait une fenêtre ouverte à chaque match.
    poser({ statut: 'SCHEDULED', dansCombienDHeures: -0.5 });

    await expect(miser()).rejects.toBeInstanceOf(PariFerme);
    expect(_base.bankrollBets.size).toBe(0);
  });

  it('le refus n\'entame pas le solde', async () => {
    // La déduction a lieu dans la transaction, après ce contrôle. S'il
    // passait après, un pari refusé coûterait quand même la mise.
    poser({ resultat: 'LOSS', statut: 'FINISHED', dansCombienDHeures: -3 });

    await expect(miser(2500)).rejects.toBeInstanceOf(PariFerme);
    expect(solde()).toBe(10_000);
  });

  it('le motif du refus est porté par l\'erreur', async () => {
    poser({ resultat: 'WIN', statut: 'FINISHED', dansCombienDHeures: -3 });

    await expect(miser()).rejects.toMatchObject({
      motif: 'resultat_connu', statut: 409,
    });
  });
});

describe('la règle, cas par cas', () => {
  const dans = (h: number) => new Date(Date.now() + h * HEURE);
  const base = { resultat: null, statutMatch: 'SCHEDULED', dateMatch: dans(24) };

  it('laisse passer un match à venir et non réglé', () => {
    expect(refusDePari(base)).toBeNull();
  });

  it.each([
    ['WIN'], ['LOSS'], ['PUSH'],
  ])('refuse un pronostic réglé (%s), même avant le coup d\'envoi', (r) => {
    // Un pronostic réglé alors que le match n'a pas commencé signale une
    // correction manuelle : dans tous les cas l'issue n'est plus incertaine.
    expect(refusDePari({ ...base, resultat: r })).toBe('resultat_connu');
  });

  it.each([
    ['LIVE'], ['live'], ['FINISHED'], ['finished'], ['SUSPENDED'],
  ])('refuse le statut %s', (s) => {
    expect(refusDePari({ ...base, statutMatch: s })).toBe('match_commence');
  });

  it('distingue un match reporté', () => {
    // Ni commencé ni jouable : le dire autrement serait faux, et l'utilisateur
    // n'a rien à corriger.
    expect(refusDePari({ ...base, statutMatch: 'POSTPONED', dateMatch: dans(-2) }))
      .toBe('match_reporte');
  });

  it('ferme exactement à l\'heure du coup d\'envoi', () => {
    const t = new Date('2026-09-20T18:00:00Z');
    const avant = refusDePari({ ...base, dateMatch: t,
      maintenant: new Date(t.getTime() - 1) });
    const pile = refusDePari({ ...base, dateMatch: t, maintenant: t });

    expect(avant).toBeNull();
    expect(pile).toBe('match_commence');
  });

  it('sans date connue, le statut décide seul', () => {
    // Une date absente ne doit pas fermer la saisie par défaut : ce serait
    // refuser des paris légitimes sur un défaut de données.
    expect(refusDePari({ ...base, dateMatch: null })).toBeNull();
    expect(refusDePari({ ...base, dateMatch: null, statutMatch: 'LIVE' }))
      .toBe('match_commence');
  });

  it('chaque motif a un message', () => {
    for (const motif of ['resultat_connu', 'match_commence', 'match_reporte'] as const) {
      expect(MESSAGE_REFUS[motif]).toBeTruthy();
      expect(MESSAGE_REFUS[motif].length).toBeGreaterThan(20);
    }
  });
});

describe('le barème est obligatoire côté serveur', () => {
  it.each([1, 299, 301, 1000, NaN, Infinity])('refuse une mise différente du calcul : %s', async montant => {
    poser({});
    await expect(miser(montant)).rejects.toThrow();
    expect(solde()).toBe(10000);
    expect(_base.bankrollBets.size).toBe(0);
  });
  it('une note changée impose de confirmer le nouveau montant', async () => {
    poser({}); _base.pronostics.get('p1').confidenceScore = 5;
    await expect(miser(300)).rejects.toThrow('changé');
    await miser(500); expect(solde()).toBe(9500);
  });
  it('deux mises concurrentes ne réutilisent pas le même solde de calcul', async () => {
    poser({});
    _base.matches.set('m2', {..._base.matches.get('m1'), id:'m2'});
    _base.pronostics.set('p2', {..._base.pronostics.get('p1'), id:'p2', matchId:'m2'});
    const results = await Promise.allSettled([placeBet('u1','p1',300),placeBet('u1','p2',300)]);
    expect(results.filter(r => r.status === 'fulfilled')).toHaveLength(1);
    expect(solde()).toBe(9700);
  });
});

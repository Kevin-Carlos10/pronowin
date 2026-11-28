import crypto from 'crypto';

import { NotificationService } from './notification.service';
import { nomDevise } from '../utils/devise';
import { rencontre } from '../utils/noms_equipes';
import { prisma } from '../lib/prisma';
import { ErreurMetier } from '../utils/erreurs';
import { miseSuggeree } from './mise_suggeree';
import { MESSAGE_REFUS, RefusPari, refusDePari } from './verrou_pari';
import { aLUnite, mouvoir, soldeExact, type Tx, type TypeMouvement } from './bankroll_journal';
import { PlafondExposition, engageEnCours, plafondExposition, verifierPlafond } from './bankroll_exposition';
import {
  annulerSelectionsDuPronostic, notifierReglementsCombines, reglerSelectionsDuPronostic, type ReglementCombine,
} from './combines.service';
import { annulerCouverturesDuPronostic, reglerCouverturesDuPronostic } from './couvertures_enregistrees.service';
import {
  COLONNES_MISE, resultatDeMise, resultatsRegles, totaux, type MiseLue, type ResultatRegle,
} from './bankroll_historique';

const notifSvc = new NotificationService();

/**
 * La saisie est fermée pour ce pronostic.
 *
 * Une classe distincte plutôt qu'un `Error` nu : le contrôleur répond 409 —
 * l'état du match a changé, la demande n'est pas malformée — et le mobile peut
 * reconnaître `code` pour rafraîchir sa liste au lieu d'afficher un message
 * d'erreur générique.
 */
export class MiseAActualiser extends Error {
  constructor() { super('La mise calculée ou le solde a changé. Vérifiez le nouveau montant avant de confirmer.'); this.name = 'MiseAActualiser'; }
}

export class PariFerme extends Error {
  readonly statut = 409;
  constructor(readonly motif: RefusPari) {
    super(MESSAGE_REFUS[motif]);
    this.name = 'PariFerme';
  }
}

// ── Montants exacts et journal des mouvements (constat B1) ───────────────────
//
// `aLUnite`, `soldeExact` et `mouvoir` vivent dans `bankroll_journal.ts`
// (27 novembre 2026), partagés avec les combinés et les couvertures.

/** Les devises que la bankroll accepte — celles que l'application propose. */
export const DEVISES_BANKROLL = ['XOF', 'XAF', 'GNF', 'EUR'] as const;

export { aLUnite };
export type { TypeMouvement };

/**
 * Le journal d'une bankroll rend-il compte de son solde ?
 *
 * La somme des mouvements doit valoir le solde : un écart dit qu'une
 * écriture est passée hors du journal. (Pas le « dernier » `soldeApres` :
 * deux mouvements de la même milliseconde n'ont pas d'ordre sûr.)
 */
export async function verifierMouvements(bankrollId: string) {
  const [bankroll, somme, nombre] = await Promise.all([
    prisma.userBankroll.findUnique({ where: { id: bankrollId } }),
    prisma.bankrollMouvement.aggregate({ where: { bankrollId }, _sum: { montant: true } }),
    prisma.bankrollMouvement.count({ where: { bankrollId } }),
  ]);
  if (!bankroll) return null;
  const devise = bankroll.currency;
  const reconstitue = soldeExact(somme._sum.montant ?? 0, devise);
  const ecart = soldeExact(bankroll.currentBalance - reconstitue, devise);
  return {
    coherent: ecart === 0,
    solde: bankroll.currentBalance,
    reconstitue,
    ecart,
    mouvements: nombre,
  };
}

// ── Plafond d'exposition (constat B2) ────────────────────────────────────────
//
// Dans `bankroll_exposition.ts` (27 novembre 2026) : les combinés et les
// couvertures engagent aussi le solde.
export { PlafondExposition, plafondExposition };

// ── Mise suggérée ─────────────────────────────────────────────────────────────
//
// La note 1–5 fixe la part obligatoire du solde disponible.
// Le calcul est partagé par l’aperçu et la validation de la mise.
export function suggestStake(
  balance: number,
  confidenceScore: number,
  devise: string | null | undefined = 'XOF',
): number {
  return miseSuggeree(balance, confidenceScore, devise);
}

// ── GET ou CREATE bankroll ────────────────────────────────────────────────────
/**
 * Combien de paris l'historique renvoie au plus.
 *
 * La limite n'est pas le problème — charger mille paris sur un téléphone n'a
 * pas de sens. Le problème était qu'elle ne se voyait pas : l'écran calculait
 * ses compteurs, son taux de réussite et sa courbe à partir de ces cinquante
 * lignes, et les présentait comme le bilan complet. Au cinquante-et-unième
 * pari, les chiffres devenaient faux sans que rien ne l'indique.
 *
 * Le bilan vient désormais de `resumeParis`, qui compte **tout**. Cette
 * constante ne borne plus que la liste affichée, et le nombre total
 * l'accompagne dans la réponse.
 */
export const PARIS_AFFICHES_MAX = 50;

export async function getBankroll(userId: string) {
  return prisma.userBankroll.findUnique({
    where: { userId },
    include: {
      bets: {
        include: { pronostic: { include: { match: true } }, couvertureEnregistree: true },
        orderBy: { createdAt: 'desc' },
        take: PARIS_AFFICHES_MAX,
      },
    },
  });
}

/**
 * Le bilan de **tous** les paris d'une bankroll, sans limite de lecture.
 *
 * Compté par la base plutôt que reconstitué depuis la page chargée : c'est la
 * seule façon que les compteurs restent vrais quand l'historique dépasse ce
 * que l'écran montre.
 */
export async function resumeParis(bankrollId: string) {
  const parStatut = await prisma.bankrollBet.groupBy({
    by:     ['result'],
    where:  { bankrollId },
    _count: { _all: true },
    _sum:   { profit: true, stakedAmount: true },
  });

  const compte = (r: string | null) =>
    parStatut.find((g) => g.result === r)?._count._all ?? 0;
  const mise = (r: string | null) =>
    parStatut.find((g) => g.result === r)?._sum.stakedAmount ?? 0;

  const gagnes     = compte('WIN');
  const perdus     = compte('LOSS');
  const rembourses = compte('PUSH');
  const enAttente  = compte(null);
  const total      = gagnes + perdus + rembourses + enAttente;

  // Un remboursé ne départage pas : il reste hors du taux de réussite.
  const departagent = gagnes + perdus;

  // Les combinés et les couvertures enregistrées (27 novembre 2026) comptent
  // dans le résultat net et dans l'engagé — ce sont des mises sorties du
  // solde —, pas dans le taux de réussite, qui juge les sélections simples.
  const [combines, couvertures] = await Promise.all([
    prisma.bankrollCombine.groupBy({
      by: ['result'], where: { bankrollId }, _count: { _all: true }, _sum: { profit: true, stakedAmount: true },
    }),
    prisma.bankrollCouverture.groupBy({
      by: ['result'], where: { bankrollId }, _count: { _all: true }, _sum: { profit: true, mise: true },
    }),
  ]);
  const combine = (r: string | null) => combines.find((g) => g.result === r);
  const profitCombines = combines.reduce((n, g) => n + (g._sum.profit ?? 0), 0);
  const profitCouvertures = couvertures.reduce((n, g) => n + (g._sum.profit ?? 0), 0);
  const engageCombines = combine(null)?._sum.stakedAmount ?? 0;
  const engageCouvertures = couvertures.find((g) => g.result === null)?._sum.mise ?? 0;

  return {
    total,
    gagnes,
    perdus,
    rembourses,
    en_attente: enAttente,
    taux_reussite: departagent > 0
      ? Math.round((gagnes / departagent) * 100)
      : 0,
    profit_net: Math.round(
      (parStatut.reduce((n, g) => n + (g._sum.profit ?? 0), 0) + profitCombines + profitCouvertures) * 100) / 100,

    /**
     * Ce qui est engagé sur des paris non tranchés.
     *
     * Cette somme est **déjà déduite** du solde disponible : la mise part au
     * moment où le pari est posé. L'écran l'ignorait et affichait
     * `solde − budget` comme un « gain » — si bien que poser un pari se
     * lisait comme une perte, flèche rouge comprise, alors que rien n'était
     * perdu. Les trois grandeurs ne mesurent pas la même chose et doivent
     * être nommées séparément.
     */
    mises_en_cours: Math.round((mise(null) + engageCombines + engageCouvertures) * 100) / 100,

    combines: {
      total:      combines.reduce((n, g) => n + g._count._all, 0),
      gagnes:     combine('WIN')?._count._all ?? 0,
      perdus:     combine('LOSS')?._count._all ?? 0,
      rembourses: combine('PUSH')?._count._all ?? 0,
      en_attente: combine(null)?._count._all ?? 0,
      profit:     Math.round(profitCombines * 100) / 100,
    },
    couvertures: {
      total:      couvertures.reduce((n, g) => n + g._count._all, 0),
      en_attente: couvertures.find((g) => g.result === null)?._count._all ?? 0,
      profit:     Math.round(profitCouvertures * 100) / 100,
    },
  };
}

// ── SET budget (crée ou met à jour) ──────────────────────────────────────────
export async function setBudget(userId: string, totalBudget: number, currency?: string) {
  if (currency !== undefined && currency !== null
      && !(DEVISES_BANKROLL as readonly string[]).includes(String(currency).toUpperCase())) {
    throw new ErreurMetier(`Devise non prise en charge : ${String(currency)}.`, 400);
  }
  return prisma.$transaction(async (tx) => {
    const existing = await tx.userBankroll.findUnique({ where: { userId } });
    const devise = (currency ? String(currency).toUpperCase() : existing?.currency) ?? 'XOF';
    const budget = aLUnite(totalBudget, devise);
    if (!(budget > 0)) throw new ErreurMetier('Budget invalide.', 400);

    if (!existing) {
      const cree = await tx.userBankroll.create({
        data: { userId, totalBudget: budget, currentBalance: budget, currency: devise },
      });
      await tx.bankrollMouvement.create({ data: {
        bankrollId: cree.id, type: 'ouverture', montant: budget, soldeApres: budget,
        motif: 'Budget initial', creeLe: new Date(),
      } });
      return cree;
    }

    if (devise !== existing.currency) {
      // Changer la devise ré-étiquetait les montants sans les convertir :
      // 100 000 XOF devenaient 100 000 EUR. Aucun taux n'est fiable ici ; la
      // devise est donc fixée dès le premier pari. Avant, rien n'est engagé :
      // on repart simplement du nouveau budget.
      const paris = await tx.bankrollBet.count({ where: { bankrollId: existing.id } });
      if (paris > 0) {
        throw new ErreurMetier(
          'La devise est fixée par tes paris enregistrés : les montants ne se convertissent pas. ' +
          'Garde ta devise actuelle.', 409, 'CURRENCY_LOCKED');
      }
      await tx.userBankroll.update({ where: { id: existing.id }, data: { totalBudget: budget, currency: devise } });
      await mouvoir(tx, existing.id, devise, budget - existing.currentBalance, 'devise',
        { motif: `Devise ${existing.currency} → ${devise}, nouveau départ à ${budget}` });
      return tx.userBankroll.findUnique({ where: { id: existing.id } }) as any;
    }

    // Le budget est la référence de la réinitialisation ; il ne déplace pas le
    // solde disponible. Le journal le note quand même : c'est une décision de
    // l'utilisateur qui changera son prochain départ.
    const maj = await tx.userBankroll.update({ where: { id: existing.id }, data: { totalBudget: budget } });
    if (budget !== existing.totalBudget) {
      await tx.bankrollMouvement.create({ data: {
        bankrollId: existing.id, type: 'budget', montant: 0, soldeApres: existing.currentBalance,
        motif: `Budget de référence ${existing.totalBudget} → ${budget}`, creeLe: new Date(),
      } });
    }
    return maj;
  });
}

// ── RESET complet (cooldown 30 jours) ────────────────────────────────────────
export async function resetBankroll(userId: string) {
  const bankroll = await prisma.userBankroll.findUnique({ where: { userId } });
  if (!bankroll) throw new Error('Bankroll introuvable.');

  // Vérifier le cooldown de 30 jours depuis le dernier reset
  const COOLDOWN_DAYS = 30;
  if ((bankroll as any).lastResetAt) {
    const daysSinceReset = (Date.now() - new Date((bankroll as any).lastResetAt).getTime()) / 86400000;
    if (daysSinceReset < COOLDOWN_DAYS) {
      const daysLeft = Math.ceil(COOLDOWN_DAYS - daysSinceReset);
      throw new Error(`Reset disponible dans ${daysLeft} jour${daysLeft > 1 ? 's' : ''}.`);
    }
  }

  // Les paris encore en attente restent engagés.
  //
  // Le solde repartait du budget entier, mises en cours comprises. Or leur
  // montant avait déjà été déduit, et le règlement crédite ensuite le gain
  // **complet** (`_settlementCredit`) : la mise se retrouvait remboursée deux
  // fois.
  //
  // Mise de 2 000 à la cote 2 sur un budget de 10 000 : solde 8 000,
  // réinitialisation à 10 000, le pari gagne et crédite 4 000 — 14 000 au lieu
  // de 12 000. Et s'il perd, la perte disparaît au lieu de coûter 2 000. Le
  // suivi devenait faux dans les deux sens, à volonté, tous les trente jours.
  //
  // Repartir du budget **moins ce qui est encore engagé** laisse l'arithmétique
  // du règlement juste, quel que soit le moment de la remise à zéro.
  //
  // Les combinés et les couvertures enregistrées en cours aussi (27 novembre
  // 2026) : leur mise est sortie du solde, et leur règlement crédite tout.
  return prisma.$transaction(async (tx) => {
    const { total: engage } = await engageEnCours(bankroll.id, tx);
    const cible  = soldeExact(bankroll.totalBudget - engage, bankroll.currency);

    // Garde sur le solde lu : une mise posée entre-temps a déjà déplacé le
    // solde, et l'écart calculé ne vaudrait plus.
    const solde = await mouvoir(tx, bankroll.id, bankroll.currency, cible - bankroll.currentBalance,
      'reinitialisation', { siSolde: bankroll.currentBalance, motif: `Retour au budget ${bankroll.totalBudget}, moins ${engage} engagés` });
    if (solde === null) throw new MiseAActualiser();
    return tx.userBankroll.update({ where: { id: bankroll.id }, data: { lastResetAt: new Date() } });
  });
}

// ── PLACE BET ─────────────────────────────────────────────────────────────────
export async function placeBet(
  userId:      string,
  pronosticId: string,
  stakedAmount: number,
  /** La cote obtenue chez le bookmaker (couverture seulement), facultative. */
  coteBookmaker?: number,
) {
  const bankroll = await prisma.userBankroll.findUnique({ where: { userId } });
  if (!bankroll) throw new Error('Configure ton budget d\'abord.');
  if (!Number.isFinite(stakedAmount) || stakedAmount <= 0) throw new Error('La mise doit être positive.');
  if (stakedAmount > bankroll.currentBalance) throw new Error('Solde insuffisant.');

  const pronostic = await prisma.pronostic.findUnique({ where: { id: pronosticId } });
  if (!pronostic) {
    // Essai par matchId
    const byMatch = await prisma.pronostic.findUnique({ where: { principalMatchId: pronosticId } });
    if (!byMatch) throw new Error('Pronostic introuvable.');
    pronosticId = byMatch.id;
  }

  // Vérifier qu'il n'y a pas déjà un pari sur ce pronostic
  const existing = await prisma.bankrollBet.findUnique({
    where: { bankrollId_pronosticId: { bankrollId: bankroll.id, pronosticId } },
  });
  if (existing) throw new Error('Tu as déjà misé sur ce pronostic.');

  const pro = await prisma.pronostic.findUnique({
    where:   { id: pronosticId },
    include: { match: true },
  });
  if (!pro) throw new Error('Pronostic introuvable.');

  // La saisie ferme au coup d'envoi.
  //
  // Rien ne le vérifiait : on pouvait enregistrer une mise sur un pronostic
  // déjà réglé, dont le résultat est public. L'écran lui-même laissait le
  // bouton « Miser » pendant un match en direct. Un historique où l'on peut
  // ajouter après coup les paris gagnants rend le classement invérifiable.
  const refus = refusDePari({
    resultat:    pro.result,
    statutMatch: pro.match?.status,
    dateMatch:   pro.match?.matchDate,
  });
  if (refus) throw new PariFerme(refus);

  const balanceAtCalculation = bankroll.currentBalance;
  const suggestedAmount = suggestStake(
    bankroll.currentBalance, pro.confidenceScore, bankroll.currency);
  if (suggestedAmount <= 0) throw new Error('Le solde ou la confiance ne permet pas de calculer une mise valide.');
  if (Math.abs(stakedAmount - suggestedAmount) > 1e-8) throw new MiseAActualiser();
  stakedAmount = suggestedAmount; // montant canonique, sans décimales supplémentaires du client
  const oddsUsed        = pro.oddsRecommended;
  const potentialGain   = aLUnite(stakedAmount * oddsUsed, bankroll.currency);

  // Engagé : mises simples, combinés et couvertures en cours (27 novembre 2026).
  await verifierPlafond(bankroll, stakedAmount);

  // Déduction atomique : le solde doit encore être celui utilisé pour le calcul.
  // La condition sur le solde est évaluée par Postgres au moment de l'UPDATE
  // (verrou ligne), pas au moment de la lecture ci-dessus — évite qu'un pari
  // concurrent fasse passer le solde en négatif, ou dépasse le plafond.
  const bet = await prisma.$transaction(async (tx) => {
    const id = crypto.randomUUID();
    const solde = await mouvoir(tx, bankroll.id, bankroll.currency, -stakedAmount, 'mise',
      { pariId: id, siSolde: balanceAtCalculation });
    if (solde === null) throw new MiseAActualiser();

    return tx.bankrollBet.create({
      data: {
        id,
        bankrollId:      bankroll.id,
        pronosticId,
        stakedAmount,
        suggestedAmount,
        oddsUsed,
        potentialGain,
        coteBookmaker: coteBookmaker !== undefined && Number.isFinite(coteBookmaker) && coteBookmaker > 1
          ? coteBookmaker : null,
      },
    });
  });

  return bet;
}

// ── Mise réelle (constat M1) ──────────────────────────────────────────────────

/** Combien de jours après le résultat l'application pose la question. */
export const JOURS_POUR_CONFIRMER = 14;

/**
 * La question n'est posée que pour les paris réglés depuis sa mise en
 * service : l'afficher d'un coup sur les dizaines de paris des deux semaines
 * passées serait une corvée, pour des mises dont on se souvient moins. Ces
 * paris restent confirmables ; on ne les réclame simplement pas.
 */
export const CONFIRMATION_DEPUIS = new Date('2026-09-24T17:00:00Z');

/** L'application doit-elle demander la mise réelle de ce pari ? */
export function miseAConfirmer(
  pari: { result: string | null; miseConfirmeeLe: Date | null; settledAt: Date | null },
  maintenant = new Date(),
): boolean {
  if (pari.result == null || pari.miseConfirmeeLe != null || pari.settledAt == null) return false;
  const depuis = Math.max(maintenant.getTime() - JOURS_POUR_CONFIRMER * 86400000, CONFIRMATION_DEPUIS.getTime());
  return pari.settledAt.getTime() >= depuis;
}

/**
 * Le parieur confirme la mise placée chez son bookmaker — ou la corrige.
 *
 * La mise calculée restait la seule connue : les 140 paris enregistrés
 * portaient exactement la mise conseillée, et le solde pouvait être faux sans
 * que rien ne le montre. On ne rend pas la mise libre — elle reste calculée et
 * verrouillée à la pose ; on demande, au résultat, si c'est bien elle. Une
 * seule fois : une réponse n'est pas modifiable ensuite.
 *
 * Corriger rejoue le pari avec la mise réelle : la différence de mise, et la
 * différence de ce que le règlement rend. Le pari reste compté au classement,
 * qui ne porte que sur les résultats — une mise déclarée nulle n'efface pas
 * une défaite.
 */
export async function confirmerMise(userId: string, pariId: string, miseReelle?: unknown) {
  return prisma.$transaction(async (tx) => {
    const pari = await tx.bankrollBet.findUnique({ where: { id: pariId }, include: { bankroll: true } });
    if (!pari || pari.bankroll.userId !== userId) throw new ErreurMetier('Pari introuvable.', 404);
    if (pari.result == null) {
      throw new ErreurMetier('La mise se confirme au résultat du pari.', 409, 'BET_PENDING');
    }
    if (pari.miseConfirmeeLe) {
      throw new ErreurMetier('Cette mise est déjà confirmée.', 409, 'STAKE_ALREADY_CONFIRMED');
    }

    const devise = pari.bankroll.currency;
    let mise = pari.stakedAmount;
    if (miseReelle !== undefined && miseReelle !== null && miseReelle !== '') {
      const n = typeof miseReelle === 'number' ? miseReelle : Number(miseReelle);
      if (!Number.isFinite(n) || n < 0 || n > 1e12) throw new ErreurMetier('Mise invalide.', 400);
      mise = aLUnite(n, devise);
    }

    const resultat = pari.result as BankrollBetResult;
    const avant = { stakedAmount: pari.stakedAmount, potentialGain: pari.potentialGain };
    const apres = { stakedAmount: mise, potentialGain: aLUnite(mise * pari.oddsUsed, devise) };
    const corrigee = mise !== pari.stakedAmount;

    // La mise part à la pose, le règlement rend ce qui revient : corriger la
    // mise, c'est rejouer les deux.
    const delta = corrigee
      ? soldeExact((avant.stakedAmount - apres.stakedAmount)
          + (_settlementCredit(resultat, apres) - _settlementCredit(resultat, avant)), devise)
      : 0;
    if (delta < 0 && -delta > pari.bankroll.currentBalance + 1e-9) {
      throw new ErreurMetier(
        'Cette mise dépasse ce que ta bankroll contenait : le solde deviendrait négatif.', 409, 'INSUFFICIENT_BALANCE');
    }

    // Conditionnel : deux réponses simultanées ne comptent qu'une fois.
    const maj = await tx.bankrollBet.updateMany({
      where: { id: pariId, miseConfirmeeLe: null },
      data:  {
        miseConfirmeeLe: new Date(),
        ...(corrigee ? {
          stakedAmount:  apres.stakedAmount,
          potentialGain: apres.potentialGain,
          profit:        _settlementProfit(resultat, apres) || 0,
        } : {}),
      },
    });
    if (maj.count === 0) {
      throw new ErreurMetier('Cette mise est déjà confirmée.', 409, 'STAKE_ALREADY_CONFIRMED');
    }

    let solde = pari.bankroll.currentBalance;
    if (delta !== 0) {
      solde = (await mouvoir(tx, pari.bankrollId, devise, delta, 'correction_mise', {
        pariId, motif: `Mise réelle ${mise} au lieu de ${pari.stakedAmount}`,
      }))!;
    }
    return { pari_id: pariId, mise: apres.stakedAmount, corrigee, current_balance: solde };
  });
}

export type BankrollBetResult = 'WIN' | 'LOSS' | 'PUSH';
type SettlementResult = BankrollBetResult | null;
type SettlementAmounts = { stakedAmount: number; potentialGain: number };

/** Amount that must be returned to the available bankroll for a settled bet. */
export function _settlementCredit(result: SettlementResult, bet: SettlementAmounts): number {
  if (result === 'WIN') return bet.potentialGain;
  if (result === 'PUSH') return bet.stakedAmount;
  return 0;
}

/** Net result displayed in the bankroll history. */
export function _settlementProfit(result: SettlementResult, bet: SettlementAmounts): number | null {
  if (result === null) return null;
  if (result === 'WIN') return parseFloat((bet.potentialGain - bet.stakedAmount).toFixed(2));
  if (result === 'PUSH') return 0;
  return -bet.stakedAmount;
}

/**
 * The stake is deducted when it is placed. A settlement therefore only moves
 * the amount returned to the available bankroll. This also makes a manual
 * correction (LOSS -> WIN, for example) safe to replay.
 */
export function _settlementBalanceDelta(
  previousResult: SettlementResult,
  nextResult: SettlementResult,
  bet: SettlementAmounts,
): number {
  return parseFloat((_settlementCredit(nextResult, bet) - _settlementCredit(previousResult, bet)).toFixed(2));
}

// ── SETTLE OR CORRECT BETS ───────────────────────────────────────────────────
// Called after a score sync or an admin override. Existing settled bets are
// reconciled too, so correcting an erroneous verdict fixes both the history
// and the bankroll balance.
export async function settleBets(pronosticId: string, result: SettlementResult) {
  let reglementsCombines: ReglementCombine[] = [];
  const couverturesParPari = new Map<string, number | null>();
  const changedBets = await prisma.$transaction(async (tx) => {
    const bets = await tx.bankrollBet.findMany({
      where:   { pronosticId },
      include: {
        bankroll: { include: { user: { select: { id: true } } } },
      },
    });

    const now = new Date();
    const changes: Array<{
      betId: string;
      previousResult: SettlementResult;
      userId: string;
      currency: string;
      profit: number | null;
      stakedAmount: number;
      potentialGain: number;
    }> = [];

    for (const bet of bets) {
      const previousResult = bet.result as SettlementResult;
      if (previousResult === result) continue;

      const profit = _settlementProfit(result, bet);
      // The conditional update protects the balance from a duplicate concurrent
      // sync: only the call that changes the stored verdict may move the money.
      const updated = await tx.bankrollBet.updateMany({
        where: { id: bet.id, result: previousResult },
        data:  { result, profit, settledAt: result === null ? null : now },
      });
      if (updated.count === 0) continue;

      const balanceDelta = _settlementBalanceDelta(previousResult, result, bet);
      if (balanceDelta !== 0) {
        await mouvoir(tx, bet.bankrollId, bet.bankroll.currency ?? 'XOF', balanceDelta, 'reglement', {
          pariId: bet.id,
          motif:  previousResult === null ? `Résultat ${result}` : `Correction ${previousResult} → ${result ?? 'en attente'}`,
        });
      }

      changes.push({
        betId:         bet.id,
        previousResult,
        userId:        bet.bankroll.user.id,
        currency:      bet.bankroll.currency ?? 'XOF',
        profit,
        stakedAmount:  bet.stakedAmount,
        potentialGain: bet.potentialGain,
      });
    }

    // Les combinés qui contiennent ce pronostic, et les couvertures de son
    // inverse (27 novembre 2026) : même transaction, le solde reste juste.
    reglementsCombines = await reglerSelectionsDuPronostic(tx, pronosticId, result);
    for (const h of await reglerCouverturesDuPronostic(tx, pronosticId, result)) {
      if (h.pariId) couverturesParPari.set(h.pariId, h.profit);
    }

    return changes;
  });

  notifierReglementsCombines(reglementsCombines);

  if (changedBets.length === 0 || result === null) return changedBets.length;

  // Notifications are intentionally sent after the transaction. A notification
  // failure must never leave a corrected balance half-written.
  const pronostic = await prisma.pronostic.findUnique({
    where:   { id: pronosticId },
    include: { match: true },
  });
  const matchStr = pronostic?.match
    ? rencontre(pronostic.match.homeTeam, pronostic.match.awayTeam)
    : 'votre pronostic';

  for (const bet of changedBets) {
    const corrected = bet.previousResult !== null;
    if (couverturesParPari.has(bet.betId)) {
      // La mise et sa couverture : le résultat qui compte est leur somme.
      const net = (bet.profit ?? 0) + (couverturesParPari.get(bet.betId) ?? 0);
      const d = nomDevise(bet.currency);
      const signe = net > 0 ? '+' : net < 0 ? '-' : '';
      const valeur = Math.abs(net).toLocaleString('fr-FR');
      const valeurEn = Math.abs(net).toLocaleString('en-GB');
      const passee = result === 'WIN';
      notifSvc.sendToUser(bet.userId, {
        title: result === 'PUSH' ? 'Mise couverte : remboursée' : `Mise couverte : ${signe}${valeur} ${d} au total`,
        titleEn: result === 'PUSH' ? 'Hedged bet: refunded' : `Hedged bet: ${signe}${valeurEn} ${d} in total`,
        body: result === 'PUSH'
          ? `${matchStr} : ta mise et ta couverture sont remboursées.`
          : `${matchStr} : ta sélection est ${passee ? 'passée' : 'perdue'}, ta couverture ${passee ? 'perdue' : 'passée'}. Résultat net : ${signe}${valeur} ${d}.`,
        bodyEn: result === 'PUSH'
          ? `${matchStr}: your bet and your hedge are refunded.`
          : `${matchStr}: your selection ${passee ? 'won' : 'lost'}, your hedge ${passee ? 'lost' : 'won'}. Net result: ${signe}${valeurEn} ${d}.`,
        data:  { deep_link: `/pronostics/${pronosticId}`, type: 'match' },
      }).catch(() => {});
      continue;
    }
    if (result === 'WIN') {
      const gain = (bet.profit ?? 0).toLocaleString('fr-FR');
      const retour = bet.potentialGain.toLocaleString('fr-FR');
      notifSvc.sendToUser(bet.userId, {
        title: corrected ? 'Résultat corrigé : gagnant' : 'Pronostic gagnant !',
        body:  corrected
          ? `${matchStr} : retour de ${retour} ${nomDevise(bet.currency)} crédité, gain net +${gain} ${nomDevise(bet.currency)}.`
          : `+${gain} ${nomDevise(bet.currency)} sur ${matchStr}. Votre bankroll est mise à jour !`,
        data:  { deep_link: `/pronostics/${pronosticId}`, type: 'match' },
      }).catch(() => {});
    } else if (result === 'PUSH') {
      const remb = bet.stakedAmount.toLocaleString('fr-FR');
      notifSvc.sendToUser(bet.userId, {
        title: corrected ? 'Résultat corrigé : remboursé' : 'Pronostic remboursé',
        body:  corrected
          ? `${matchStr} : la mise de ${remb} ${nomDevise(bet.currency)} a été remboursée après correction.`
          : `${remb} ${nomDevise(bet.currency)} de mise remboursée sur ${matchStr}.`,
        data:  { deep_link: `/pronostics/${pronosticId}`, type: 'match' },
      }).catch(() => {});
    } else {
      const perte = bet.stakedAmount.toLocaleString('fr-FR');
      notifSvc.sendToUser(bet.userId, {
        title: corrected ? 'Résultat corrigé : perdu' : 'Pronostic perdant',
        body:  corrected
          ? `${matchStr} : le résultat a été corrigé. Mise de ${perte} ${nomDevise(bet.currency)} perdue.`
          : `-${perte} ${nomDevise(bet.currency)} sur ${matchStr}. Ne lâchez pas !`,
        data:  { deep_link: `/pronostics/${pronosticId}`, type: 'match' },
      }).catch(() => {});
    }
  }

  return changedBets.length;
}

// ── Sélection modifiée avant le coup d'envoi ─────────────────────────────────

export interface PariAnnule { userId: string; montant: number; devise: string }

/**
 * L'analyste a changé la sélection d'un pronostic publié avant le coup
 * d'envoi (12 octobre 2026) : une entrée de bankroll ne garde que la cote,
 * elle serait réglée sur une sélection que l'abonné n'a pas jouée. Ces
 * entrées sont annulées et la mise rendue, dans la transaction de l'appelant ;
 * l'abonné peut valider la nouvelle sélection.
 */
export async function annulerParisSelectionModifiee(tx: Tx, pronosticId: string): Promise<PariAnnule[]> {
  // Les couvertures de ce pronostic d'abord (leur mise est rendue), avant que
  // la suppression de la mise ne les emporte ; puis ses sélections dans des
  // combinés, qui deviennent remboursées (27 novembre 2026). Pas de
  // notification ici : on est dans la transaction de l'appelant.
  await annulerCouverturesDuPronostic(tx, pronosticId);
  await annulerSelectionsDuPronostic(tx, pronosticId);
  const paris = await tx.bankrollBet.findMany({
    where:   { pronosticId, result: null },
    include: { bankroll: { select: { userId: true, currency: true } } },
  });
  const annules: PariAnnule[] = [];
  for (const pari of paris) {
    const devise = pari.bankroll.currency ?? 'XOF';
    await mouvoir(tx, pari.bankrollId, devise, pari.stakedAmount, 'annulation', {
      pariId: pari.id, motif: 'Sélection modifiée par l’analyste : mise rendue',
    });
    await tx.bankrollBet.delete({ where: { id: pari.id } });
    annules.push({ userId: pari.bankroll.userId, montant: pari.stakedAmount, devise });
  }
  return annules;
}

/** À appeler après la transaction : une notification n'annule rien. */
export function notifierSelectionModifiee(
  annules: PariAnnule[], pronosticId: string, match: { homeTeam: string; awayTeam: string },
) {
  const matchStr = rencontre(match.homeTeam, match.awayTeam);
  for (const a of annules) {
    notifSvc.sendToUser(a.userId, {
      title: 'Sélection modifiée',
      body:  `L’analyste a changé sa sélection sur ${matchStr}. Votre mise de `
           + `${a.montant.toLocaleString('fr-FR')} ${nomDevise(a.devise)} vous a été rendue : `
           + 'vous pouvez valider la nouvelle sélection.',
      data:  { deep_link: `/pronostics/${pronosticId}`, type: 'match' },
    }).catch(() => {});
  }
}

/**
 * Le pronostic a été retiré avant le coup d'envoi (23 novembre 2026) : la
 * mise est rendue. À appeler après la transaction.
 */
export function notifierPronosticRetire(
  annules: PariAnnule[], match: { id: string; homeTeam: string; awayTeam: string },
) {
  const matchStr = rencontre(match.homeTeam, match.awayTeam);
  for (const a of annules) {
    notifSvc.sendToUser(a.userId, {
      title: 'Pronostic retiré',
      body:  `L’analyste a retiré un pronostic sur ${matchStr} avant le coup d’envoi. Votre mise de `
           + `${a.montant.toLocaleString('fr-FR')} ${nomDevise(a.devise)} vous a été rendue.`,
      data:  { deep_link: `/pronostics/${match.id}`, type: 'match' },
    }).catch(() => {});
  }
}

// ── ADMIN — Liste de toutes les bankrolls ─────────────────────────────────────
// Vue d'ensemble pour l'admin : un utilisateur n'apparaît que s'il a configuré
// un budget (sinon rien à montrer). Les stats (taux de réussite, ROI) sont
// recalculées ici plutôt que dénormalisées, cohérent avec getBankrollStats().
export async function listBankrolls(params: {
  page:     number;
  perPage:  number;
  search?:  string; // pseudo, téléphone ou email
  sortBy?:  'currentBalance' | 'totalBudget' | 'createdAt' | 'pseudo';
  sortDir?: 'asc' | 'desc';
}) {
  const { page, perPage, search, sortBy = 'currentBalance', sortDir = 'desc' } = params;

  const where: any = {};
  if (search) {
    where.user = {
      OR: [
        { pseudo:      { contains: search, mode: 'insensitive' } },
        { phoneNumber: { contains: search } },
        { email:       { contains: search, mode: 'insensitive' } },
      ],
    };
  }

  // `sortBy` vient de la query string : sans liste blanche, une valeur inconnue
  // fait lever Prisma (500) et n'importe quel champ du modèle devient un
  // critère d'ordre. Même correctif que sur la liste des utilisateurs.
  const SORTABLE = new Set(['currentBalance', 'totalBudget', 'createdAt', 'pseudo']);
  const col = SORTABLE.has(sortBy) ? sortBy : 'currentBalance';
  const dir = sortDir === 'asc' ? 'asc' : 'desc';

  // Le tri par pseudo porte sur la relation user — reste séparé du tri sur
  // les colonnes propres à UserBankroll pour garder un orderBy Prisma valide.
  const orderBy: any = col === 'pseudo'
    ? { user: { pseudo: dir } }
    : { [col]: dir };

  const [bankrolls, total] = await Promise.all([
    prisma.userBankroll.findMany({
      where, orderBy, skip: (page - 1) * perPage, take: perPage,
      include: {
        user: { select: { id: true, pseudo: true, phoneNumber: true, email: true, avatarUrl: true } },
        // Les combinés et les couvertures aussi (28 novembre 2026) : le profit
        // et le rendement d'un portefeuille les comptent, comme dans l'app.
        bets:     { select: COLONNES_MISE },
        combines: { select: COLONNES_MISE },
      },
    }),
    prisma.userBankroll.count({ where }),
  ]);

  const data = bankrolls.map(b => {
    const settled  = b.bets.filter(bet => bet.result !== null);
    const decisive = settled.filter(bet => bet.result !== 'PUSH');
    const wins     = decisive.filter(bet => bet.result === 'WIN').length;
    const regles = reglesDe(b.bets, b.combines);
    const { profit: totalProfit, mise: totalStaked } = totaux(regles);

    return {
      user_id:         b.userId,
      pseudo:          b.user.pseudo,
      phone_number:    b.user.phoneNumber,
      email:            b.user.email,
      avatar_url:       b.user.avatarUrl,
      total_budget:     b.totalBudget,
      current_balance:  b.currentBalance,
      currency:         b.currency,
      total_bets:       b.bets.length,
      pending_bets:     b.bets.length - settled.length,
      wins,
      losses:           decisive.length - wins,
      win_rate:         decisive.length > 0 ? parseFloat(((wins / decisive.length) * 100).toFixed(1)) : null,
      total_profit:     parseFloat(totalProfit.toFixed(2)),
      roi:              totalStaked > 0 ? parseFloat(((totalProfit / totalStaked) * 100).toFixed(1)) : null,
      combines:            b.combines.length,
      combines_en_attente: b.combines.filter(c => c.result === null).length,
      couvertures:         [...b.bets, ...b.combines].filter(m => m.couvertureEnregistree != null).length,
      last_reset_at:    b.lastResetAt,
      created_at:       b.createdAt,
    };
  });

  return { data, total, page, per_page: perPage, total_pages: Math.ceil(total / perPage) };
}

/**
 * ADMIN — Agrégats sur l'ensemble des bankrolls.
 *
 * La page listait les comptes un par un sans jamais dire si la fonctionnalité
 * marche : combien de budget est confié, combien de paris attendent leur
 * règlement, et surtout si l'ensemble des utilisateurs gagne ou perd. Ces
 * quatre chiffres se lisent en une seconde et remplacent une lecture ligne à
 * ligne.
 */
export async function listBankrollsStats() {
  const [bankrolls, paris, combinesTous] = await Promise.all([
    prisma.userBankroll.findMany({ select: { id: true, currency: true, totalBudget: true, currentBalance: true } }),
    prisma.bankrollBet.findMany({ select: { bankrollId: true, ...COLONNES_MISE } }),
    prisma.bankrollCombine.findMany({ select: { bankrollId: true, ...COLONNES_MISE } }),
  ]);

  // Le taux de réussite juge les sélections simples, comme dans l'app.
  const settled  = paris.filter(b => b.result !== null);
  const decisive = settled.filter(b => b.result !== 'PUSH');   // PUSH = mise rendue
  const wins     = decisive.filter(b => b.result === 'WIN').length;

  // Par devise (28 novembre 2026) : les totaux additionnaient des francs CFA
  // et des euros, et la page ne pouvait leur donner aucune unité.
  const deviseDe = new Map(bankrolls.map(b => [b.id, b.currency]));
  const parDevise = new Map<string, {
    devise: string; bankrolls: number; budget: number; solde: number; regles: ResultatRegle[];
  }>();
  const groupe = (devise: string) => {
    let g = parDevise.get(devise);
    if (!g) parDevise.set(devise, g = { devise, bankrolls: 0, budget: 0, solde: 0, regles: [] });
    return g;
  };
  for (const b of bankrolls) {
    const g = groupe(b.currency);
    g.bankrolls++;
    g.budget += b.totalBudget;
    g.solde  += b.currentBalance;
  }
  const toutes: ResultatRegle[] = [];
  const ranger = (genre: ResultatRegle['genre'], m: MiseLue & { bankrollId: string }) => {
    const r = resultatDeMise(genre, m);
    if (!r) return;
    toutes.push(r);
    groupe(deviseDe.get(m.bankrollId) ?? 'XOF').regles.push(r);
  };
  for (const m of paris) ranger('pari', m);
  for (const m of combinesTous) ranger('combine', m);

  const rendement = (t: { profit: number; mise: number }) =>
    t.mise > 0 ? +((t.profit / t.mise) * 100).toFixed(1) : null;
  const devises = [...parDevise.values()]
    .map(g => {
      const t = totaux(g.regles);
      return {
        devise:        g.devise,
        bankrolls:     g.bankrolls,
        total_budget:  soldeExact(g.budget, g.devise),
        total_balance: soldeExact(g.solde, g.devise),
        total_profit:  soldeExact(t.profit, g.devise),
        roi:           rendement(t),
      };
    })
    .sort((a, b) => b.bankrolls - a.bankrolls);

  const global = totaux(toutes);
  const couvertes = [...paris, ...combinesTous].map(m => m.couvertureEnregistree).filter(c => c != null);
  return {
    bankrolls:     bankrolls.length,
    // Toutes devises confondues : gardés pour les versions du panneau qui les
    // lisent encore. La page affiche `devises`.
    total_budget:  Math.round(bankrolls.reduce((n, b) => n + b.totalBudget, 0)),
    total_balance: Math.round(bankrolls.reduce((n, b) => n + b.currentBalance, 0)),
    total_bets:    paris.length,
    pending_bets:  paris.length - settled.length,
    wins, losses:  decisive.length - wins,
    // Sur zéro pari réglé, un « 0 % » se lirait comme un mauvais résultat
    // alors qu'il n'y a simplement rien à mesurer : on renvoie null.
    win_rate:      decisive.length > 0 ? +((wins / decisive.length) * 100).toFixed(1) : null,
    total_profit:  Math.round(global.profit),
    roi:           rendement(global),
    devises,
    combines: {
      total:      combinesTous.length,
      en_attente: combinesTous.filter(c => c.result === null).length,
      gagnes:     combinesTous.filter(c => c.result === 'WIN').length,
      perdus:     combinesTous.filter(c => c.result === 'LOSS').length,
    },
    couvertures: {
      total:      couvertes.length,
      en_attente: couvertes.filter(c => c!.result === null).length,
    },
  };
}

/** Les mises réglées d'un portefeuille, simples et combinées. */
function reglesDe(paris: MiseLue[], combinesListe: MiseLue[]): ResultatRegle[] {
  const liste: ResultatRegle[] = [];
  for (const m of paris) { const r = resultatDeMise('pari', m); if (r) liste.push(r); }
  for (const m of combinesListe) { const r = resultatDeMise('combine', m); if (r) liste.push(r); }
  return liste;
}

// ── STATS ─────────────────────────────────────────────────────────────────────
export async function getBankrollStats(userId: string) {
  const bankroll = await prisma.userBankroll.findUnique({ where: { userId } });
  if (!bankroll) return null;

  // Le gain net et la base du rendement comptent aussi les combinés et les
  // couvertures enregistrées (27 novembre 2026) : ce sont des mises sorties
  // du solde. Le taux de réussite, lui, juge les sélections simples.
  const regles  = await resultatsRegles(bankroll.id);
  const settled = regles.filter(r => r.genre === 'pari');
  // Les remboursés (PUSH) ne sont ni des victoires ni des défaites — on les
  // exclut du taux de réussite et de la base de calcul du ROI (la mise a été
  // rendue, elle n'a jamais été réellement "à risque").
  const decisive = settled.filter(b => b.result !== 'PUSH');
  const wins     = decisive.filter(b => b.result === 'WIN').length;
  const losses   = decisive.filter(b => b.result === 'LOSS').length;
  const pushes   = settled.length - decisive.length;
  const { profit: totalProfit, mise: totalStaked } = totaux(regles);
  const roi = totalStaked > 0 ? (totalProfit / totalStaked) * 100 : 0;

  return {
    totalBudget:    bankroll.totalBudget,
    currentBalance: bankroll.currentBalance,
    currency:       bankroll.currency,
    totalBets:      settled.length,
    combines:       regles.length - settled.length,
    wins,
    losses,
    pushes,
    winRate:        decisive.length > 0 ? (wins / decisive.length) * 100 : 0,
    totalProfit:    parseFloat(totalProfit.toFixed(2)),
    totalStaked:    parseFloat(totalStaked.toFixed(2)),
    roi:            parseFloat(roi.toFixed(2)),
  };
}

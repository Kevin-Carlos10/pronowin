import crypto from 'crypto';
import { Prisma } from '@prisma/client';

import { NotificationService } from './notification.service';
import { nomDevise } from '../utils/devise';
import { prisma } from '../lib/prisma';
import { ErreurMetier } from '../utils/erreurs';
import { lireConfig } from './app_config.service';
import { miseSuggeree, pasDeDevise } from './mise_suggeree';
import { MESSAGE_REFUS, RefusPari, refusDePari } from './verrou_pari';

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

/** Les devises que la bankroll accepte — celles que l'application propose. */
export const DEVISES_BANKROLL = ['XOF', 'XAF', 'GNF', 'EUR'] as const;

/**
 * Un montant ramené à l'unité de la devise, par défaut.
 *
 * Le franc CFA n'a pas de centimes. Un gain potentiel de 1 234 × 1,73 était
 * gardé à 2 134,82 FCFA — une somme qu'aucun bookmaker ne verse —, et ces
 * centimes fictifs, additionnés en virgule flottante, rendaient le solde
 * inexact. En unités entières, un nombre à virgule flottante est exact : les
 * additions répétées du solde ne dérivent plus.
 */
export function aLUnite(montant: number, devise: string | null | undefined): number {
  const facteur = 1 / pasDeDevise(devise);
  return Math.floor(montant * facteur + 1e-9) / facteur;
}

/** Le solde à la précision de la devise : au centime près pour l'euro. */
function soldeExact(solde: number, devise: string | null | undefined): number {
  const facteur = 1 / pasDeDevise(devise);
  return Math.round(solde * facteur) / facteur;
}

type Tx = Prisma.TransactionClient;
export type TypeMouvement =
  'ouverture' | 'budget' | 'devise' | 'mise' | 'reglement' | 'correction_mise' | 'reinitialisation';

/**
 * Déplace le solde disponible et l'inscrit au journal, dans la transaction de
 * l'appelant. C'est le seul chemin qui modifie `currentBalance` : la somme
 * des mouvements d'une bankroll vaut ainsi son solde.
 *
 * `siSolde` : ne bouge que si le solde vaut encore ce montant — la garde de
 * placeBet contre deux mises simultanées. Renvoie le solde après le
 * mouvement, ou `null` si la garde a refusé.
 */
async function mouvoir(
  tx: Tx, bankrollId: string, devise: string, montant: number, type: TypeMouvement,
  opts: { pariId?: string; motif?: string; siSolde?: number } = {},
): Promise<number | null> {
  const where: Prisma.UserBankrollWhereInput = { id: bankrollId };
  if (opts.siSolde !== undefined) where.currentBalance = opts.siSolde;
  const r = await tx.userBankroll.updateMany({ where, data: { currentBalance: { increment: montant } } });
  if (r.count === 0) return null;

  // La ligne est verrouillée par l'UPDATE jusqu'à la fin de la transaction :
  // ce qu'on relit est notre écriture, pas celle d'un autre.
  const lu = await tx.userBankroll.findUnique({ where: { id: bankrollId } });
  let solde = lu!.currentBalance;
  const exact = soldeExact(solde, devise);
  if (exact !== solde) {
    await tx.userBankroll.update({ where: { id: bankrollId }, data: { currentBalance: exact } });
    solde = exact;
  }
  await tx.bankrollMouvement.create({ data: {
    bankrollId, type, montant, soldeApres: solde, pariId: opts.pariId ?? null, motif: opts.motif ?? null,
    creeLe: new Date(),
  } });
  return solde;
}

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

/**
 * La part de la bankroll que les mises en cours peuvent engager ensemble, ou
 * `null` : pas de plafond.
 *
 * Chaque mise respecte le barème, mais rien ne limitait leur somme : cinq
 * pronostics notés 5 le même soir engageaient 25 % du solde. Le seuil est une
 * décision produit, réglée dans le panneau (BANKROLL_PLAFOND_EXPOSITION) ;
 * vide, il n'y a pas de plafond.
 */
export async function plafondExposition(): Promise<number | null> {
  const { valeurs } = await lireConfig();
  const brut = (valeurs as Record<string, string>).BANKROLL_PLAFOND_EXPOSITION ?? '';
  const pct = Number(brut);
  return brut.trim() !== '' && Number.isFinite(pct) && pct > 0 && pct <= 100 ? pct / 100 : null;
}

export class PlafondExposition extends ErreurMetier {
  constructor(plafond: number, engage: number, capital: number, devise: string) {
    const fmt = (n: number) => `${Math.round(n).toLocaleString('fr-FR')} ${nomDevise(devise)}`;
    super(
      `Tes paris en cours engagent déjà ${fmt(engage)} sur ${fmt(capital)}. ` +
      `Le plafond est de ${Math.round(plafond * 100)} % de ta bankroll : ` +
      'attends le résultat d\'un pari en cours avant d\'en ajouter un.',
      409, 'EXPOSURE_CAP');
    this.name = 'PlafondExposition';
  }
}

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
        include: { pronostic: { include: { match: true } } },
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
      parStatut.reduce((n, g) => n + (g._sum.profit ?? 0), 0) * 100) / 100,

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
    mises_en_cours: Math.round(mise(null) * 100) / 100,
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
  return prisma.$transaction(async (tx) => {
    const { _sum } = await tx.bankrollBet.aggregate({
      where: { bankrollId: bankroll.id, result: null },
      _sum:  { stakedAmount: true },
    });
    const engage = _sum.stakedAmount ?? 0;
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
) {
  const bankroll = await prisma.userBankroll.findUnique({ where: { userId } });
  if (!bankroll) throw new Error('Configure ton budget d\'abord.');
  if (!Number.isFinite(stakedAmount) || stakedAmount <= 0) throw new Error('La mise doit être positive.');
  if (stakedAmount > bankroll.currentBalance) throw new Error('Solde insuffisant.');

  const pronostic = await prisma.pronostic.findUnique({ where: { id: pronosticId } });
  if (!pronostic) {
    // Essai par matchId
    const byMatch = await prisma.pronostic.findUnique({ where: { matchId: pronosticId } });
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

  const plafond = await plafondExposition();
  if (plafond !== null) {
    const { _sum } = await prisma.bankrollBet.aggregate({
      where: { bankrollId: bankroll.id, result: null },
      _sum:  { stakedAmount: true },
    });
    const engage  = _sum.stakedAmount ?? 0;
    // Rapporté à tout ce que la bankroll contient : le disponible plus ce qui
    // est déjà engagé. Rapporté au seul disponible, le plafond se resserrerait
    // à chaque mise.
    const capital = bankroll.currentBalance + engage;
    if (engage + stakedAmount > plafond * capital + 1e-9) {
      throw new PlafondExposition(plafond, engage, capital, bankroll.currency);
    }
  }

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
  const changedBets = await prisma.$transaction(async (tx) => {
    const bets = await tx.bankrollBet.findMany({
      where:   { pronosticId },
      include: {
        bankroll: { include: { user: { select: { id: true } } } },
      },
    });

    const now = new Date();
    const changes: Array<{
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
        previousResult,
        userId:        bet.bankroll.user.id,
        currency:      bet.bankroll.currency ?? 'XOF',
        profit,
        stakedAmount:  bet.stakedAmount,
        potentialGain: bet.potentialGain,
      });
    }

    return changes;
  });

  if (changedBets.length === 0 || result === null) return changedBets.length;

  // Notifications are intentionally sent after the transaction. A notification
  // failure must never leave a corrected balance half-written.
  const pronostic = await prisma.pronostic.findUnique({
    where:   { id: pronosticId },
    include: { match: true },
  });
  const matchStr = pronostic?.match
    ? `${pronostic.match.homeTeam} vs ${pronostic.match.awayTeam}`
    : 'votre pronostic';

  for (const bet of changedBets) {
    const corrected = bet.previousResult !== null;
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
        bets: { select: { result: true, profit: true, stakedAmount: true } },
      },
    }),
    prisma.userBankroll.count({ where }),
  ]);

  const data = bankrolls.map(b => {
    const settled  = b.bets.filter(bet => bet.result !== null);
    const decisive = settled.filter(bet => bet.result !== 'PUSH');
    const wins     = decisive.filter(bet => bet.result === 'WIN').length;
    const totalProfit = settled.reduce((sum, bet) => sum + (bet.profit ?? 0), 0);
    const totalStaked = decisive.reduce((sum, bet) => sum + bet.stakedAmount, 0);

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
  const [agg, bets] = await Promise.all([
    prisma.userBankroll.aggregate({
      _count: { _all: true },
      _sum:   { totalBudget: true, currentBalance: true },
    }),
    prisma.bankrollBet.findMany({ select: { result: true, profit: true, stakedAmount: true } }),
  ]);

  const settled  = bets.filter(b => b.result !== null);
  const decisive = settled.filter(b => b.result !== 'PUSH');   // PUSH = mise rendue
  const wins     = decisive.filter(b => b.result === 'WIN').length;
  const profit   = settled.reduce((s, b) => s + (b.profit ?? 0), 0);
  const staked   = decisive.reduce((s, b) => s + b.stakedAmount, 0);

  return {
    bankrolls:     agg._count._all,
    total_budget:  Math.round(agg._sum.totalBudget    ?? 0),
    total_balance: Math.round(agg._sum.currentBalance ?? 0),
    total_bets:    bets.length,
    pending_bets:  bets.length - settled.length,
    wins, losses:  decisive.length - wins,
    // Sur zéro pari réglé, un « 0 % » se lirait comme un mauvais résultat
    // alors qu'il n'y a simplement rien à mesurer : on renvoie null.
    win_rate:      decisive.length > 0 ? +((wins / decisive.length) * 100).toFixed(1) : null,
    total_profit:  Math.round(profit),
    roi:           staked > 0 ? +((profit / staked) * 100).toFixed(1) : null,
  };
}

// ── STATS ─────────────────────────────────────────────────────────────────────
export async function getBankrollStats(userId: string) {
  const bankroll = await prisma.userBankroll.findUnique({
    where:   { userId },
    include: { bets: { where: { result: { not: null } } } },
  });
  if (!bankroll) return null;

  const settled = bankroll.bets;
  // Les remboursés (PUSH) ne sont ni des victoires ni des défaites — on les
  // exclut du taux de réussite et de la base de calcul du ROI (la mise a été
  // rendue, elle n'a jamais été réellement "à risque").
  const decisive = settled.filter(b => b.result !== 'PUSH');
  const wins     = decisive.filter(b => b.result === 'WIN').length;
  const losses   = decisive.filter(b => b.result === 'LOSS').length;
  const pushes   = settled.length - decisive.length;
  const totalProfit = settled.reduce((sum, b) => sum + (b.profit ?? 0), 0);
  const totalStaked = decisive.reduce((sum, b) => sum + b.stakedAmount, 0);
  const roi = totalStaked > 0 ? (totalProfit / totalStaked) * 100 : 0;

  return {
    totalBudget:    bankroll.totalBudget,
    currentBalance: bankroll.currentBalance,
    currency:       bankroll.currency,
    totalBets:      settled.length,
    wins,
    losses,
    pushes,
    winRate:        decisive.length > 0 ? (wins / decisive.length) * 100 : 0,
    totalProfit:    parseFloat(totalProfit.toFixed(2)),
    totalStaked:    parseFloat(totalStaked.toFixed(2)),
    roi:            parseFloat(roi.toFixed(2)),
  };
}

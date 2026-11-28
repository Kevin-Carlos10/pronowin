/**
 * « J'ai couvert » (27 novembre 2026) : la mise sur l'inverse entre dans la
 * bankroll.
 *
 * Sans elle, la bankroll ne connaissait que la mise d'origine : si elle
 * perdait, le bilan affichait une perte alors que l'abonné avait gagné grâce
 * à sa couverture. La couverture enregistrée sort sa mise du solde, et se
 * règle d'elle-même avec la sélection couverte : elle gagne quand la sélection
 * perd, et elles sont remboursées ensemble (ligne entière, match nul sur un
 * « remboursé si match nul »).
 *
 * Une couverture par mise simple, une par combiné (sa dernière sélection
 * ouverte). Une fois enregistrée, plus d'alerte pour cette mise.
 */
import crypto from 'crypto';

import { prisma } from '../lib/prisma';
import { ErreurMetier } from '../utils/erreurs';
import { aLUnite, mouvoir, soldeExact, type Tx } from './bankroll_journal';
import { derniereSelectionOuverte } from './combines.service';
import {
  STRATEGIES, libelleSelection, resultatInverse, selectionDuPronostic, selectionInverse, type Strategie,
} from './couverture';

type Resultat = 'WIN' | 'LOSS' | 'PUSH';

/** Ce que le règlement rend au solde. */
export function creditCouverture(r: Resultat | null, h: { mise: number; cote: number }, devise: string | null | undefined): number {
  if (r === 'WIN') return aLUnite(h.mise * h.cote, devise);
  if (r === 'PUSH') return h.mise;
  return 0;
}

export function profitCouverture(r: Resultat | null, h: { mise: number; cote: number }, devise: string | null | undefined): number | null {
  if (r === null) return null;
  return Math.round((creditCouverture(r, h, devise) - h.mise) * 100) / 100;
}

const STATUTS_COUVRABLES = new Set(['LIVE', 'SCHEDULED']);

/** POST /bankroll/couvertures */
export async function enregistrerCouverture(userId: string, entree: {
  pari_id?: unknown; combine_id?: unknown; mise?: unknown; cote?: unknown; strategie?: unknown;
}) {
  const pariId = typeof entree.pari_id === 'string' && entree.pari_id ? entree.pari_id : null;
  const combineId = typeof entree.combine_id === 'string' && entree.combine_id ? entree.combine_id : null;
  if (!pariId === !combineId) throw new ErreurMetier('Indique la mise ou le combiné à couvrir.', 400, 'HEDGE_TARGET');
  const strategie = typeof entree.strategie === 'string' && ([...STRATEGIES, 'libre'] as string[]).includes(entree.strategie)
    ? entree.strategie as Strategie | 'libre' : 'libre';
  const cote = Number(entree.cote);
  if (!Number.isFinite(cote) || cote < 1.01 || cote > 1000) throw new ErreurMetier('Cote invalide : entre 1,01 et 1 000.', 400, 'HEDGE_ODDS');

  const bankroll = await prisma.userBankroll.findUnique({ where: { userId } });
  if (!bankroll) throw new ErreurMetier('Configure ton budget d\'abord.', 409, 'NO_BANKROLL');
  const mise = aLUnite(Number(entree.mise), bankroll.currency);
  if (!Number.isFinite(mise) || mise <= 0) throw new ErreurMetier('La mise doit être positive.', 400, 'HEDGE_STAKE');
  if (mise > bankroll.currentBalance) throw new ErreurMetier('Solde insuffisant.', 409, 'INSUFFICIENT_BALANCE');

  // La sélection couverte : celle de la mise, ou la dernière ouverte du combiné.
  let pronosticId: string;
  if (pariId) {
    const pari = await prisma.bankrollBet.findUnique({ where: { id: pariId }, include: { couvertureEnregistree: true } });
    if (!pari || pari.bankrollId !== bankroll.id) throw new ErreurMetier('Mise introuvable.', 404, 'BET_NOT_FOUND');
    if (pari.result != null) throw new ErreurMetier('Cette mise est déjà réglée.', 409, 'BET_SETTLED');
    if (pari.couvertureEnregistree) throw new ErreurMetier('Cette mise est déjà couverte.', 409, 'HEDGE_EXISTS');
    pronosticId = pari.pronosticId;
  } else {
    const c = await prisma.bankrollCombine.findUnique({
      where: { id: combineId! }, include: { selections: true, couvertureEnregistree: true },
    });
    if (!c || c.bankrollId !== bankroll.id) throw new ErreurMetier('Combiné introuvable.', 404, 'COMBINE_NOT_FOUND');
    if (c.result != null) throw new ErreurMetier('Ce combiné est déjà réglé.', 409, 'BET_SETTLED');
    if (c.couvertureEnregistree) throw new ErreurMetier('Ce combiné est déjà couvert.', 409, 'HEDGE_EXISTS');
    const derniere = derniereSelectionOuverte(c.selections);
    if (!derniere) {
      throw new ErreurMetier('Un combiné se couvre quand il ne reste qu’une sélection PronoWin à jouer.', 409, 'HEDGE_NOT_READY');
    }
    pronosticId = derniere.pronosticId!;
  }

  const pro = await prisma.pronostic.findUnique({ where: { id: pronosticId }, include: { match: true } });
  if (!pro || !pro.match) throw new ErreurMetier('Pronostic introuvable.', 404, 'PRONOSTIC_NOT_FOUND');
  const selection = selectionDuPronostic(pro);
  if (!selection) throw new ErreurMetier('Ce marché n’a pas d’inverse exact : il ne se couvre pas.', 409, 'HEDGE_MARKET');
  if (!STATUTS_COUVRABLES.has(pro.match.status) || pro.result != null) {
    throw new ErreurMetier('Le match est terminé : il n’y a plus rien à couvrir.', 409, 'HEDGE_CLOSED');
  }
  const inverse = selectionInverse(selection);

  return prisma.$transaction(async (tx) => {
    const id = crypto.randomUUID();
    const solde = await mouvoir(tx, bankroll.id, bankroll.currency, -mise, 'couverture',
      { pariId: id, siSolde: bankroll.currentBalance, motif: `Couverture : ${libelleSelection(inverse, pro.match.homeTeam, pro.match.awayTeam, 'fr')}` });
    if (solde === null) throw new ErreurMetier('Le solde a changé : réessaie.', 409, 'STAKE_CHANGED');
    const h = await tx.bankrollCouverture.create({ data: {
      id, bankrollId: bankroll.id, pariId, combineId, pronosticId,
      selectionFr: libelleSelection(inverse, pro.match.homeTeam, pro.match.awayTeam, 'fr'),
      selectionEn: libelleSelection(inverse, pro.match.homeTeam, pro.match.awayTeam, 'en'),
      strategie, mise, cote, result: null,
    } });
    return { ...h, current_balance: solde };
  });
}

/** Le résultat d'un pronostic, reporté sur les couvertures de son inverse. */
export async function reglerCouverturesDuPronostic(tx: Tx, pronosticId: string, result: Resultat | null) {
  const couvertures = await tx.bankrollCouverture.findMany({ where: { pronosticId }, include: { bankroll: true } });
  const reglees: { id: string; pariId: string | null; combineId: string | null; result: Resultat | null; profit: number | null }[] = [];
  for (const h of couvertures) {
    const devise = h.bankroll.currency ?? 'XOF';
    const avant = (h.result ?? null) as Resultat | null;
    const apres = resultatInverse(result);
    if (avant === apres) continue;
    const profit = profitCouverture(apres, h, devise);
    const maj = await tx.bankrollCouverture.updateMany({
      where: { id: h.id, result: h.result ?? null },
      data: { result: apres, profit, settledAt: apres === null ? null : new Date() },
    });
    if (maj.count === 0) continue;
    const delta = soldeExact(creditCouverture(apres, h, devise) - creditCouverture(avant, h, devise), devise);
    if (delta !== 0) {
      await mouvoir(tx, h.bankrollId, devise, delta, 'reglement', {
        pariId: h.id, motif: avant === null ? `Couverture ${apres}` : `Couverture corrigée ${avant} → ${apres ?? 'en attente'}`,
      });
    }
    reglees.push({ id: h.id, pariId: h.pariId, combineId: h.combineId, result: apres, profit });
  }
  return reglees;
}

/**
 * Le pronostic couvert a été retiré, ou sa sélection modifiée, avant le coup
 * d'envoi : la mise et le combiné qu'il portait sont annulés ou ajustés, la
 * couverture l'est aussi. Sa mise est rendue.
 */
export async function annulerCouverturesDuPronostic(tx: Tx, pronosticId: string) {
  const couvertures = await tx.bankrollCouverture.findMany({ where: { pronosticId, result: null }, include: { bankroll: true } });
  for (const h of couvertures) {
    await mouvoir(tx, h.bankrollId, h.bankroll.currency ?? 'XOF', h.mise, 'annulation', {
      pariId: h.id, motif: 'Pronostic couvert retiré ou modifié : mise de couverture rendue',
    });
    await tx.bankrollCouverture.delete({ where: { id: h.id } });
  }
  return couvertures.length;
}

/** Au format de l'application. */
export function couverturePourApi(h: {
  id: string; selectionFr: string; selectionEn: string; strategie: string; mise: number; cote: number;
  result: string | null; profit: number | null; createdAt: Date;
} | null | undefined) {
  if (!h) return null;
  return {
    id: h.id, selection_fr: h.selectionFr, selection_en: h.selectionEn, strategie: h.strategie,
    mise: h.mise, cote: h.cote, result: h.result, profit: h.profit, created_at: h.createdAt,
  };
}

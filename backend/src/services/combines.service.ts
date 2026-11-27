/**
 * Les coupons combinés de la bankroll (27 novembre 2026).
 *
 * Décisions de l'utilisateur (27 novembre 2026) :
 * - de 2 à 10 sélections ;
 * - des pronostics PronoWin publiés, ouverts (avant leur coup d'envoi), et des
 *   sélections libres que l'abonné écrit lui-même et règle à la main ;
 * - la mise suit le barème de la sélection la moins sûre ; une sélection
 *   libre n'a pas de note et compte pour la note 1 (1,5 % du solde). Comme une
 *   mise simple, elle est calculée et verrouillée : l'abonné ne la choisit pas.
 *
 * Le combiné passe si toutes ses sélections passent. Une sélection remboursée
 * (ou annulée parce que le pronostic a été retiré ou modifié avant le coup
 * d'envoi) compte pour une cote de 1, comme chez les bookmakers. Une seule
 * sélection perdue suffit : le combiné est réglé perdu sans attendre les
 * autres.
 *
 * Deux sélections du même match ne se combinent pas : leurs issues sont liées,
 * et le gain affiché serait faux.
 *
 * Le classement des abonnés ne compte pas les combinés : il juge des
 * pronostics, pas des coupons.
 */
import crypto from 'crypto';

import { prisma } from '../lib/prisma';
import { ErreurMetier } from '../utils/erreurs';
import { nomDevise } from '../utils/devise';
import { rencontre } from '../utils/noms_equipes';
import { NotificationService } from './notification.service';
import { miseSuggeree } from './mise_suggeree';
import { MESSAGE_REFUS, refusDePari } from './verrou_pari';
import { estVerrouille } from './verrou_pronostic';
import { aLUnite, mouvoir, soldeExact, type Tx } from './bankroll_journal';
import { verifierPlafond } from './bankroll_exposition';

export const COMBINE_MIN = 2;
export const COMBINE_MAX = 10;
/** Une sélection libre n'a pas de note : elle compte pour la moins sûre. */
export const NOTE_SELECTION_LIBRE = 1;
export const COTE_MIN = 1.01;
export const COTE_MAX = 1000;

export type Resultat = 'WIN' | 'LOSS' | 'PUSH';

export type EntreeSelection =
  | { pronostic_id: string }
  | { libre: { match: string; selection: string; cote: number } };

export class CombineAActualiser extends ErreurMetier {
  constructor() {
    super('La mise calculée ou le solde a changé. Vérifie le nouveau montant avant de valider.', 409, 'STAKE_CHANGED');
    this.name = 'CombineAActualiser';
  }
}

// ─── Le calcul, sans base ────────────────────────────────────────────────────

/** Le produit des cotes, à trois décimales. */
export function coteTotale(cotes: number[]): number {
  return Math.round(cotes.reduce((p, c) => p * c, 1) * 1000) / 1000;
}

interface LigneEtat { cote: number; result: string | null; annulee?: boolean }

/**
 * Le résultat d'un combiné d'après ses sélections, et ce que son règlement
 * rend au solde. Nul tant qu'une sélection est en attente et qu'aucune n'a
 * perdu.
 */
export function etatCombine(
  mise: number, selections: LigneEtat[], devise: string | null | undefined,
): { result: Resultat | null; retour: number | null } {
  const effectif = (l: LigneEtat) => (l.annulee ? 'PUSH' : l.result);
  if (selections.some(l => effectif(l) === 'LOSS')) return { result: 'LOSS', retour: 0 };
  if (selections.some(l => effectif(l) == null)) return { result: null, retour: null };
  const gagnees = selections.filter(l => effectif(l) === 'WIN');
  if (gagnees.length === 0) return { result: 'PUSH', retour: mise };
  return { result: 'WIN', retour: aLUnite(mise * gagnees.reduce((p, l) => p * l.cote, 1), devise) };
}

/** Le gain net d'un combiné réglé. */
export function profitCombine(mise: number, result: Resultat | null, retour: number | null): number | null {
  if (result === null) return null;
  return Math.round(((retour ?? 0) - mise) * 100) / 100;
}

/**
 * La seule sélection encore ouverte d'un combiné dont toutes les autres sont
 * passées (gagnées ou remboursées) — celle qu'on peut couvrir. Nulle sinon,
 * ou si c'est une sélection libre (aucune cote à lire).
 */
export function derniereSelectionOuverte<T extends LigneEtat & { pronosticId: string | null }>(selections: T[]): T | null {
  const effectif = (l: LigneEtat) => (l.annulee ? 'PUSH' : l.result);
  if (selections.some(l => effectif(l) === 'LOSS')) return null;
  const ouvertes = selections.filter(l => effectif(l) == null);
  return ouvertes.length === 1 && ouvertes[0].pronosticId ? ouvertes[0] : null;
}

/**
 * La cote qui reste à jouer sur la dernière sélection : celle des sélections
 * gagnées multipliée par la sienne (les remboursées comptent pour 1).
 */
export function coteRestante(selections: LigneEtat[], derniere: LigneEtat): number {
  const gagnees = selections.filter(l => !l.annulee && l.result === 'WIN');
  return gagnees.reduce((p, l) => p * l.cote, 1) * derniere.cote;
}

// ─── Les sélections demandées ────────────────────────────────────────────────

interface SelectionResolue {
  pronosticId: string | null;
  libreMatch: string | null;
  libreSelection: string | null;
  cote: number;
  note: number;
}

const texte = (v: unknown) => (typeof v === 'string' ? v.trim() : '');

/** Vérifie et complète les sélections d'un combiné. */
async function resoudre(userId: string, entrees: unknown, maintenant: Date): Promise<SelectionResolue[]> {
  if (!Array.isArray(entrees) || entrees.length < COMBINE_MIN || entrees.length > COMBINE_MAX) {
    throw new ErreurMetier(`Un combiné compte de ${COMBINE_MIN} à ${COMBINE_MAX} sélections.`, 400, 'COMBINE_SIZE');
  }
  const user = await prisma.user.findUnique({ where: { id: userId } });
  const premium = user?.subscriptionPlan === 'premium'
    && (!user.subscriptionExpiresAt || user.subscriptionExpiresAt > maintenant);

  const vusPronostics = new Set<string>();
  const vusMatchs = new Set<string>();
  const lignes: SelectionResolue[] = [];
  for (const e of entrees as any[]) {
    if (e && typeof e.pronostic_id === 'string' && e.pronostic_id) {
      // L'application désigne le pronostic principal d'un match par l'identifiant
      // du match, comme pour une mise simple.
      const p = await prisma.pronostic.findUnique({ where: { id: e.pronostic_id }, include: { match: true } })
        ?? await prisma.pronostic.findUnique({ where: { principalMatchId: e.pronostic_id }, include: { match: true } });
      if (!p || !p.isPublished) throw new ErreurMetier('Pronostic introuvable.', 404, 'PRONOSTIC_NOT_FOUND');
      const duel = p.match ? rencontre(p.match.homeTeam, p.match.awayTeam) : 'ce match';
      if (estVerrouille(p.isPremium, premium)) {
        throw new ErreurMetier(`Le pronostic sur ${duel} est réservé aux abonnés Premium.`, 403, 'PREMIUM_REQUIRED');
      }
      const refus = refusDePari({ resultat: p.result, statutMatch: p.match?.status, dateMatch: p.match?.matchDate, maintenant });
      if (refus) throw new ErreurMetier(`${duel} : ${MESSAGE_REFUS[refus]}`, 409, 'BET_CLOSED');
      if (vusPronostics.has(p.id)) throw new ErreurMetier('Une sélection apparaît deux fois.', 400, 'COMBINE_DUPLICATE');
      if (vusMatchs.has(p.matchId)) {
        throw new ErreurMetier(`Deux sélections de ${duel} ne se combinent pas : leurs issues sont liées.`, 400, 'COMBINE_SAME_MATCH');
      }
      vusPronostics.add(p.id);
      vusMatchs.add(p.matchId);
      lignes.push({ pronosticId: p.id, libreMatch: null, libreSelection: null, cote: p.oddsRecommended, note: p.confidenceScore });
      continue;
    }
    const libre = e?.libre;
    const match = texte(libre?.match);
    const selection = texte(libre?.selection);
    const cote = typeof libre?.cote === 'number' ? libre.cote : Number(libre?.cote);
    if (match.length < 2 || match.length > 80) throw new ErreurMetier('Indique le match de la sélection libre (2 à 80 caractères).', 400, 'COMBINE_FREE_MATCH');
    if (selection.length < 2 || selection.length > 80) throw new ErreurMetier('Indique la sélection libre (2 à 80 caractères).', 400, 'COMBINE_FREE_SELECTION');
    if (!Number.isFinite(cote) || cote < COTE_MIN || cote > COTE_MAX) {
      throw new ErreurMetier('Cote invalide : entre 1,01 et 1 000.', 400, 'COMBINE_FREE_ODDS');
    }
    lignes.push({ pronosticId: null, libreMatch: match, libreSelection: selection, cote: Math.round(cote * 1000) / 1000, note: NOTE_SELECTION_LIBRE });
  }
  return lignes;
}

/** La mise du barème pour ces sélections : celle de la note la plus faible. */
function miseDu(solde: number, lignes: SelectionResolue[], devise: string) {
  const note = Math.min(...lignes.map(l => l.note));
  return { note, mise: miseSuggeree(solde, note, devise) };
}

/** POST /bankroll/combines/apercu — la mise, la cote et le gain, sans rien enregistrer. */
export async function apercuCombine(userId: string, entrees: unknown, maintenant = new Date()) {
  const bankroll = await prisma.userBankroll.findUnique({ where: { userId } });
  if (!bankroll) throw new ErreurMetier('Configure ton budget d\'abord.', 409, 'NO_BANKROLL');
  const lignes = await resoudre(userId, entrees, maintenant);
  const { note, mise } = miseDu(bankroll.currentBalance, lignes, bankroll.currency);
  const cote = coteTotale(lignes.map(l => l.cote));
  return {
    mise,
    note_retenue: note,
    cote_totale: cote,
    gain_potentiel: aLUnite(mise * lignes.reduce((p, l) => p * l.cote, 1), bankroll.currency),
    devise: bankroll.currency,
    solde: bankroll.currentBalance,
  };
}

/** POST /bankroll/combines — enregistre le combiné et sort sa mise du solde. */
export async function placerCombine(userId: string, entrees: unknown, stakedAmount: number, maintenant = new Date()) {
  const bankroll = await prisma.userBankroll.findUnique({ where: { userId } });
  if (!bankroll) throw new ErreurMetier('Configure ton budget d\'abord.', 409, 'NO_BANKROLL');
  const lignes = await resoudre(userId, entrees, maintenant);
  const { note, mise } = miseDu(bankroll.currentBalance, lignes, bankroll.currency);
  if (mise <= 0) throw new ErreurMetier('Le solde ne permet pas de calculer une mise valide.', 409, 'STAKE_INVALID');
  if (!Number.isFinite(stakedAmount) || Math.abs(stakedAmount - mise) > 1e-8) throw new CombineAActualiser();
  await verifierPlafond(bankroll, mise);

  const produit = lignes.reduce((p, l) => p * l.cote, 1);
  return prisma.$transaction(async (tx) => {
    const id = crypto.randomUUID();
    const solde = await mouvoir(tx, bankroll.id, bankroll.currency, -mise, 'combine',
      { pariId: id, siSolde: bankroll.currentBalance, motif: `Combiné de ${lignes.length} sélections` });
    if (solde === null) throw new CombineAActualiser();
    const combine = await tx.bankrollCombine.create({ data: {
      id, bankrollId: bankroll.id, stakedAmount: mise, suggestedAmount: mise,
      oddsUsed: coteTotale(lignes.map(l => l.cote)),
      potentialGain: aLUnite(mise * produit, bankroll.currency), noteRetenue: note, result: null,
    } });
    for (const [ordre, l] of lignes.entries()) {
      await tx.bankrollCombineSelection.create({ data: { combineId: id, ordre, ...l, result: null, annulee: false } });
    }
    return { ...combine, current_balance: solde };
  });
}

// ─── Le règlement ────────────────────────────────────────────────────────────

export interface ReglementCombine {
  combineId: string; userId: string; devise: string;
  avant: Resultat | null; apres: Resultat | null; profit: number | null;
}

/**
 * Remet le combiné d'accord avec ses sélections, et le solde avec lui. Rejouable :
 * une correction (LOSS → WIN d'une sélection) déplace seulement la différence.
 */
export async function recalculerCombine(tx: Tx, combineId: string): Promise<ReglementCombine | null> {
  const c = await tx.bankrollCombine.findUnique({
    where: { id: combineId }, include: { selections: true, bankroll: true },
  });
  if (!c) return null;
  const devise = c.bankroll.currency ?? 'XOF';
  const etat = etatCombine(c.stakedAmount, c.selections, devise);
  const avant = (c.result ?? null) as Resultat | null;
  if (etat.result === avant && (etat.retour ?? null) === (c.retour ?? null)) return null;

  const profit = profitCombine(c.stakedAmount, etat.result, etat.retour);
  // Conditionnel : deux règlements simultanés ne déplacent l'argent qu'une fois.
  const maj = await tx.bankrollCombine.updateMany({
    where: { id: combineId, result: c.result ?? null, retour: c.retour ?? null },
    data: { result: etat.result, retour: etat.retour, profit, settledAt: etat.result === null ? null : new Date() },
  });
  if (maj.count === 0) return null;

  const delta = soldeExact((etat.retour ?? 0) - (c.retour ?? 0), devise);
  if (delta !== 0) {
    await mouvoir(tx, c.bankrollId, devise, delta, 'reglement', {
      pariId: combineId,
      motif: avant === null ? `Combiné ${etat.result}` : `Combiné corrigé ${avant} → ${etat.result ?? 'en attente'}`,
    });
  }
  return { combineId, userId: c.bankroll.userId, devise, avant, apres: etat.result, profit };
}

/** Le résultat d'un pronostic, reporté sur les combinés qui le contiennent. */
export async function reglerSelectionsDuPronostic(tx: Tx, pronosticId: string, result: Resultat | null) {
  const lignes = await tx.bankrollCombineSelection.findMany({ where: { pronosticId, annulee: false } });
  const combines = new Set<string>();
  for (const l of lignes) {
    if ((l.result ?? null) === result) continue;
    await tx.bankrollCombineSelection.update({
      where: { id: l.id }, data: { result, settledAt: result === null ? null : new Date() },
    });
    combines.add(l.combineId);
  }
  const reglements: ReglementCombine[] = [];
  for (const id of combines) {
    const r = await recalculerCombine(tx, id);
    if (r) reglements.push(r);
  }
  return reglements;
}

/**
 * Le pronostic a été retiré, ou sa sélection modifiée, avant le coup d'envoi :
 * ses sélections dans des combinés deviennent remboursées (cote 1). Le combiné
 * continue avec les autres.
 */
export async function annulerSelectionsDuPronostic(tx: Tx, pronosticId: string) {
  const lignes = await tx.bankrollCombineSelection.findMany({ where: { pronosticId, annulee: false, result: null } });
  const combines = new Set<string>();
  for (const l of lignes) {
    await tx.bankrollCombineSelection.update({ where: { id: l.id }, data: { annulee: true, settledAt: new Date() } });
    combines.add(l.combineId);
  }
  const reglements: ReglementCombine[] = [];
  for (const id of combines) {
    const r = await recalculerCombine(tx, id);
    if (r) reglements.push(r);
  }
  return reglements;
}

/**
 * POST /bankroll/combines/:id/selections/:selectionId/resultat — l'abonné
 * règle une sélection libre (ou annule son réglage : `null`).
 */
export async function reglerSelectionLibre(userId: string, combineId: string, selectionId: string, result: unknown) {
  if (!(result === null || result === 'WIN' || result === 'LOSS' || result === 'PUSH')) {
    throw new ErreurMetier('Résultat invalide.', 400, 'RESULT_INVALID');
  }
  const r = await prisma.$transaction(async (tx) => {
    const c = await tx.bankrollCombine.findUnique({ where: { id: combineId }, include: { bankroll: true } });
    if (!c || c.bankroll.userId !== userId) throw new ErreurMetier('Combiné introuvable.', 404, 'COMBINE_NOT_FOUND');
    const l = await tx.bankrollCombineSelection.findUnique({ where: { id: selectionId } });
    if (!l || l.combineId !== combineId) throw new ErreurMetier('Sélection introuvable.', 404, 'SELECTION_NOT_FOUND');
    if (l.pronosticId || !l.libreMatch) {
      throw new ErreurMetier('Cette sélection est un pronostic PronoWin : elle se règle toute seule.', 409, 'SELECTION_NOT_FREE');
    }
    await tx.bankrollCombineSelection.update({
      where: { id: selectionId }, data: { result: result as Resultat | null, settledAt: result === null ? null : new Date() },
    });
    return recalculerCombine(tx, combineId);
  });
  if (r) notifierReglementsCombines([r]);
  return { result: r?.apres ?? null };
}

const notifSvc = new NotificationService();

/** Après la transaction : une notification n'annule rien. */
export function notifierReglementsCombines(reglements: ReglementCombine[]) {
  for (const r of reglements) {
    if (r.apres === null) continue;
    const d = nomDevise(r.devise);
    const montant = Math.abs(r.profit ?? 0).toLocaleString('fr-FR');
    const montantEn = Math.abs(r.profit ?? 0).toLocaleString('en-GB');
    const corrige = r.avant !== null;
    const textes = r.apres === 'WIN'
      ? { t: corrige ? 'Combiné corrigé : gagnant' : 'Combiné gagnant !', b: `+${montant} ${d} : toutes tes sélections sont passées.`,
          te: corrige ? 'Accumulator corrected: won' : 'Accumulator won!', be: `+${montantEn} ${d}: all your selections came in.` }
      : r.apres === 'PUSH'
      ? { t: 'Combiné remboursé', b: 'Toutes tes sélections ont été remboursées : ta mise t’est rendue.',
          te: 'Accumulator refunded', be: 'All your selections were refunded: your stake is returned.' }
      : { t: corrige ? 'Combiné corrigé : perdu' : 'Combiné perdu', b: `-${montant} ${d} : une sélection n’est pas passée.`,
          te: corrige ? 'Accumulator corrected: lost' : 'Accumulator lost', be: `-${montantEn} ${d}: one selection did not come in.` };
    notifSvc.sendToUser(r.userId, {
      title: textes.t, titleEn: textes.te, body: textes.b, bodyEn: textes.be,
      data: { type: 'match', deep_link: `/bankroll/combine/${r.combineId}` },
    }).catch(() => {});
  }
}

// ─── La lecture ──────────────────────────────────────────────────────────────

/** Les combinés d'une bankroll, du plus récent au plus ancien. */
export function lireCombines(bankrollId: string, take = 50) {
  return prisma.bankrollCombine.findMany({
    where: { bankrollId },
    orderBy: { createdAt: 'desc' },
    take,
    include: {
      selections: { orderBy: { ordre: 'asc' }, include: { pronostic: { include: { match: true } } } },
      couvertureEnregistree: true,
    },
  });
}

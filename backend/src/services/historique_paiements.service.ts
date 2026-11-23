import { prisma } from '../lib/prisma';
import { formuleDe, type Formule } from './renouvellement.service';

/**
 * L'historique des paiements d'un compte (23 novembre 2026), pour l'écran
 * « Historique des paiements » et ses reçus.
 *
 * Payer par Mobile Money laisse l'abonné sans trace de son côté : pas de
 * relevé de boutique, pas de reçu. D'où des messages « j'ai payé, où est mon
 * Premium ? » quand une validation tarde. Trois sources, sans doublon :
 *
 * - les abonnements accordés (ce qui a été payé, ou offert, et pour quand) ;
 * - les paiements GeniusPay qui n'ont pas abouti, ou pas encore : un
 *   paiement réussi est déjà son abonnement, dont il donne la référence ;
 * - les preuves de transfert en attente ou refusées : une preuve validée est
 *   déjà son abonnement.
 */
export type StatutPaiement =
  | 'paye' | 'offert' | 'en_cours' | 'en_verification' | 'refuse' | 'echoue' | 'a_verifier' | 'rembourse';

export interface LignePaiement {
  id: string;
  date: string;
  statut: StatutPaiement;
  formule: Formule | null;
  /** En FCFA ; `null` quand on l'ignore (achat de boutique). */
  montant: number | null;
  /** geniuspay | manual_mobcash | iap_apple | iap_google | manual_admin | promo | autre */
  moyen: string;
  /** L'opérateur choisi chez GeniusPay (orange_money, moov_money…). */
  operateur: string | null;
  reference: string | null;
  debut: string | null;
  fin: string | null;
  /** Le motif d'un refus, tel que l'équipe l'a écrit. */
  motif: string | null;
}

const MAX = 50;
/** Un paiement GeniusPay échoué ne reste à l'écran qu'un mois. */
const ECHECS_JOURS = 30;
/** L'abonnement d'un paiement GeniusPay est créé dans la même transaction. */
const TOLERANCE_MS = 5 * 60_000;

function moyenDe(paymentMethod: string): string {
  if (paymentMethod === 'geniuspay' || paymentMethod === 'manual_mobcash'
      || paymentMethod === 'iap_apple' || paymentMethod === 'iap_google'
      || paymentMethod === 'manual_admin') return paymentMethod;
  if (paymentMethod.startsWith('promo_') || paymentMethod === 'xbet_promo') return 'promo';
  return 'autre';
}

function statutGeniusPay(statut: string): StatutPaiement {
  switch (statut) {
    case 'pending': case 'processing': return 'en_cours';
    case 'anomalie':                   return 'a_verifier';
    case 'refunded':                   return 'rembourse';
    default:                           return 'echoue';
  }
}

const formuleDePlan = (plan: string | null | undefined): Formule | null =>
  plan === 'premium_annual' || plan === 'premium_monthly' ? plan : null;

export async function historiquePaiements(userId: string, maintenant: Date = new Date()): Promise<LignePaiement[]> {
  const [abonnements, paiements, preuves] = await Promise.all([
    prisma.subscription.findMany({
      where:   { userId, plan: 'premium' },
      orderBy: { createdAt: 'desc' },
      take:    MAX,
      select:  { id: true, createdAt: true, startDate: true, endDate: true, amountPaid: true, paymentMethod: true },
    }),
    prisma.paiementGeniusPay.findMany({
      where:   { userId },
      orderBy: { creeLe: 'desc' },
      take:    MAX,
      select:  { id: true, plan: true, montant: true, reference: true, statut: true, moyen: true,
                 creeLe: true, premiumAccordeLe: true, environnement: true },
    }),
    prisma.subscriptionProof.findMany({
      where:   { userId, type: 'payment_screenshot', status: { in: ['pending', 'rejected'] } },
      orderBy: { createdAt: 'desc' },
      take:    20,
      select:  { id: true, createdAt: true, planId: true, amount: true, status: true, adminNote: true },
    }),
  ]);

  // Un paiement de test (sandbox) n'a rien à faire dans l'historique d'un
  // compte : il n'a rien coûté.
  const reels = paiements.filter(p => p.environnement !== 'sandbox');
  const utilises = new Set<string>();
  const lignes: LignePaiement[] = [];

  for (const a of abonnements) {
    const moyen = moyenDe(a.paymentMethod);
    // Le paiement GeniusPay qui a ouvert cet abonnement : sa référence et
    // son opérateur.
    const gp = moyen === 'geniuspay'
      ? reels.find(p => !utilises.has(p.id) && p.premiumAccordeLe
          && Math.abs(p.premiumAccordeLe.getTime() - a.createdAt.getTime()) <= TOLERANCE_MS)
      : undefined;
    if (gp) utilises.add(gp.id);
    lignes.push({
      id: a.id,
      date: a.createdAt.toISOString(),
      statut: moyen === 'manual_admin' || moyen === 'promo' ? 'offert' : 'paye',
      formule: formuleDe(a.startDate, a.endDate),
      montant: moyen === 'iap_apple' || moyen === 'iap_google' ? null : Math.round(a.amountPaid ?? 0),
      moyen,
      operateur: gp?.moyen ?? null,
      reference: gp?.reference ?? null,
      debut: a.startDate.toISOString(),
      fin: a.endDate.toISOString(),
      motif: null,
    });
  }

  const limiteEchecs = maintenant.getTime() - ECHECS_JOURS * 86_400_000;
  for (const p of reels) {
    if (utilises.has(p.id) || p.premiumAccordeLe) continue;
    const statut = statutGeniusPay(p.statut);
    if (statut === 'echoue' && p.creeLe.getTime() < limiteEchecs) continue;
    lignes.push({
      id: p.id, date: p.creeLe.toISOString(), statut,
      formule: formuleDePlan(p.plan), montant: p.montant,
      moyen: 'geniuspay', operateur: p.moyen ?? null, reference: p.reference ?? null,
      debut: null, fin: null, motif: null,
    });
  }

  for (const preuve of preuves) {
    lignes.push({
      id: preuve.id, date: preuve.createdAt.toISOString(),
      statut: preuve.status === 'pending' ? 'en_verification' : 'refuse',
      formule: formuleDePlan(preuve.planId),
      montant: preuve.amount == null ? null : Math.round(preuve.amount),
      moyen: 'manual_mobcash', operateur: null, reference: null,
      debut: null, fin: null,
      motif: preuve.status === 'rejected' ? (preuve.adminNote ?? null) : null,
    });
  }

  return lignes.sort((x, y) => y.date.localeCompare(x.date)).slice(0, MAX);
}

import { prisma } from '../lib/prisma';
import { PLANS_GENIUSPAY, rapprocherPaiement } from './geniuspay.service';

/**
 * Les paiements Mobile Money automatiques (GeniusPay), vus depuis le panneau
 * (18 octobre 2026).
 *
 * Ils existent depuis le 13 octobre, en réel, et aucun écran ne les montrait :
 * deux paiements restaient « en cours » chez l'opérateur depuis ce jour-là
 * sans que rien ne le signale. Le rapprochement automatique ne relit que les
 * paiements de moins de 26 heures (le lien de paiement expire en 24) : passé
 * ce délai, un paiement resté « en cours » n'était plus jamais relu.
 *
 * ── Ce que dit chaque état ─────────────────────────────────────────────────
 *
 *   accorde     payé, Premium accordé
 *   en_cours    le client a validé chez l'opérateur, GeniusPay n'a pas conclu
 *   en_attente  page de paiement ouverte, rien de validé (moins de 26 h)
 *   abandonne   page ouverte, jamais payée, lien expiré
 *   echoue      refusé, annulé, expiré ou remboursé chez GeniusPay
 *   anomalie    encaissé, mais pas ce qui était demandé (montant, référence,
 *               environnement) — ou payé sans que le Premium ait suivi
 *
 * « En cours » depuis plus d'une heure, ou en anomalie : c'est là que de
 * l'argent peut avoir été prélevé sans contrepartie. Ces paiements sont
 * « bloqués » et remontent en tête.
 */

export type EtatPaiementMM = 'accorde' | 'en_cours' | 'en_attente' | 'abandonne' | 'echoue' | 'anomalie';
export const ETATS_PAIEMENT_MM: EtatPaiementMM[] = ['accorde', 'en_cours', 'en_attente', 'abandonne', 'echoue', 'anomalie'];

const HEURE = 3_600_000;
/** Au-delà, un paiement « en cours » est bloqué. */
const BLOQUE_APRES_MS = HEURE;
/** Le lien de paiement expire en 24 h ; le rapprochement s'arrête à 26 h. */
const ABANDON_APRES_MS = 26 * HEURE;
const PAR_PAGE = 50;

export function etatPaiementMM(
  p: { statut: string; premiumAccordeLe: Date | null; creeLe: Date },
  maintenant = new Date(),
): EtatPaiementMM {
  if (p.premiumAccordeLe) return 'accorde';
  if (p.statut === 'anomalie' || p.statut === 'completed') return 'anomalie';
  if (p.statut === 'processing') return 'en_cours';
  if (p.statut === 'pending') {
    return maintenant.getTime() - p.creeLe.getTime() > ABANDON_APRES_MS ? 'abandonne' : 'en_attente';
  }
  return 'echoue';
}

export function estBloque(etat: EtatPaiementMM, creeLe: Date, maintenant = new Date()): boolean {
  return etat === 'anomalie'
    || (etat === 'en_cours' && maintenant.getTime() - creeLe.getTime() > BLOQUE_APRES_MS);
}

export async function resumePaiementsMobileMoney(params: {
  etat?: string; recherche?: string; sandbox?: boolean; jours?: number; page?: number;
} = {}) {
  const maintenant = new Date();
  const jours = Math.min(Math.max(params.jours ?? 30, 1), 365);
  const depuis = new Date(maintenant.getTime() - jours * 24 * HEURE);
  const lignes = await prisma.paiementGeniusPay.findMany({
    orderBy: { creeLe: 'desc' },
    take: 5000,
    include: { user: { select: {
      id: true, pseudo: true, email: true, subscriptionPlan: true, subscriptionExpiresAt: true, deletedAt: true,
    } } },
  });

  const paiements = lignes.map(p => {
    const etat = etatPaiementMM(p, maintenant);
    return {
      id:            p.id,
      etat,
      statut:        p.statut,
      bloque:        estBloque(etat, p.creeLe, maintenant),
      sandbox:       p.environnement !== 'live',
      formule:       PLANS_GENIUSPAY[p.plan]?.libelle ?? p.plan,
      montant:       p.montant,
      frais:         p.frais,
      net:           p.montantNet,
      moyen:         p.moyen,
      reference:     p.reference,
      creeLe:        p.creeLe.toISOString(),
      majLe:         p.majLe.toISOString(),
      accordeLe:     p.premiumAccordeLe?.toISOString() ?? null,
      ageHeures:     Math.floor((maintenant.getTime() - p.creeLe.getTime()) / HEURE),
      compte: {
        id:       p.user.id,
        pseudo:   p.user.pseudo,
        email:    p.user.email,
        premium:  p.user.subscriptionPlan === 'premium'
                  && (!p.user.subscriptionExpiresAt || p.user.subscriptionExpiresAt > maintenant),
        supprime: !!p.user.deletedAt,
      },
    };
  });

  // Les chiffres portent sur les paiements réels ; le bac à sable est compté à part.
  const reels = paiements.filter(p => !p.sandbox);
  const periode = reels.filter(p => new Date(p.creeLe) >= depuis);
  const accordes = periode.filter(p => p.etat === 'accorde');
  const somme = (xs: typeof paiements, f: (p: typeof paiements[number]) => number | null) =>
    xs.reduce((s, p) => s + (f(p) ?? 0), 0);
  const conclus = periode.filter(p => ['accorde', 'abandonne', 'echoue'].includes(p.etat)).length;
  const stats = {
    jours,
    encaisses: accordes.length,
    brut:      somme(accordes, p => p.montant),
    frais:     somme(accordes, p => p.frais),
    // Net inconnu : le brut moins les frais connus, à défaut.
    net:       somme(accordes, p => p.net ?? (p.frais !== null ? p.montant - p.frais : null)),
    bloques:   reels.filter(p => p.bloque).length,
    montantBloque: somme(reels.filter(p => p.bloque), p => p.montant),
    enAttente: reels.filter(p => p.etat === 'en_attente').length,
    abandonnes: periode.filter(p => p.etat === 'abandonne').length,
    echoues:   periode.filter(p => p.etat === 'echoue').length,
    // Sur les paiements ouverts et arrivés à leur terme dans la période.
    tauxReussite: conclus ? Math.round((accordes.length / conclus) * 100) : null,
    sandbox:   paiements.length - reels.length,
  };

  const q = params.recherche?.trim().toLowerCase();
  const filtres = paiements
    .filter(p => params.sandbox || !p.sandbox)
    .filter(p => !params.etat || (params.etat === 'bloque' ? p.bloque : p.etat === params.etat))
    .filter(p => !q || [p.compte.pseudo, p.compte.email, p.reference]
      .some(v => (v ?? '').toLowerCase().includes(q)))
    // Les bloqués d'abord, puis du plus récent au plus ancien.
    .sort((a, b) => Number(b.bloque) - Number(a.bloque) || b.creeLe.localeCompare(a.creeLe));
  const page = Math.max(params.page ?? 1, 1);
  return {
    stats,
    total:     filtres.length,
    page,
    parPage:   PAR_PAGE,
    paiements: filtres.slice((page - 1) * PAR_PAGE, page * PAR_PAGE),
  };
}

/**
 * Relit un paiement chez GeniusPay, quel que soit son âge, et en tire les
 * conséquences (Premium accordé s'il est payé et conforme). null : inconnu.
 */
export async function reverifierPaiementMobileMoney(id: string) {
  const avant = await prisma.paiementGeniusPay.findUnique({ where: { id } });
  if (!avant) return null;
  const apres = (await rapprocherPaiement(id)) ?? avant;
  const etat = etatPaiementMM(apres);
  return {
    etat,
    statut:         apres.statut,
    change:         apres.statut !== avant.statut || !!apres.premiumAccordeLe !== !!avant.premiumAccordeLe,
    premiumAccorde: !!apres.premiumAccordeLe && !avant.premiumAccordeLe,
    // Rien n'est relu pour un paiement déjà conclu ou en anomalie.
    relu:           !avant.premiumAccordeLe && !['failed', 'cancelled', 'expired', 'refunded', 'anomalie'].includes(avant.statut),
  };
}

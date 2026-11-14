import jwt from 'jsonwebtoken';
import { prisma } from '../lib/prisma';
import { ErreurMetier } from '../utils/erreurs';
import { AuthService } from './auth.service';
import { configGeniusPay, creerPaiement, etatPaiement, geniusPayOuvert, PLANS_GENIUSPAY } from './geniuspay.service';

/**
 * Paiement Mobile Money depuis le site, pronowin.space/premium (13 octobre
 * 2026).
 *
 * Google Play et l'App Store imposent leur achat intégré dans leurs
 * applications. Un abonné peut en revanche payer sur le site, et profiter du
 * Premium dans toutes les applications : il est porté par le compte. Les
 * applications des boutiques ne renvoient jamais vers cette page.
 *
 * ── Identifier sans connecter ────────────────────────────────────────────
 *
 * Le site ne connaît pas les comptes. L'abonné donne l'adresse e-mail de son
 * compte et reçoit le même code à 6 chiffres qu'à la connexion. Le code
 * vérifié ouvre un **jeton de paiement** de 30 minutes, signé avec un secret
 * distinct de celui des sessions : il permet de payer et de suivre le
 * paiement, rien d'autre — les routes de l'application le refusent.
 *
 * Une adresse inconnue reçoit la même réponse qu'une adresse connue : la page
 * ne dit pas qui est inscrit.
 */

const DUREE_JETON = '30m';
const PORTEE = 'paiement_web';

function secret(): string {
  if (!process.env.JWT_SECRET) throw new Error('JWT_SECRET absent.');
  return `${process.env.JWT_SECRET}:${PORTEE}`;
}

export function signerJetonPaiement(userId: string): string {
  return jwt.sign({ userId, portee: PORTEE }, secret(), { expiresIn: DUREE_JETON } as jwt.SignOptions);
}

/** Le compte du jeton de paiement, ou `null` s'il est faux, expiré ou d'une autre portée. */
export function lireJetonPaiement(jeton: string | undefined): string | null {
  if (!jeton) return null;
  try {
    const p = jwt.verify(jeton, secret()) as { userId?: string; portee?: string };
    return p.portee === PORTEE && p.userId ? p.userId : null;
  } catch {
    return null;
  }
}

function adresse(brute: unknown): string {
  const e = String(brute ?? '').trim().toLowerCase();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(e) || e.length > 254) {
    throw new ErreurMetier('Adresse e-mail invalide.', 400);
  }
  return e;
}

async function compteActif(email: string) {
  return prisma.user.findFirst({
    where: { email: { equals: email, mode: 'insensitive' }, deletedAt: null, isActive: true },
    select: { id: true, email: true, pseudo: true, subscriptionExpiresAt: true },
  });
}

/** Ce que la page affiche avant toute identification. */
export function offreWeb() {
  const cfg = configGeniusPay();
  return {
    // En test, le paiement n'est ouvert qu'aux comptes testeurs : la page
    // s'affiche, et le refus vient au moment de payer.
    disponible: !!cfg,
    environnement: cfg?.environnement ?? null,
    formules: Object.entries(PLANS_GENIUSPAY).map(([id, f]) => ({
      id, montant: f.montant(), jours: f.jours,
    })),
  };
}

/** Envoie le code de connexion habituel, si l'adresse est celle d'un compte. */
export async function envoyerCode(brute: unknown) {
  const email = adresse(brute);
  const compte = await compteActif(email);
  if (compte?.email) await new AuthService().sendEmailOtp(compte.email);
  return { message: 'Si un compte PronoWin utilise cette adresse, un code vient de lui être envoyé.' };
}

/** Vérifie le code et ouvre un jeton de paiement de 30 minutes. */
export async function verifierCode(brute: unknown, code: unknown) {
  const email = adresse(brute);
  const saisi = String(code ?? '').trim();
  const compte = await compteActif(email);
  if (!compte?.email || !/^\d{4,8}$/.test(saisi)
      || !await new AuthService().consommerCode(compte.email, saisi)) {
    throw new ErreurMetier('Code invalide ou expiré.', 400);
  }
  const premium = compte.subscriptionExpiresAt && compte.subscriptionExpiresAt > new Date()
    ? compte.subscriptionExpiresAt : null;
  const cfg = configGeniusPay();
  return {
    jeton: signerJetonPaiement(compte.id),
    compte: { pseudo: compte.pseudo, premium_jusqu_au: premium },
    paiement_ouvert: geniusPayOuvert(cfg, { id: compte.id, email: compte.email }),
  };
}

export async function payer(userId: string, plan: unknown) {
  return creerPaiement(userId, String(plan ?? ''), { retour: 'site' });
}

export async function suivre(userId: string, id: string) {
  return etatPaiement(userId, id);
}

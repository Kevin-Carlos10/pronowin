import { prisma } from '../lib/prisma';
import { ErreurMetier } from '../utils/erreurs';

/**
 * Ceux qui suivent un match : favori (« Suivre ce match »), ou pari en cours
 * sur son pronostic dans la bankroll. Un utilisateur dans les deux cas ne
 * reçoit qu'une alerte.
 *
 * ── Les alertes au choix (27 octobre 2026) ─────────────────────────────────
 *
 * Suivre un match envoyait tout : coup d'envoi, compositions, buts, cartons,
 * mi-temps, fin du match, résumé. Sur la semaine du 19 octobre, 145 alertes
 * de but pour 8 lues : trop, et le risque qu'on coupe tout. Chaque match
 * suivi garde désormais la liste des alertes choisies (toutes par défaut).
 * Un pari en cours sans suivi n'a rien choisi : il reçoit tout, comme avant.
 */
export const CATEGORIES_ALERTE = [
  'coup_envoi', 'compositions', 'buts', 'cartons', 'mi_temps', 'fin_de_match', 'resume',
] as const;
export type CategorieAlerte = typeof CATEGORIES_ALERTE[number];

export async function suiveursDuMatch(
  matchId: string, pronosticId: string | null, categorie?: CategorieAlerte,
): Promise<string[]> {
  const [abonnes, suiveurs, paris] = await Promise.all([
    prisma.userFavoriteMatch.findMany({
      where:  { matchId, ...(categorie ? { alertes: { has: categorie } } : {}) },
      select: { userId: true },
    }),
    // Ceux qui suivent, quelle que soit l'alerte : leur choix l'emporte sur
    // leur pari.
    categorie
      ? prisma.userFavoriteMatch.findMany({ where: { matchId }, select: { userId: true } })
      : Promise.resolve(null),
    pronosticId
      ? prisma.bankrollBet.findMany({
          where:  { pronosticId, result: null },
          select: { bankroll: { select: { userId: true } } },
        })
      : Promise.resolve([] as { bankroll: { userId: string } }[]),
  ]);
  const ontChoisi = new Set((suiveurs ?? abonnes).map(s => s.userId));
  const parieurs = paris.map(p => p.bankroll.userId).filter(u => !ontChoisi.has(u) || !categorie);
  return [...new Set([...abonnes.map(f => f.userId), ...parieurs])];
}

/** Le match, par son identifiant ou celui de son pronostic. */
async function idDuMatch(id: string): Promise<string | null> {
  const m = await prisma.match.findUnique({ where: { id }, select: { id: true } });
  if (m) return m.id;
  return (await prisma.pronostic.findUnique({ where: { id }, select: { matchId: true } }))?.matchId ?? null;
}

/** Suivi, et les alertes choisies — toutes, pour un match pas encore suivi. */
export async function lireAlertes(userId: string, id: string) {
  const matchId = await idDuMatch(id);
  if (!matchId) throw new ErreurMetier('Match introuvable.', 404);
  const f = await prisma.userFavoriteMatch.findUnique({
    where: { userId_matchId: { userId, matchId } }, select: { alertes: true },
  });
  return { suivi: f !== null, alertes: f?.alertes ?? [...CATEGORIES_ALERTE] };
}

/**
 * Choisit les alertes d'un match ; le suit s'il ne l'était pas. Une liste
 * vide garde le match suivi (il reste dans « Pour toi »), sans notification.
 */
export async function choisirAlertes(userId: string, id: string, alertes: unknown) {
  if (!Array.isArray(alertes) || alertes.some(a => !(CATEGORIES_ALERTE as readonly unknown[]).includes(a))) {
    throw new ErreurMetier(`Alertes invalides : ${CATEGORIES_ALERTE.join(', ')}.`, 422);
  }
  const matchId = await idDuMatch(id);
  if (!matchId) throw new ErreurMetier('Match introuvable.', 404);
  // Dans l'ordre du catalogue, sans doublon.
  const choisies = CATEGORIES_ALERTE.filter(c => (alertes as string[]).includes(c));
  await prisma.userFavoriteMatch.upsert({
    where:  { userId_matchId: { userId, matchId } },
    create: { userId, matchId, alertes: choisies },
    update: { alertes: choisies },
  });
  return { suivi: true, alertes: choisies };
}

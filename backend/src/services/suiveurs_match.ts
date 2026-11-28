import { prisma } from '../lib/prisma';
import { ErreurMetier } from '../utils/erreurs';
import { isNotifEnabled } from './notification.service';
import { idEquipeDepuisLogo } from './recherche_equipes_joueurs.service';

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

/** De quoi trouver ceux qui suivent les équipes ou la ligue d'un match. */
export interface ContexteSuivi {
  league?: string | null;
  homeTeamLogo?: string | null;
  awayTeamLogo?: string | null;
}

/**
 * [contexte] (15 novembre 2026) : ceux qui suivent l'une des deux équipes ou
 * la ligue du match s'ajoutent, pour les alertes que ce suivi annonce
 * (`suiveursEquipesLigues`). Qui suit aussi le match lui-même a fait son
 * choix pour lui : c'est ce choix qui compte.
 */
export async function suiveursDuMatch(
  matchId: string, pronosticId: string | null, categorie?: CategorieAlerte, contexte?: ContexteSuivi,
): Promise<string[]> {
  const [abonnes, suiveurs, paris, fans] = await Promise.all([
    prisma.userFavoriteMatch.findMany({
      where:  { matchId, ...(categorie ? { alertes: { has: categorie } } : {}) },
      select: { userId: true },
    }),
    // Ceux qui suivent, quelle que soit l'alerte : leur choix l'emporte sur
    // leur pari.
    categorie
      ? prisma.userFavoriteMatch.findMany({ where: { matchId }, select: { userId: true } })
      : Promise.resolve(null),
    // Les paris en cours sur n'importe quel pronostic du match (plusieurs
    // par match, 23 novembre 2026), pas seulement sur le principal.
    pronosticId
      ? prisma.bankrollBet.findMany({
          where:  { pronostic: { matchId }, result: null },
          select: { bankroll: { select: { userId: true } } },
        })
      : Promise.resolve([] as { bankroll: { userId: string } }[]),
    categorie && contexte ? suiveursEquipesLigues(contexte, categorie) : Promise.resolve([] as string[]),
  ]);
  const ontChoisi = new Set((suiveurs ?? abonnes).map(s => s.userId));
  const parieurs = paris.map(p => p.bankroll.userId).filter(u => !ontChoisi.has(u) || !categorie);
  return [...new Set([...abonnes.map(f => f.userId), ...parieurs, ...fans.filter(u => !ontChoisi.has(u))])];
}

/**
 * ── Les équipes et ligues suivies (15 novembre 2026) ──────────────────────
 *
 * Suivre une équipe ou une ligue ne faisait qu'afficher ses matchs dans
 * « Suivis » : aucune alerte. Une équipe suivie annonce le coup d'envoi, les
 * buts et le résultat de ses matchs ; une ligue, le coup d'envoi et le
 * résultat seulement — les buts de dix matchs d'une journée feraient trop
 * (145 alertes de but pour 8 lues, semaine du 19 octobre). Chacun des deux
 * se coupe dans les réglages (`equipes_suivies`, `ligues_suivies`).
 */
export const ALERTES_EQUIPE_SUIVIE: readonly CategorieAlerte[] = ['coup_envoi', 'buts', 'fin_de_match'];
export const ALERTES_LIGUE_SUIVIE: readonly CategorieAlerte[] = ['coup_envoi', 'fin_de_match'];

export async function suiveursEquipesLigues(contexte: ContexteSuivi, categorie: CategorieAlerte): Promise<string[]> {
  const equipes = [...new Set([contexte.homeTeamLogo, contexte.awayTeamLogo]
    .map(idEquipeDepuisLogo).filter((id): id is number => id !== null))];
  const parEquipe = ALERTES_EQUIPE_SUIVIE.includes(categorie) && equipes.length > 0;
  const ligue = contexte.league?.trim() ?? '';
  const parLigue = ALERTES_LIGUE_SUIVIE.includes(categorie) && ligue.length > 0;
  if (!parEquipe && !parLigue) return [];
  // Un compte supprimé garde sa ligne, anonymisée : rien ne lui part.
  const actif = { deletedAt: null };
  const avecPrefs = { userId: true, user: { select: { notificationPrefs: true } } } as const;
  const [fans, habitues] = await Promise.all([
    parEquipe
      ? prisma.userEquipeSuivie.findMany({ where: { equipeId: { in: equipes }, user: actif }, select: avecPrefs })
      : Promise.resolve([]),
    parLigue
      ? prisma.userLigueSuivie.findMany({ where: { ligue, user: actif }, select: avecPrefs })
      : Promise.resolve([]),
  ]);
  return [...new Set([
    ...fans.filter(f => isNotifEnabled(f.user.notificationPrefs, 'equipes_suivies')).map(f => f.userId),
    ...habitues.filter(h => isNotifEnabled(h.user.notificationPrefs, 'ligues_suivies')).map(h => h.userId),
  ])];
}

/** Une équipe suivie, au format de l'application. */
export interface EquipeSuivieDto { id: number; nom: string; logo: string | null; competition: string | null }

/** Les équipes et ligues suivies, dans l'ordre où elles l'ont été. */
export async function lireSuivis(userId: string): Promise<{ ligues: string[]; equipes: EquipeSuivieDto[] }> {
  const [equipes, ligues] = await Promise.all([
    prisma.userEquipeSuivie.findMany({ where: { userId }, orderBy: { createdAt: 'asc' } }),
    prisma.userLigueSuivie.findMany({ where: { userId }, orderBy: { createdAt: 'asc' } }),
  ]);
  return {
    ligues:  ligues.map(l => l.ligue),
    equipes: equipes.map(e => ({ id: e.equipeId, nom: e.nom, logo: e.logo, competition: e.competition })),
  };
}

/** Plus que n'en suivra jamais un supporter ; au-delà, une liste suspecte. */
export const MAX_SUIVIS = 300;

const texte = (v: unknown, max: number): v is string =>
  typeof v === 'string' && v.trim().length > 0 && v.length <= max;

/**
 * Remplace les ligues et/ou les équipes suivies par celles reçues — l'une
 * des deux listes peut manquer, elle reste alors telle quelle. L'ordre reçu
 * est gardé.
 */
export async function enregistrerSuivis(userId: string, corps: unknown) {
  const c = (corps && typeof corps === 'object' ? corps : {}) as { ligues?: unknown; equipes?: unknown };
  if (c.ligues === undefined && c.equipes === undefined) {
    throw new ErreurMetier('Rien à enregistrer : « ligues » ou « equipes » attendu.', 422);
  }
  let ligues: string[] | undefined;
  if (c.ligues !== undefined) {
    if (!Array.isArray(c.ligues) || c.ligues.length > MAX_SUIVIS || !c.ligues.every(l => texte(l, 120))) {
      throw new ErreurMetier('Ligues invalides.', 422);
    }
    ligues = [...new Set((c.ligues as string[]).map(l => l.trim()))];
  }
  let equipes: Array<{ equipeId: number; nom: string; logo: string | null; competition: string | null }> | undefined;
  if (c.equipes !== undefined) {
    if (!Array.isArray(c.equipes) || c.equipes.length > MAX_SUIVIS) throw new ErreurMetier('Équipes invalides.', 422);
    const vues = new Map<number, NonNullable<typeof equipes>[number]>();
    for (const e of c.equipes as unknown[]) {
      const { id, nom, logo, competition } = (e && typeof e === 'object' ? e : {}) as Record<string, unknown>;
      const valide = typeof id === 'number' && Number.isInteger(id) && id > 0 && texte(nom, 120)
        && (logo == null || texte(logo, 500)) && (competition == null || texte(competition, 120));
      if (!valide) throw new ErreurMetier('Équipes invalides.', 422);
      if (!vues.has(id as number)) {
        vues.set(id as number, { equipeId: id as number, nom: (nom as string).trim(),
          logo: (logo as string | null | undefined) ?? null, competition: (competition as string | null | undefined) ?? null });
      }
    }
    equipes = [...vues.values()];
  }
  // Les dates suivent l'ordre reçu : c'est celui de la lecture.
  const t0 = Date.now();
  const date = (i: number) => new Date(t0 + i);
  await prisma.$transaction([
    ...(ligues ? [
      prisma.userLigueSuivie.deleteMany({ where: { userId } }),
      prisma.userLigueSuivie.createMany({ data: ligues.map((ligue, i) => ({ userId, ligue, createdAt: date(i) })) }),
    ] : []),
    ...(equipes ? [
      prisma.userEquipeSuivie.deleteMany({ where: { userId } }),
      prisma.userEquipeSuivie.createMany({ data: equipes.map((e, i) => ({ userId, ...e, createdAt: date(i) })) }),
    ] : []),
  ]);
  return lireSuivis(userId);
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

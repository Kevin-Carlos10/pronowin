import { prisma } from '../lib/prisma';
import { ErreurMetier } from '../utils/erreurs';
import { DUREE_DANS_LE_FIL_MS } from './resumes_match.service';

/**
 * Les résumés de match vus depuis le panneau (22 octobre 2026) : les relire,
 * en corriger le texte, les retirer du fil.
 *
 * Ils s'écrivent seuls (resumes_match.service.ts), une soixantaine par
 * semaine depuis qu'ils couvrent les grandes compétitions. Le 22 octobre,
 * trois titres prêtaient au vainqueur le doublé d'un joueur de l'équipe
 * battue ; il a fallu un script sur le serveur pour les corriger.
 *
 * Retirer un résumé ne l'efface pas : la ligne reste, marquée « masqué », et
 * le résumé n'est pas réécrit au passage suivant. Un texte corrigé ne l'est
 * pas non plus : un résumé n'est rédigé qu'une fois.
 */

export type FiltreResumes = 'tous' | 'dans_le_fil' | 'masques' | 'modifies';
export const FILTRES_RESUMES: FiltreResumes[] = ['tous', 'dans_le_fil', 'masques', 'modifies'];

const PAR_PAGE = 30;
/** Les limites du texte, comme pour un article du panneau. */
const LONGUEUR_TITRE = 200;
const LONGUEUR_RESUME = 5000;

const AVEC_MATCH = {
  match: { select: {
    homeTeam: true, awayTeam: true, homeScore: true, awayScore: true,
    matchDate: true, hasPublishedPronostic: true,
  } },
} as const;

type Ligne = Awaited<ReturnType<typeof lireLigne>>;
const lireLigne = (id: string) => prisma.resumeMatch.findUnique({ where: { id }, include: AVEC_MATCH });

function presenter(r: NonNullable<Ligne>, maintenant: number) {
  const m = r.match;
  return {
    id:         r.id,
    matchId:    r.matchId,
    ligue:      r.ligue,
    titre:      r.titre,
    titreEn:    r.titreEn,
    resume:     r.resume,
    resumeEn:   r.resumeEn,
    creeLe:     r.creeLe.toISOString(),
    masque:     r.masque,
    modifieLe:  r.modifieLe?.toISOString() ?? null,
    modifiePar: r.modifiePar,
    // Dans le fil : moins de trois jours, et pas retiré.
    dansLeFil:  !r.masque && r.creeLe.getTime() >= maintenant - DUREE_DANS_LE_FIL_MS,
    quitteLeFil: new Date(r.creeLe.getTime() + DUREE_DANS_LE_FIL_MS).toISOString(),
    match: m ? {
      domicile:    m.homeTeam,
      exterieur:   m.awayTeam,
      score:       m.homeScore !== null && m.awayScore !== null ? `${m.homeScore}-${m.awayScore}` : null,
      date:        m.matchDate.toISOString(),
      pronostique: m.hasPublishedPronostic,
    } : null,
  };
}

export type ResumeAdmin = ReturnType<typeof presenter>;

export async function listerResumesAdmin(o: {
  filtre?: FiltreResumes; recherche?: string; page?: number;
}, maintenant = new Date()) {
  const t = maintenant.getTime();
  const depuisFil = new Date(t - DUREE_DANS_LE_FIL_MS);
  const page = Math.max(1, Math.floor(o.page ?? 1));
  const q = o.recherche?.trim();

  const parFiltre = {
    tous:        {},
    dans_le_fil: { masque: false, creeLe: { gte: depuisFil } },
    masques:     { masque: true },
    modifies:    { modifieLe: { not: null } },
  }[o.filtre ?? 'tous'];
  const where = {
    ...parFiltre,
    ...(q ? { OR: [
      { titre: { contains: q, mode: 'insensitive' as const } },
      { ligue: { contains: q, mode: 'insensitive' as const } },
      { match: { homeTeam: { contains: q, mode: 'insensitive' as const } } },
      { match: { awayTeam: { contains: q, mode: 'insensitive' as const } } },
    ] } : {}),
  };

  const [lignes, total, tous, dansLeFil, masques, modifies] = await Promise.all([
    prisma.resumeMatch.findMany({
      where, include: AVEC_MATCH, orderBy: { creeLe: 'desc' },
      skip: (page - 1) * PAR_PAGE, take: PAR_PAGE,
    }),
    prisma.resumeMatch.count({ where }),
    prisma.resumeMatch.count(),
    prisma.resumeMatch.count({ where: { masque: false, creeLe: { gte: depuisFil } } }),
    prisma.resumeMatch.count({ where: { masque: true } }),
    prisma.resumeMatch.count({ where: { modifieLe: { not: null } } }),
  ]);

  return {
    stats: { total: tous, dansLeFil, masques, modifies },
    total, page, parPage: PAR_PAGE,
    resumes: lignes.map(r => presenter(r, t)),
  };
}

export async function lireResumeAdmin(id: string, maintenant = new Date()): Promise<ResumeAdmin | null> {
  const r = await lireLigne(id);
  return r ? presenter(r, maintenant.getTime()) : null;
}

/** Un champ du formulaire : obligatoire, sans espaces autour, retours à la ligne unifiés. */
function texte(v: unknown, nom: string, max: number): string {
  if (typeof v !== 'string') throw new ErreurMetier(`${nom} : champ manquant.`, 422);
  const s = v.replace(/\r\n?/g, '\n').trim();
  if (!s) throw new ErreurMetier(`${nom} : ne peut pas être vide.`, 422);
  if (s.length > max) throw new ErreurMetier(`${nom} : ${max} caractères au plus (${s.length}).`, 422);
  return s;
}

/** Corrige le texte d'un résumé ; null s'il n'existe pas. */
export async function modifierResume(id: string, champs: {
  titre?: unknown; titreEn?: unknown; resume?: unknown; resumeEn?: unknown;
}, auteur: string, maintenant = new Date()): Promise<ResumeAdmin | null> {
  const data = {
    titre:    texte(champs.titre,    'Titre',                LONGUEUR_TITRE),
    titreEn:  texte(champs.titreEn,  'Titre en anglais',     LONGUEUR_TITRE),
    resume:   texte(champs.resume,   'Texte',                LONGUEUR_RESUME),
    resumeEn: texte(champs.resumeEn, 'Texte en anglais',     LONGUEUR_RESUME),
  };
  if (!await prisma.resumeMatch.findUnique({ where: { id }, select: { id: true } })) return null;
  await prisma.resumeMatch.update({
    where: { id },
    data: { ...data, modifieLe: maintenant, modifiePar: auteur.slice(0, 100) },
  });
  return lireResumeAdmin(id, maintenant);
}

/** Retire un résumé du fil, ou l'y remet ; null s'il n'existe pas. */
export async function masquerResume(id: string, masque: boolean, maintenant = new Date()): Promise<ResumeAdmin | null> {
  if (!await prisma.resumeMatch.findUnique({ where: { id }, select: { id: true } })) return null;
  await prisma.resumeMatch.update({ where: { id }, data: { masque } });
  return lireResumeAdmin(id, maintenant);
}

import { prisma } from '../lib/prisma';
import { ErreurMetier } from '../utils/erreurs';
import { journal } from '../utils/logger';
import { cache, CACHE_KEYS } from './cache.service';
import { CAMPAIGN_SEGMENTS, NotificationService } from './notification.service';
import { PronosticsService, verifierCotePublication } from './pronostics.service';

/**
 * Publier un pronostic, envoyer une notification — à une heure choisie.
 *
 * Rien ne le permettait : un pronostic prêt la veille devait être publié à la
 * main le lendemain matin, une annonce « match ce soir » envoyée à l'heure où
 * l'administrateur était disponible plutôt qu'à celle où elle sert.
 *
 * ── Exécution ────────────────────────────────────────────────────────────────
 *
 * Le processus des tâches regarde chaque minute ce qui est arrivé à échéance.
 * Chaque programmation est réservée par un « comparer puis échanger » (statut
 * `prevue` → `en_cours`) : même si deux processus tournaient, une seule
 * exécution aurait lieu — une notification envoyée deux fois ne se rattrape
 * pas.
 *
 * ── Ce qui ne doit pas partir ────────────────────────────────────────────────
 *
 * - Un pronostic dont le match a commencé : le publier après le coup d'envoi
 *   annoncerait un pari que plus personne ne peut prendre.
 * - Une notification en retard de plus d'une heure (serveur arrêté à l'heure
 *   prévue) : « match ce soir » reçu le lendemain fait plus de mal que rien.
 *
 * Dans les deux cas la programmation passe en échec, avec la raison en clair.
 */

export const TYPES = ['publication_pronostic', 'notification'] as const;
export type TypeProgrammation = typeof TYPES[number];

const MINUTE = 60_000;
/** Pas avant une minute : sinon, autant publier tout de suite. */
const DELAI_MIN_MS = MINUTE;
const HORIZON_MAX_MS = 30 * 24 * 60 * MINUTE;
/** Une notification plus en retard que ça n'est pas envoyée. */
const RETARD_MAX_NOTIFICATION_MS = 60 * MINUTE;
/** Un pronostic se publie au plus tard cinq minutes avant le coup d'envoi. */
const MARGE_COUP_ENVOI_MS = 5 * MINUTE;
/** Une exécution qui n'a pas rendu compte après ce délai a été interrompue. */
const EXECUTION_MAX_MS = 10 * MINUTE;

function verifierHeure(prevueLe: Date, maintenant = new Date()) {
  if (!Number.isFinite(prevueLe.getTime())) throw new ErreurMetier('Date de programmation invalide.', 422);
  if (prevueLe.getTime() < maintenant.getTime() + DELAI_MIN_MS) {
    throw new ErreurMetier("L'heure choisie est déjà passée, ou dans moins d'une minute.", 422);
  }
  if (prevueLe.getTime() > maintenant.getTime() + HORIZON_MAX_MS) {
    throw new ErreurMetier('Une programmation se fait au plus 30 jours à l\'avance.', 422);
  }
}

const fmt = (d: Date) => d.toLocaleString('fr-FR', {
  timeZone: 'Africa/Ouagadougou', day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit',
});

// ─── Création et annulation ──────────────────────────────────────────────────

/**
 * Programme la publication d'un pronostic enregistré en brouillon. Une
 * programmation déjà prévue pour lui est remplacée : il n'y en a qu'une.
 */
export async function programmerPublication(params: {
  pronosticId?: string; matchId?: string; prevueLe: Date; auteur?: string;
}, maintenant = new Date()) {
  verifierHeure(params.prevueLe, maintenant);
  const p = await prisma.pronostic.findFirst({
    where:   params.pronosticId ? { id: params.pronosticId } : { matchId: params.matchId ?? '' },
    include: { match: { select: { homeTeam: true, awayTeam: true, matchDate: true, status: true } } },
  });
  if (!p) throw new ErreurMetier('Pronostic introuvable : enregistrez-le d\'abord en brouillon.', 404);
  if (p.isPublished) throw new ErreurMetier('Ce pronostic est déjà publié.', 409);
  if (p.match.status !== 'SCHEDULED') throw new ErreurMetier('Le match n\'est plus à venir : impossible de programmer.', 422);
  if (params.prevueLe.getTime() > p.match.matchDate.getTime() - MARGE_COUP_ENVOI_MS) {
    throw new ErreurMetier(
      `La publication doit avoir lieu au plus tard 5 minutes avant le coup d'envoi (${fmt(p.match.matchDate)}).`, 422);
  }
  // Refusé maintenant plutôt qu'à l'heure dite, quand personne ne regarde.
  verifierCotePublication(p.oddsRecommended);

  return prisma.$transaction(async (t) => {
    await t.programmation.updateMany({
      where: { type: 'publication_pronostic', pronosticId: p.id, statut: 'prevue' },
      data:  { statut: 'annulee', compteRendu: 'Remplacée par une nouvelle programmation.' },
    });
    return t.programmation.create({ data: {
      type: 'publication_pronostic', pronosticId: p.id, prevueLe: params.prevueLe,
      creeePar: params.auteur ?? null,
    } });
  });
}

export async function programmerNotification(params: {
  segment: string; title: string; body: string; deepLink?: string | null; imageUrl?: string | null;
  prevueLe: Date; auteur?: string;
}, maintenant = new Date()) {
  verifierHeure(params.prevueLe, maintenant);
  if (!(CAMPAIGN_SEGMENTS as readonly string[]).includes(params.segment)) {
    // L'envoi à une seule personne sert à tester un message : il se fait tout de suite.
    throw new ErreurMetier('Audience inconnue, ou non programmable.', 422);
  }
  const title = String(params.title ?? '').trim();
  const body  = String(params.body ?? '').trim();
  if (!title || !body) throw new ErreurMetier('Le titre et le message sont obligatoires.', 422);
  if (title.length > 100 || body.length > 300) {
    throw new ErreurMetier('Titre : 100 caractères au plus ; message : 300.', 422);
  }
  return prisma.programmation.create({ data: {
    type: 'notification', prevueLe: params.prevueLe, creeePar: params.auteur ?? null,
    charge: { segment: params.segment, title, body,
              ...(params.deepLink ? { deepLink: params.deepLink } : {}),
              ...(params.imageUrl ? { imageUrl: params.imageUrl } : {}) },
  } });
}

/** Annule une programmation encore prévue, du type attendu. */
export async function annulerProgrammation(id: string, type: TypeProgrammation, auteur?: string) {
  const { count } = await prisma.programmation.updateMany({
    where: { id, type, statut: 'prevue' },
    data:  { statut: 'annulee', compteRendu: `Annulée${auteur ? ' par ' + auteur : ''}.` },
  });
  if (!count) throw new ErreurMetier('Programmation introuvable, ou déjà exécutée.', 409);
  return { ok: true };
}

/**
 * Les programmations d'un type : toutes celles à venir, puis les 30 dernières
 * exécutées, annulées ou en échec. Pour une publication, le match est joint.
 */
export async function listerProgrammations(type: TypeProgrammation, filtre: { pronosticId?: string } = {}) {
  const base = { type, ...(filtre.pronosticId ? { pronosticId: filtre.pronosticId } : {}) };
  const [aVenir, passees] = await Promise.all([
    prisma.programmation.findMany({ where: { ...base, statut: { in: ['prevue', 'en_cours'] } }, orderBy: { prevueLe: 'asc' } }),
    prisma.programmation.findMany({ where: { ...base, statut: { in: ['executee', 'annulee', 'echec'] } },
                                    orderBy: { prevueLe: 'desc' }, take: 30 }),
  ]);
  const toutes = [...aVenir, ...passees];
  const ids = [...new Set(toutes.map((p) => p.pronosticId).filter((x): x is string => !!x))];
  const pronos = ids.length ? await prisma.pronostic.findMany({
    where:  { id: { in: ids } },
    select: { id: true, matchId: true, predictionLabel: true,
              match: { select: { homeTeam: true, awayTeam: true, matchDate: true } } },
  }) : [];
  const parId = new Map(pronos.map((p) => [p.id, p]));
  const habiller = (p: typeof toutes[number]) => {
    const pr = p.pronosticId ? parId.get(p.pronosticId) : undefined;
    return {
      id: p.id, type: p.type, statut: p.statut, prevueLe: p.prevueLe.toISOString(),
      creeePar: p.creeePar, creeeLe: p.creeeLe.toISOString(),
      executeeLe: p.executeeLe?.toISOString() ?? null, compteRendu: p.compteRendu,
      charge: p.charge,
      pronostic: pr ? { id: pr.id, matchId: pr.matchId, libelle: pr.predictionLabel,
                        match: `${pr.match.homeTeam} – ${pr.match.awayTeam}`,
                        coupEnvoi: pr.match.matchDate.toISOString() } : null,
    };
  };
  return { aVenir: aVenir.map(habiller), passees: passees.map(habiller) };
}

// ─── Exécution ───────────────────────────────────────────────────────────────

const notifSvc = () => new NotificationService();

/**
 * La même suite que le bouton « Publier » du panneau (contrôleur
 * `togglePublish`) : publier — la cote minimale est vérifiée là —, annoncer
 * aux membres, vider le cache des listes.
 *
 * Le cache vidé ici est celui du processus des tâches. Celui de l'API expire
 * de lui-même : le pronostic apparaît dans l'application en deux minutes au
 * plus.
 */
async function publierPronostic(pronosticId: string, maintenant: Date): Promise<string> {
  const p = await prisma.pronostic.findUnique({ where: { id: pronosticId }, include: { match: true } });
  if (!p) throw new Error('Pronostic supprimé entre-temps.');
  const libelle = `${p.match.homeTeam} – ${p.match.awayTeam}`;
  if (p.isPublished) return `${libelle} : déjà publié à la main, rien à faire.`;
  if (p.match.status !== 'SCHEDULED' || p.match.matchDate.getTime() <= maintenant.getTime()) {
    throw new Error(`${libelle} : le match a commencé, le pronostic reste en brouillon.`);
  }
  await new PronosticsService().togglePublish(p.id, true);
  notifSvc().notifyPronosticPublished({
    homeTeam: p.match.homeTeam, awayTeam: p.match.awayTeam, pronosticId: p.id,
    predictionLabel: p.predictionLabel, isPremium: p.isPremium, matchStatus: p.match.status,
  }).catch(() => {});
  cache.del('pronostics:');
  cache.del(CACHE_KEYS.publicStats);
  return `${libelle} : publié, membres prévenus.`;
}

async function envoyerNotification(charge: any, prevueLe: Date, maintenant: Date): Promise<string> {
  const retard = maintenant.getTime() - prevueLe.getTime();
  if (retard > RETARD_MAX_NOTIFICATION_MS) {
    throw new Error(`Non envoyée : ${Math.round(retard / MINUTE)} minutes de retard sur l'heure prévue `
      + '(serveur arrêté ?). Un message d\'actualité reçu trop tard fait plus de mal que rien.');
  }
  const r: any = await notifSvc().sendToSegment(String(charge?.segment ?? ''), {
    title: String(charge?.title ?? ''), body: String(charge?.body ?? ''),
    deepLink: charge?.deepLink ?? undefined, imageUrl: charge?.imageUrl ?? undefined,
  });
  const envoyes = Number(r?.sent ?? 0);
  if (r?.error === 'firebase_non_configure') return 'Inscrite dans l\'historique des membres ; envoi push indisponible.';
  return envoyes
    ? `Envoyée à ${envoyes.toLocaleString('fr-FR')} membre${envoyes > 1 ? 's' : ''}.`
    : 'Aucun destinataire joignable.';
}

/** Exécute ce qui est arrivé à échéance. Appelée chaque minute par les tâches. */
export async function executerProgrammationsEchues(maintenant = new Date()) {
  // Une exécution interrompue (processus arrêté en plein travail) ne reste
  // pas « en cours » pour toujours.
  await prisma.programmation.updateMany({
    where: { statut: 'en_cours', executeeLe: { lt: new Date(maintenant.getTime() - EXECUTION_MAX_MS) } },
    data:  { statut: 'echec', compteRendu: 'Exécution interrompue : à vérifier, puis reprogrammer si besoin.' },
  });

  const dues = await prisma.programmation.findMany({
    where: { statut: 'prevue', prevueLe: { lte: maintenant } }, orderBy: { prevueLe: 'asc' }, take: 20,
  });
  let executees = 0;
  for (const p of dues) {
    const { count } = await prisma.programmation.updateMany({
      where: { id: p.id, statut: 'prevue' }, data: { statut: 'en_cours', executeeLe: maintenant },
    });
    if (!count) continue;   // prise par un autre processus, ou annulée entre-temps
    try {
      const compteRendu = p.type === 'publication_pronostic'
        ? await publierPronostic(p.pronosticId ?? '', maintenant)
        : await envoyerNotification(p.charge, p.prevueLe, maintenant);
      await prisma.programmation.update({ where: { id: p.id },
        data: { statut: 'executee', executeeLe: new Date(), compteRendu } });
      executees++;
    } catch (e: any) {
      journal.warn(`[programmations] ${p.type} ${p.id} en échec :`, e?.message);
      await prisma.programmation.update({ where: { id: p.id },
        data: { statut: 'echec', executeeLe: new Date(), compteRendu: String(e?.message ?? e).slice(0, 500) } })
        .catch(() => {});
    }
  }
  return { executees, dues: dues.length };
}

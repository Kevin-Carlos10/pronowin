import fs from 'fs';

import { prisma } from '../lib/prisma';
import { etatDesTaches, lireEtatPublie, SILENCE_MAX_MS, tachesDansLApi } from './etat_taches';

/**
 * L'état de la machine, tel que le tableau de bord doit le montrer.
 *
 * Le tableau de bord ne disait rien de la santé du système : ni l'API, ni la
 * dernière synchronisation des scores, ni le quota football, ni la dernière
 * sauvegarde. Le compte de service a ainsi échoué des semaines sans que
 * personne ne le voie (constats A7 et I6 de l'audit du 24 septembre 2026).
 *
 * Chaque bloc se lit indépendamment : une lecture en échec rend `null` pour
 * ce bloc, et le reste s'affiche quand même.
 */
export const FICHIER_ETAT_SAUVEGARDE =
  process.env.SAUVEGARDE_ETAT ?? '/var/lib/pronowin/sauvegarde.json';

type CopieDistante = { distante?: string; erreur?: string } | null;

async function lireSauvegarde(): Promise<{ derniere: string; taille: string | null; panneau: boolean; copieDistante: CopieDistante } | null> {
  try {
    const brut = JSON.parse(await fs.promises.readFile(FICHIER_ETAT_SAUVEGARDE, 'utf8'));
    if (typeof brut?.derniere !== 'string') return null;
    // Copie hors du serveur (O4) : null tant qu'elle n'est pas configurée.
    const c = brut.copieDistante;
    const copieDistante: CopieDistante = c && typeof c === 'object'
      ? { ...(typeof c.distante === 'string' ? { distante: c.distante } : {}),
          ...(typeof c.erreur === 'string' ? { erreur: c.erreur } : {}) }
      : null;
    return { derniere: brut.derniere, taille: brut.taille ?? null, panneau: !!brut.panneau, copieDistante };
  } catch {
    return null;
  }
}

async function essayer<T>(lire: () => Promise<T>): Promise<T | null> {
  try { return await lire(); } catch { return null; }
}

export async function lireSante() {
  const debut = Date.now();
  const base = await essayer(async () => {
    await prisma.$queryRaw`SELECT 1`;
    return { ok: true, latenceMs: Date.now() - debut };
  }) ?? { ok: false, latenceMs: null };

  const [fileStore, preuves, sauvegarde] = await Promise.all([
    essayer(async () => {
      const groupes = await prisma.iapNotification.groupBy({ by: ['statut'], _count: { _all: true } });
      return Object.fromEntries(groupes.map((g) => [g.statut, g._count._all]));
    }),
    essayer(async () => {
      const [nombre, plusAncienne] = await Promise.all([
        prisma.subscriptionProof.count({ where: { status: 'pending' } }),
        prisma.subscriptionProof.findFirst({
          where: { status: 'pending' }, orderBy: { createdAt: 'asc' }, select: { createdAt: true } }),
      ]);
      return { nombre, plusAncienne: plusAncienne?.createdAt.toISOString() ?? null };
    }),
    lireSauvegarde(),
  ]);

  const { demarreLe } = etatDesTaches();
  // Les tâches tournent dans l'API, ou dans pronowin-taches (P1) : leur état
  // vient alors de ce qu'il a publié en base.
  let { taches, quotaFootball } = etatDesTaches();
  let processusTaches: { separe: boolean; demarreLe: string | null; publieLe: string | null; silencieux: boolean } =
    { separe: false, demarreLe, publieLe: null, silencieux: false };
  if (!tachesDansLApi()) {
    const publie = await lireEtatPublie();
    taches = publie?.taches ?? {};
    quotaFootball = publie?.quotaFootball ?? null;
    processusTaches = {
      separe:     true,
      demarreLe:  publie?.demarreLe ?? null,
      publieLe:   publie?.publieLe ?? null,
      silencieux: !publie || Date.now() - Date.parse(publie.publieLe) > SILENCE_MAX_MS,
    };
  }
  return {
    genereLe: new Date().toISOString(),
    api: { demarreLe, node: process.version },
    base,
    taches,
    processusTaches,
    quotaFootball,
    fileStore,
    preuves,
    sauvegarde,
  };
}

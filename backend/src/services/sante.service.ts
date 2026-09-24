import fs from 'fs';

import { prisma } from '../lib/prisma';
import { etatDesTaches } from './etat_taches';

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

async function lireSauvegarde(): Promise<{ derniere: string; taille: string | null; panneau: boolean } | null> {
  try {
    const brut = JSON.parse(await fs.promises.readFile(FICHIER_ETAT_SAUVEGARDE, 'utf8'));
    if (typeof brut?.derniere !== 'string') return null;
    return { derniere: brut.derniere, taille: brut.taille ?? null, panneau: !!brut.panneau };
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

  const { demarreLe, taches, quotaFootball } = etatDesTaches();
  return {
    genereLe: new Date().toISOString(),
    api: { demarreLe, node: process.version },
    base,
    taches,
    quotaFootball,
    fileStore,
    preuves,
    sauvegarde,
  };
}

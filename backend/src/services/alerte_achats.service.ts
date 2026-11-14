import { prisma } from '../lib/prisma';
import logger from '../utils/logger';
import { envoyerAlerteAdmin } from './email.service';

/**
 * L'argent est arrivé, l'abonnement n'est pas parti, personne ne l'a vu.
 *
 * ── Ce que rien ne couvrait ───────────────────────────────────────────────
 *
 * Un utilisateur paie, envoie sa capture, et attend. La validation est
 * manuelle : quelqu'un doit ouvrir le panneau d'administration et approuver.
 * Si personne ne l'ouvre, la preuve reste `pending` indéfiniment — sans délai,
 * sans relance, sans que rien ne le signale. L'utilisateur a payé et n'a rien.
 *
 * C'est la panne la plus coûteuse du système : elle ne fait tomber aucun
 * service, n'apparaît dans aucun journal d'erreur, et se mesure directement en
 * argent encaissé sans contrepartie.
 *
 * ── Le seuil, et pourquoi il n'est pas « ouvrable » ───────────────────────
 *
 * Les écrans annoncent « 30 minutes ouvrables » et « 2 heures ouvrables ».
 * Calculer des heures ouvrables demanderait de définir les jours et horaires
 * de travail au Burkina Faso, puis de les tenir à jour — une seconde règle,
 * vouée à diverger de la première.
 *
 * Six heures d'horloge évitent ce calcul tout en restant très au-delà de ce
 * qui est promis. Une preuve déposée un samedi matin déclenchera l'alerte
 * avant lundi : ce n'est pas une fausse alerte, c'est quelqu'un qui a payé et
 * qui attend. Laisser courir jusqu'à lundi serait le vrai défaut.
 */
export const SEUIL_ATTENTE_HEURES = 6;

/** Intervalle entre deux contrôles. Égal au seuil : détection sous 12 h au pire. */
export const INTERVALLE_CONTROLE_MS = SEUIL_ATTENTE_HEURES * 60 * 60 * 1000;

export interface AchatEnRetard {
  id:      string;
  type:    string;
  heures:  number;
  compte:  string;
}

/** Depuis combien d'heures, arrondi à l'unité inférieure. */
export function attenteEnHeures(depuis: Date, maintenant: Date): number {
  return Math.floor((maintenant.getTime() - depuis.getTime()) / 3_600_000);
}

/** Les preuves toujours en attente au-delà du seuil, la plus ancienne d'abord. */
export async function achatsEnRetard(maintenant = new Date()): Promise<AchatEnRetard[]> {
  const limite = new Date(maintenant.getTime() - INTERVALLE_CONTROLE_MS);

  const preuves = await prisma.subscriptionProof.findMany({
    where:   { status: 'pending', createdAt: { lt: limite } },
    orderBy: { createdAt: 'asc' },
    select: {
      id:        true,
      type:      true,
      createdAt: true,
      user:      { select: { pseudo: true, phoneNumber: true } },
    },
  });

  return preuves.map((p: any) => ({
    id:     p.id,
    type:   String(p.type),
    heures: attenteEnHeures(p.createdAt, maintenant),
    // Le pseudo suffit à retrouver la fiche ; à défaut le téléphone, qui est
    // l'identifiant que la personne a réellement utilisé pour payer.
    compte: p.user?.pseudo ?? p.user?.phoneNumber ?? p.id,
  }));
}

/** Le corps du courriel. Séparé pour être lisible dans un banc. */
export function corpsAlerte(retards: AchatEnRetard[]): string {
  const lignes = retards.map(
    (r) => `  · ${r.compte} — ${r.type} — en attente depuis ${r.heures} h`,
  );

  return [
    `${retards.length} achat(s) en attente depuis plus de ${SEUIL_ATTENTE_HEURES} h.`,
    '',
    ...lignes,
    '',
    'Ces personnes ont payé et attendent leur abonnement.',
    'Validation : https://pronowin.space/admin/abonnements',
  ].join('\n');
}

/**
 * Contrôle et alerte s'il y a lieu.
 *
 * Aucun courriel quand tout va bien : une alerte qui part tous les jours pour
 * dire que rien ne se passe cesse d'être lue au bout d'une semaine, et c'est
 * précisément celle du jour où quelque chose se passe qu'on n'ouvrira pas.
 */
export async function signalerAchatsEnRetard(
  maintenant = new Date(),
): Promise<{ enRetard: number; alerteEnvoyee: boolean }> {
  const retards = await achatsEnRetard(maintenant);
  if (retards.length === 0) return { enRetard: 0, alerteEnvoyee: false };

  const envoyee = await envoyerAlerteAdmin(
    `PronoWin — ${retards.length} achat(s) non activé(s)`,
    corpsAlerte(retards),
  );

  logger.warn(`[AchatsEnRetard] ${retards.length} en attente`, {
    comptes: retards.map((r) => r.compte),
  });

  return { enRetard: retards.length, alerteEnvoyee: envoyee };
}

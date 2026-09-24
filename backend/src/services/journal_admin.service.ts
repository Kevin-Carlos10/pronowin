import crypto from 'crypto';

import { prisma } from '../lib/prisma';
import type { ActeurAdmin } from '../utils/delegation_admin';

/**
 * Le journal des actions d'administration, chaîné par empreintes.
 *
 * Constats A3 et D02 de l'audit du 24 septembre 2026 : le journal était un
 * fichier JSON du panneau, modifiable par quiconque accède au serveur, borné à
 * 5 000 entrées, absent de la sauvegarde, et le nom de l'auteur y venait d'un
 * cookie que le navigateur pouvait réécrire.
 *
 * Ici :
 *  - l'auteur vient de la délégation signée par le panneau, jamais du corps de
 *    la requête ;
 *  - chaque entrée porte l'empreinte de la précédente. Modifier une ligne,
 *    en retirer une ou en glisser une entre deux : la chaîne casse, et
 *    `verifierChaine` dit où ;
 *  - l'écriture est sérialisée par un verrou de transaction PostgreSQL, faute
 *    de quoi deux entrées simultanées se réclameraient de la même précédente.
 *
 * Ce que la chaîne ne protège pas : quelqu'un qui réécrit toute la table et
 * recalcule toutes les empreintes. Elle rend une altération visible, pas
 * impossible — la sauvegarde quotidienne, qui garde 30 jours d'états
 * antérieurs, permet alors de comparer.
 */
export const ORIGINE = '0'.repeat(64);
/** Identifiant du verrou consultatif qui sérialise l'écriture. */
const VERROU = 724_000_001;

export interface EntreeJournal {
  action:  string;
  cible?:  string;
  details?: unknown;
  ip?:     string | null;
  horodatage?: Date;
}

/**
 * JSON à clés triées, à toute profondeur.
 *
 * PostgreSQL range les clés d'un `jsonb` dans son propre ordre : l'objet relu
 * n'est pas sérialisé comme l'objet écrit, et une empreinte calculée sur
 * `JSON.stringify` ne se recalculerait jamais à l'identique.
 */
function stable(v: unknown): string {
  if (v === null || typeof v !== 'object') return JSON.stringify(v ?? null);
  if (Array.isArray(v)) return '[' + v.map(stable).join(',') + ']';
  const o = v as Record<string, unknown>;
  return '{' + Object.keys(o).filter((k) => o[k] !== undefined).sort()
    .map((k) => JSON.stringify(k) + ':' + stable(o[k])).join(',') + '}';
}

/** La forme canonique d'une entrée, celle que l'empreinte couvre. */
function canonique(e: {
  horodatage: Date; action: string; cible: string; details: unknown;
  acteurId: string; acteurNom: string; acteurRole: string; ip: string | null;
}): string {
  return stable([
    e.horodatage.toISOString(), e.action, e.cible, e.details ?? null,
    e.acteurId, e.acteurNom, e.acteurRole, e.ip ?? null,
  ]);
}

export function empreinteEntree(precedente: string, contenu: string): string {
  return crypto.createHash('sha256').update(precedente).update('\n').update(contenu).digest('hex');
}

/** Ajoute une entrée au nom de [acteur]. */
export async function ajouterAuJournal(acteur: ActeurAdmin, e: EntreeJournal) {
  const ligne = {
    horodatage: e.horodatage ?? new Date(),
    action:     String(e.action).slice(0, 80),
    cible:      String(e.cible ?? '').slice(0, 300),
    // Passé par JSON avant tout : une date devient la chaîne que la base
    // rendra, et l'empreinte porte sur ce qui sera effectivement relu.
    details:    (e.details == null ? null : JSON.parse(JSON.stringify(e.details))) as any,
    acteurId:   acteur.id,
    acteurNom:  acteur.nom,
    acteurRole: acteur.role,
    ip:         e.ip ? String(e.ip).slice(0, 64) : null,
  };
  return prisma.$transaction(async (t) => {
    await t.$executeRaw`SELECT pg_advisory_xact_lock(${VERROU})`;
    const derniere = await t.journalAdmin.findFirst({ orderBy: { id: 'desc' }, select: { empreinte: true } });
    const precedente = derniere?.empreinte ?? ORIGINE;
    const empreinte = empreinteEntree(precedente, canonique(ligne));
    return t.journalAdmin.create({ data: { ...ligne, empreintePrecedente: precedente, empreinte } });
  // Les écritures attendent leur tour sur le verrou : une rafale d'actions
  // (un traitement par lot) ne doit pas échouer sur le délai par défaut de
  // Prisma, qui est de deux secondes.
  }, { maxWait: 15_000, timeout: 20_000 });
}

/**
 * Relit toute la chaîne, dans l'ordre, et recalcule chaque empreinte.
 * Rend le nombre d'entrées et, le cas échéant, la première rupture.
 */
export async function verifierChaine(lot = 1000) {
  let precedente = ORIGINE;
  let total = 0;
  let curseur = 0;
  for (;;) {
    const lignes = await prisma.journalAdmin.findMany({
      where: { id: { gt: curseur } }, orderBy: { id: 'asc' }, take: lot,
    });
    if (lignes.length === 0) break;
    for (const l of lignes) {
      const attendue = empreinteEntree(precedente, canonique({
        horodatage: l.horodatage, action: l.action, cible: l.cible, details: l.details,
        acteurId: l.acteurId, acteurNom: l.acteurNom, acteurRole: l.acteurRole, ip: l.ip,
      }));
      if (l.empreintePrecedente !== precedente || l.empreinte !== attendue) {
        return { ok: false, total, rupture: { id: l.id, horodatage: l.horodatage.toISOString(), action: l.action } };
      }
      precedente = l.empreinte;
      total++;
    }
    curseur = lignes[lignes.length - 1].id;
  }
  return { ok: true, total, rupture: null };
}

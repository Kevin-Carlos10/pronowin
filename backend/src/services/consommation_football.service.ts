import { prisma } from '../lib/prisma';
import { journal } from '../utils/logger';

/**
 * Ce que consomme le quota d'API-Football (plan Pro : 7 500 requêtes par jour).
 *
 * Le panneau ne voyait que le dernier « restant » relevé dans les en-têtes du
 * fournisseur : ni ce qui l'avait consommé, ni la tendance des jours passés.
 * Quand il s'épuise, les scores cessent de se mettre à jour, et l'on ne savait
 * pas quel écran ou quelle tâche couper.
 *
 * ── Deux comptes ─────────────────────────────────────────────────────────────
 *
 * - Ce serveur : chaque appel est compté au départ de la réponse, par jour et
 *   par famille (« /fixtures en direct », « /odds », « /players »…).
 * - Le fournisseur : la plus petite valeur restante relevée dans la journée.
 *   C'est son décompte qui fait foi ; l'écart avec le nôtre, ce sont des appels
 *   faits avec la même clé ailleurs (un poste de développement, par exemple).
 *
 * Le jour est celui de l'heure universelle : le fournisseur remet son compteur
 * à zéro à minuit UTC.
 *
 * ── Deux processus ───────────────────────────────────────────────────────────
 *
 * L'API et le processus des tâches appellent tous deux le fournisseur. Chacun
 * compte en mémoire et verse ses totaux en base chaque minute, par addition :
 * aucun ne lit puis réécrit le total de l'autre.
 */

const INTERVALLE_MS = 60_000;
const CONSERVATION_JOURS = 90;
const JOUR_MS = 86_400_000;

interface Compteur { appels: number; echecs: number }
interface ReleveQuota { jour: string; limite: number; restant: number; releveLe: Date }

let compteurs = new Map<string, Compteur>();
let quota: ReleveQuota | null = null;
let minuterie: NodeJS.Timeout | null = null;
let dernierepurge = '';

export const jourUtc = (d = new Date()) => d.toISOString().slice(0, 10);

/**
 * La famille d'un appel : son chemin, précisé pour `/fixtures`, qui sert à
 * quatre usages très différents en coût — le direct (toutes les minutes), le
 * détail d'un match, les matchs d'une date, le reste.
 */
export function familleDe(url?: string, params?: Record<string, unknown> | null): string {
  const [chemin, requete] = String(url ?? '').split('?');
  const p: Record<string, unknown> = { ...Object.fromEntries(new URLSearchParams(requete ?? '')), ...(params ?? {}) };
  const c = '/' + chemin.replace(/^https?:\/\/[^/]+/i, '').replace(/^\/+|\/+$/g, '').replace(/[^a-zA-Z0-9/_-]/g, '');
  if (c === '/fixtures') {
    if (p.live)           return '/fixtures?live';
    if (p.id || p.ids)    return '/fixtures?id';
    if (p.date || p.from) return '/fixtures?date';
  }
  return c.slice(0, 60);
}

/** Lit le quota dans les en-têtes d'une réponse du fournisseur. */
function lireQuota(entetes: Record<string, unknown> | undefined, maintenant: Date): ReleveQuota | null {
  const limite  = Number(entetes?.['x-ratelimit-requests-limit']);
  const restant = Number(entetes?.['x-ratelimit-requests-remaining']);
  if (!Number.isFinite(limite) || !Number.isFinite(restant) || limite <= 0) return null;
  return { jour: jourUtc(maintenant), limite, restant, releveLe: maintenant };
}

/**
 * Compte un appel au fournisseur. Ne lève jamais : le comptage ne doit pas
 * pouvoir faire échouer l'appel qu'il observe.
 */
export function compterAppel(
  config?: { url?: string; params?: any } | null,
  options: { echec?: boolean; entetes?: Record<string, unknown> } = {},
) {
  try {
    const maintenant = new Date();
    const cle = `${jourUtc(maintenant)}|${familleDe(config?.url, config?.params)}`;
    const c = compteurs.get(cle) ?? { appels: 0, echecs: 0 };
    c.appels++;
    if (options.echec) c.echecs++;
    compteurs.set(cle, c);

    const q = lireQuota(options.entetes, maintenant);
    // La plus petite valeur restante du jour ; un nouveau jour remplace l'ancien.
    if (q && (!quota || q.jour > quota.jour || (q.jour === quota.jour && q.restant <= quota.restant))) quota = q;

    demarrer();
  } catch { /* rien : voir plus haut */ }
}

function demarrer() {
  // Les bancs d'essai versent eux-mêmes, quand ils le veulent.
  if (minuterie || process.env.JEST_WORKER_ID) return;
  minuterie = setInterval(() => { void verserCompteurs(); }, INTERVALLE_MS);
  minuterie.unref();
}

/**
 * Verse les totaux en mémoire dans la base, par addition.
 *
 * Une ligne versée sort du lot aussitôt : si la base tombe en cours de route,
 * seules les lignes restantes sont remises en mémoire, et rien n'est compté
 * deux fois.
 */
export async function verserCompteurs(): Promise<void> {
  const lot = compteurs;
  compteurs = new Map();
  const q = quota;
  quota = null;
  try {
    for (const [cle, c] of [...lot]) {
      const [jour, famille] = cle.split('|');
      await prisma.$executeRaw`
        INSERT INTO "consommation_football" ("jour", "famille", "appels", "echecs")
        VALUES (${jour}, ${famille}, ${c.appels}, ${c.echecs})
        ON CONFLICT ("jour", "famille") DO UPDATE SET
          "appels" = "consommation_football"."appels" + EXCLUDED."appels",
          "echecs" = "consommation_football"."echecs" + EXCLUDED."echecs"`;
      lot.delete(cle);
    }
    if (q) {
      await prisma.$executeRaw`
        INSERT INTO "quota_football_jours" ("jour", "limite", "restant_min", "releve_le")
        VALUES (${q.jour}, ${q.limite}, ${q.restant}, ${q.releveLe})
        ON CONFLICT ("jour") DO UPDATE SET
          "limite"      = EXCLUDED."limite",
          "restant_min" = LEAST("quota_football_jours"."restant_min", EXCLUDED."restant_min"),
          "releve_le"   = GREATEST("quota_football_jours"."releve_le", EXCLUDED."releve_le")`;
    }
    const aujourdhui = jourUtc();
    if (dernierepurge !== aujourdhui) {
      const seuil = jourUtc(new Date(Date.now() - CONSERVATION_JOURS * JOUR_MS));
      await prisma.$executeRaw`DELETE FROM "consommation_football" WHERE "jour" < ${seuil}`;
      await prisma.$executeRaw`DELETE FROM "quota_football_jours" WHERE "jour" < ${seuil}`;
      dernierepurge = aujourdhui;
    }
  } catch (e: any) {
    for (const [cle, c] of lot) {
      const d = compteurs.get(cle) ?? { appels: 0, echecs: 0 };
      compteurs.set(cle, { appels: d.appels + c.appels, echecs: d.echecs + c.echecs });
    }
    if (q && !quota) quota = q;
    journal.warn('[football] consommation non versée, nouvel essai dans une minute :', e?.message);
  }
}

/** Pour les bancs d'essai. */
export function _reinitialiserConsommation() {
  compteurs = new Map();
  quota = null;
  dernierepurge = '';
  if (minuterie) clearInterval(minuterie);
  minuterie = null;
}

// ─── Lecture pour le panneau ─────────────────────────────────────────────────

export interface LigneConso { jour: string; famille: string; appels: number; echecs: number }
export interface LigneQuota { jour: string; limite: number; restantMin: number; releveLe: Date }

const parFamille = (lignes: LigneConso[]) => {
  const m = new Map<string, { famille: string; appels: number; echecs: number }>();
  for (const l of lignes) {
    const f = m.get(l.famille) ?? { famille: l.famille, appels: 0, echecs: 0 };
    f.appels += l.appels; f.echecs += l.echecs;
    m.set(l.famille, f);
  }
  const total = [...m.values()].reduce((s, f) => s + f.appels, 0);
  return [...m.values()]
    .map((f) => ({ ...f, part: total ? Math.round((f.appels / total) * 1000) / 10 : 0 }))
    .sort((a, b) => b.appels - a.appels || a.famille.localeCompare(b.famille));
};

export function analyserConsommation(lignes: LigneConso[], quotas: LigneQuota[], maintenant = new Date()) {
  const aujourdhui = jourUtc(maintenant);
  const debutJour = Date.parse(aujourdhui + 'T00:00:00Z');

  const jours = Array.from({ length: 30 }, (_, i) => {
    const jour = jourUtc(new Date(debutJour - (29 - i) * JOUR_MS));
    const dujour = lignes.filter((l) => l.jour === jour);
    const q = quotas.find((x) => x.jour === jour);
    return {
      jour,
      serveur:     dujour.reduce((s, l) => s + l.appels, 0),
      echecs:      dujour.reduce((s, l) => s + l.echecs, 0),
      fournisseur: q ? Math.max(0, q.limite - q.restantMin) : null,
      limite:      q?.limite ?? null,
      // Aucun appel compté ni aucun relevé : le comptage n'existait pas encore.
      mesure:      dujour.length > 0 || !!q,
    };
  });

  const j = jours[jours.length - 1];
  const qJour = quotas.find((x) => x.jour === aujourdhui);
  const utilise = j.fournisseur ?? j.serveur;
  // Rythme depuis minuit UTC, prolongé jusqu'à la fin du jour. Avant une
  // heure écoulée, trop tôt pour en tirer quoi que ce soit.
  const ecoule = (maintenant.getTime() - debutJour) / JOUR_MS;
  const projection = ecoule >= 1 / 24 ? Math.round(utilise / ecoule) : null;

  const precedents = jours.slice(0, -1).filter((x) => x.mesure).slice(-7);
  const moyenne7j = precedents.length
    ? Math.round(precedents.reduce((s, x) => s + (x.fournisseur ?? x.serveur), 0) / precedents.length)
    : null;

  const septJours = jours.slice(-7).map((x) => x.jour);
  return {
    aujourdhui: {
      jour:        aujourdhui,
      serveur:     j.serveur,
      echecs:      j.echecs,
      fournisseur: j.fournisseur,
      limite:      qJour?.limite ?? null,
      restant:     qJour?.restantMin ?? null,
      releveLe:    qJour?.releveLe.toISOString() ?? null,
      // Appels comptés par le fournisseur, pas par ce serveur : la même clé
      // sert ailleurs.
      horsServeur: j.fournisseur !== null ? Math.max(0, j.fournisseur - j.serveur) : null,
      projection,
      remiseAZero: new Date(debutJour + JOUR_MS).toISOString(),
    },
    moyenne7j,
    jours,
    familles: {
      aujourdhui: parFamille(lignes.filter((l) => l.jour === aujourdhui)),
      septJours:  parFamille(lignes.filter((l) => septJours.includes(l.jour))),
    },
  };
}

export async function resumeConsommation() {
  // Les appels de ce processus qui attendent leur versement comptent aussi.
  await verserCompteurs();
  const depuis = jourUtc(new Date(Date.now() - 30 * JOUR_MS));
  const [lignes, quotas] = await Promise.all([
    prisma.consommationFootball.findMany({ where: { jour: { gte: depuis } } }),
    prisma.quotaFootballJour.findMany({ where: { jour: { gte: depuis } } }),
  ]);
  return analyserConsommation(lignes, quotas);
}

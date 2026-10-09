import { prisma } from '../lib/prisma';
import { comparerVersions, lireConfig } from './app_config.service';

/**
 * Quelle version de l'application chaque membre utilise-t-il ?
 *
 * Le serveur l'ignorait. Le panneau ne pouvait donc pas dire combien de
 * membres restaient sur une version ancienne — et relever la version minimale
 * se faisait à l'aveugle, au risque de bloquer d'un coup tous ceux qui
 * n'avaient pas fait la mise à jour.
 *
 * Depuis la 1.0.18, l'application envoie `X-App-Version`, `X-App-Build`,
 * `X-App-Plateforme` et `X-App-Canal` avec chaque requête vers l'API. Un
 * membre actif qui n'en envoie pas utilise donc la 1.0.17 ou une plus
 * ancienne : il est compté comme tel, pas ignoré.
 */

/** Au plus une écriture par membre dans cette fenêtre, sauf changement de version. */
const FENETRE_MS = 6 * 60 * 60 * 1000;
const MEMOIRE_MAX = 50_000;

export const VERSION_PREMIERE_DECLAREE = '1.0.18';
/** La dernière qui ne déclare rien : un membre muet l'utilise, ou une plus ancienne. */
export const VERSION_MUETTE = '1.0.17';

export interface VersionDeclaree {
  version:    string;
  build:      number | null;
  plateforme: 'ios' | 'android' | 'web' | 'autre';
  canal:      'store' | 'direct' | null;
}

const PLATEFORMES = ['ios', 'android', 'web', 'autre'] as const;

/** Lit les en-têtes `X-App-*`. `null` si la version manque ou n'a pas la forme attendue. */
export function lireVersionApp(entetes: Record<string, unknown> | undefined): VersionDeclaree | null {
  const brut = (n: string) => {
    const v = entetes?.[n];
    return typeof v === 'string' ? v.trim() : Array.isArray(v) && typeof v[0] === 'string' ? v[0].trim() : '';
  };
  const version = brut('x-app-version');
  if (!/^\d{1,4}(\.\d{1,4}){1,3}$/.test(version)) return null;
  const build = /^\d{1,7}$/.test(brut('x-app-build')) ? parseInt(brut('x-app-build'), 10) : null;
  const p = brut('x-app-plateforme').toLowerCase();
  const c = brut('x-app-canal').toLowerCase();
  return {
    version,
    build,
    plateforme: (PLATEFORMES as readonly string[]).includes(p) ? p as VersionDeclaree['plateforme'] : 'autre',
    canal:      c === 'store' || c === 'direct' ? c : null,
  };
}

const dejaNote = new Map<string, { cle: string; le: number }>();

/**
 * Retient la version d'un membre. Sans attendre, et sans jamais lever : rien
 * ici ne doit retarder ni faire échouer la requête.
 */
export function noterVersionApp(userId: string, entetes: Record<string, unknown> | undefined) {
  try {
    const v = lireVersionApp(entetes);
    if (!v) return;
    const cle = `${v.version}|${v.build ?? ''}|${v.plateforme}|${v.canal ?? ''}`;
    const avant = dejaNote.get(userId);
    const maintenant = Date.now();
    if (avant && avant.cle === cle && maintenant - avant.le < FENETRE_MS) return;
    if (dejaNote.size >= MEMOIRE_MAX) dejaNote.clear();
    dejaNote.set(userId, { cle, le: maintenant });
    const donnees = { version: v.version, build: v.build, plateforme: v.plateforme, canal: v.canal, vuLe: new Date(maintenant) };
    prisma.versionAppCompte.upsert({
      where:  { userId },
      update: donnees,
      create: { userId, ...donnees },
    }).catch(() => { dejaNote.delete(userId); });
  } catch { /* voir plus haut */ }
}

/** Pour les bancs d'essai. */
export function _oublierVersions() { dejaNote.clear(); }

// ─── Lecture pour le panneau ─────────────────────────────────────────────────

export interface MembreActif { id: string; pseudo: string; premium: boolean; vuLe: Date }
export interface VersionVue  { userId: string; version: string; build: number | null; plateforme: string; canal: string | null; vuLe: Date }

/** La famille de distribution : la version de référence n'est pas la même partout. */
export const familleDistribution = (plateforme: string, canal: string | null) =>
  plateforme === 'ios' ? 'ios' : plateforme === 'android' ? (canal === 'direct' ? 'apk' : 'play') : 'autre';

export function analyserVersions(
  membres: MembreActif[],
  versions: VersionVue[],
  reference: { store: string; apk: string },
) {
  const parCompte = new Map(versions.map((v) => [v.userId, v]));

  // La version de référence de chaque famille : la plus haute entre la
  // configuration et ce que les membres utilisent déjà. Une configuration
  // jamais tenue à jour ne doit pas faire passer tout le monde pour à jour.
  const plusHaute = (a: string, b: string) => (comparerVersions(a, b) >= 0 ? a : b);
  const ref: Record<string, string> = { ios: reference.store, play: reference.store, apk: reference.apk };
  for (const v of versions) {
    const f = familleDistribution(v.plateforme, v.canal);
    if (f in ref) ref[f] = plusHaute(ref[f], v.version);
  }

  const groupes = new Map<string, { version: string; plateforme: string; canal: string | null; famille: string;
                                     membres: number; premium: number; aJour: boolean }>();
  const enRetard: Array<{ userId: string; pseudo: string; premium: boolean; version: string; famille: string; vuLe: string }> = [];
  let inconnus = 0, inconnusPremium = 0, aJour = 0;

  for (const m of membres) {
    const v = parCompte.get(m.id);
    if (!v) {
      inconnus++;
      if (m.premium) inconnusPremium++;
      continue;
    }
    const famille = familleDistribution(v.plateforme, v.canal);
    const aJourIci = !(famille in ref) || comparerVersions(v.version, ref[famille]) >= 0;
    if (aJourIci) aJour++;
    else enRetard.push({ userId: m.id, pseudo: m.pseudo, premium: m.premium, version: v.version,
                         famille, vuLe: m.vuLe.toISOString() });
    const cle = `${v.version}|${famille}`;
    const g = groupes.get(cle) ?? { version: v.version, plateforme: v.plateforme, canal: v.canal, famille,
                                    membres: 0, premium: 0, aJour: aJourIci };
    g.membres++;
    if (m.premium) g.premium++;
    groupes.set(cle, g);
  }

  const total = membres.length;
  const part = (n: number) => (total ? Math.round((n / total) * 1000) / 10 : 0);
  return {
    actifs: total,
    aJour,
    enRetard: enRetard.length,
    // Compté sur tous, pas sur la liste tronquée plus bas.
    enRetardPremium: enRetard.filter((m) => m.premium).length,
    inconnus,
    inconnusPremium,
    references: ref,
    versions: [...groupes.values()]
      .map((g) => ({ ...g, part: part(g.membres) }))
      .sort((a, b) => comparerVersions(b.version, a.version) || b.membres - a.membres),
    // Les Premium d'abord : ce sont eux qu'une version minimale relevée
    // couperait de ce qu'ils ont payé.
    listeEnRetard: enRetard
      .sort((a, b) => Number(b.premium) - Number(a.premium) || comparerVersions(a.version, b.version)
        || b.vuLe.localeCompare(a.vuLe))
      .slice(0, 200),
  };
}

export async function resumeVersions(params: { jours?: number } = {}) {
  const jours = [7, 30, 90].includes(params.jours ?? 0) ? params.jours! : 30;
  const depuis = new Date(Date.now() - jours * 86_400_000);
  const maintenant = new Date();
  const [users, versions, config] = await Promise.all([
    prisma.user.findMany({
      where:  { lastSeenAt: { gte: depuis }, deletedAt: null },
      select: { id: true, pseudo: true, subscriptionPlan: true, subscriptionExpiresAt: true, lastSeenAt: true },
    }),
    prisma.versionAppCompte.findMany(),
    lireConfig(),
  ]);
  const membres: MembreActif[] = users.map((u) => ({
    id: u.id, pseudo: u.pseudo, vuLe: u.lastSeenAt!,
    premium: u.subscriptionPlan === 'premium' && (!u.subscriptionExpiresAt || u.subscriptionExpiresAt > maintenant),
  }));
  const reference = { store: config.valeurs.APP_LATEST_VERSION, apk: config.valeurs.APK_LATEST_VERSION };
  return {
    jours,
    premiereVersionDeclaree: VERSION_PREMIERE_DECLAREE,
    versionMuette: VERSION_MUETTE,
    configuration: {
      store: { min: config.valeurs.APP_MIN_VERSION, derniere: config.valeurs.APP_LATEST_VERSION },
      apk:   { min: config.valeurs.APK_MIN_VERSION, derniere: config.valeurs.APK_LATEST_VERSION },
    },
    ...analyserVersions(membres, versions, reference),
  };
}

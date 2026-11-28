/**
 * Ce que font les tâches de fond, pour qui doit le savoir.
 *
 * Aucune n'était visible : la synchronisation des scores, les rappels
 * d'expiration, l'alerte d'achats et la file des notifications de store
 * tournaient ou échouaient sans que le tableau de bord en dise rien. Le compte
 * de service est ainsi resté en échec des semaines sans que personne ne le
 * voie (constats A7 et I6 de l'audit du 24 septembre 2026).
 *
 * Chaque tâche note ici sa dernière exécution ; la route `/admin/sante` le
 * rend au panneau. L'état vit en mémoire : il repart à zéro au redémarrage,
 * ce que la réponse dit (`demarreLe`).
 */
export interface EtatTache {
  derniereReussite: string | null;
  dernierEchec:     string | null;
  derniereErreur:   string | null;
  dureeMs:          number | null;
  detail:           string | null;
}

const taches = new Map<string, EtatTache>();
const demarreLe = new Date().toISOString();

let quota: { limite: number; restant: number; releveLe: string } | null = null;

/** Exécute [travail] en notant son issue sous [nom]. L'erreur est relancée. */
export async function suivre<T>(nom: string, travail: () => Promise<T>, detail?: (r: T) => string): Promise<T> {
  const debut = Date.now();
  const e = taches.get(nom) ?? {
    derniereReussite: null, dernierEchec: null, derniereErreur: null, dureeMs: null, detail: null,
  };
  try {
    const r = await travail();
    taches.set(nom, { ...e, derniereReussite: new Date().toISOString(), dureeMs: Date.now() - debut,
                      detail: detail ? detail(r) : e.detail });
    void publierMaintenant();
    return r;
  } catch (err: any) {
    taches.set(nom, { ...e, dernierEchec: new Date().toISOString(), dureeMs: Date.now() - debut,
                      derniereErreur: String(err?.message ?? err).slice(0, 200) });
    void publierMaintenant();
    throw err;
  }
}

/**
 * Le quota du fournisseur de données football, lu dans les en-têtes de ses
 * réponses (`x-ratelimit-requests-*`). Quand il s'épuise, les résultats
 * cessent de se mettre à jour : il faut le voir avant.
 */
export function noterQuota(entetes: Record<string, unknown> | undefined) {
  const limite  = Number(entetes?.['x-ratelimit-requests-limit']);
  const restant = Number(entetes?.['x-ratelimit-requests-remaining']);
  if (Number.isFinite(limite) && Number.isFinite(restant) && limite > 0) {
    quota = { limite, restant, releveLe: new Date().toISOString() };
  }
}

export function etatDesTaches() {
  return {
    demarreLe,
    taches: Object.fromEntries(taches),
    quotaFootball: quota,
  };
}

/** Pour les bancs d'essai. */
export function _reinitialiser() { taches.clear(); quota = null; }

// ─── Processus des tâches séparé (constat P1) ────────────────────────────────
//
// Cet état vit dans la mémoire du processus qui exécute les tâches. Quand ce
// n'est plus l'API, la page Santé du panneau — servie par l'API — ne le
// verrait plus : le processus des tâches le publie donc en base après chaque
// exécution, et la santé le relit.

/** L'API lance-t-elle les tâches ? Non quand un processus dédié s'en charge. */
export function tachesDansLApi(env: NodeJS.ProcessEnv = process.env): boolean {
  return env.TACHES_SEPAREES !== '1';
}

/** La ligne de `app_settings` où l'état est publié. */
export const CLE_ETAT_PUBLIE = '_etat_taches';
/** Au-delà, un processus des tâches muet est signalé : la file des stores
 *  tourne chaque minute, et publie à chaque fois. */
export const SILENCE_MAX_MS = 10 * 60 * 1000;

let publier = false;

/** À appeler par le processus des tâches, et par lui seul. */
export function publierEtat(actif = true) { publier = actif; }

async function publierMaintenant(): Promise<void> {
  if (!publier) return;
  try {
    // Chargé ici : l'API n'en a pas besoin, et certains bancs n'ont pas de base.
    const { prisma } = await import('../lib/prisma');
    const valeur = JSON.stringify(etatDesTaches());
    await prisma.appSetting.upsert({
      where:  { key: CLE_ETAT_PUBLIE },
      update: { value: valeur, updatedBy: 'pronowin-taches' },
      create: { key: CLE_ETAT_PUBLIE, value: valeur, updatedBy: 'pronowin-taches' },
    });
  } catch { /* la santé le dira : l'état publié vieillira */ }
}

/** L'état publié par le processus des tâches, et quand il l'a été. */
export async function lireEtatPublie(): Promise<
  (ReturnType<typeof etatDesTaches> & { publieLe: string }) | null> {
  try {
    const { prisma } = await import('../lib/prisma');
    const ligne = await prisma.appSetting.findUnique({ where: { key: CLE_ETAT_PUBLIE } });
    if (!ligne) return null;
    return { ...JSON.parse(ligne.value), publieLe: ligne.updatedAt.toISOString() };
  } catch {
    return null;
  }
}

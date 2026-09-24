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
    return r;
  } catch (err: any) {
    taches.set(nom, { ...e, dernierEchec: new Date().toISOString(), dureeMs: Date.now() - debut,
                      derniereErreur: String(err?.message ?? err).slice(0, 200) });
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

import { etatDesTaches } from './etat_taches';

/** Cache borné par processus, avec dédoublonnage des appels en cours.
 * Les erreurs HTTP et les erreurs fournisseur ne sont jamais des données vides.
 * Un échec conserve brièvement la dernière réponse et impose un délai de reprise.
 */
export interface Releve<T> { data: T | null; updatedAt: string | null; stale: boolean; }
export class CacheFootball<T> {
  private cache = new Map<string, Releve<T> & { expires: number; failures: number }>();
  private pending = new Map<string, Promise<Releve<T>>>();
  constructor(private max = 256, private staleMaxMs = 5 * 60_000) {}

  async read(key: string, ttl: number, fetch: () => Promise<T>): Promise<Releve<T>> {
    const hit = this.cache.get(key);
    const usable = (r: Releve<T>): Releve<T> => r.stale &&
      (!r.updatedAt || Date.now() - Date.parse(r.updatedAt) > this.staleMaxMs)
        ? { data: null, updatedAt: r.updatedAt, stale: true } : r;
    if (hit && hit.expires > Date.now()) return usable(hit);
    const pending = this.pending.get(key);
    if (pending) return pending;
    const work = (async () => {
      let value: Releve<T> & { expires: number; failures: number };
      try {
        const data = await fetch();
        value = { data, updatedAt: new Date().toISOString(), stale: false,
          expires: Date.now() + ttl, failures: 0 };
      } catch (_) {
        const failures = Math.min((hit?.failures ?? 0) + 1, 3);
        value = { ...usable(hit ?? { data: null, updatedAt: null, stale: true }),
          stale: true, failures, expires: Date.now() + 30_000 * 2 ** (failures - 1) };
      }
      this.cache.delete(key);
      this.cache.set(key, value);
      while (this.cache.size > this.max) this.cache.delete(this.cache.keys().next().value!);
      return usable(value);
    })();
    this.pending.set(key, work);
    try { return await work; } finally { this.pending.delete(key); }
  }
}

/** API-Sports peut répondre HTTP 200 avec une erreur de quota dans le corps. */
export function responseFootball(body: any): any[] {
  if (body?.errors && Object.keys(body.errors).length > 0) throw new Error('Football provider error');
  if (!Array.isArray(body?.response)) throw new Error('Invalid football response');
  return body.response;
}

/** Préserve les derniers 10 % pour le score principal et les tâches métier.
 * Le quota est celui reçu du fournisseur, pas celui supposé d'un abonnement.
 * Un relevé de la veille ne doit pas bloquer le jour suivant (reset UTC).
 */
export function exigerQuotaEnrichissement(): void {
  const quota = etatDesTaches().quotaFootball;
  if (quota && quota.releveLe.slice(0, 10) === new Date().toISOString().slice(0, 10) &&
      quota.restant <= Math.max(10, Math.ceil(quota.limite * 0.1))) {
    throw new Error('Football enrichment paused: quota reserve');
  }
}

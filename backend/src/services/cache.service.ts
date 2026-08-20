/**
 * Cache en mémoire simple avec TTL.
 * Évite les requêtes Prisma répétées pour des données qui changent peu.
 *
 * Usage:
 *   cache.set('key', data, 60);          // TTL 60 secondes
 *   const v = cache.get<MyType>('key');  // null si expiré / absent
 *   cache.del('key');                    // invalider manuellement
 */

interface CacheEntry<T> {
  value:     T;
  expiresAt: number;  // timestamp ms
}

class CacheService {
  private store = new Map<string, CacheEntry<unknown>>();

  /** Stocker une valeur avec TTL en secondes. */
  set<T>(key: string, value: T, ttlSeconds: number): void {
    this.store.set(key, {
      value,
      expiresAt: Date.now() + ttlSeconds * 1000,
    });
  }

  /** Récupérer une valeur. Retourne null si absente ou expirée. */
  get<T>(key: string): T | null {
    const entry = this.store.get(key);
    if (!entry) return null;
    if (Date.now() > entry.expiresAt) {
      this.store.delete(key);
      return null;
    }
    return entry.value as T;
  }

  /** Invalider une clé ou un préfixe. */
  del(key: string): void {
    // Suppression exacte
    if (this.store.has(key)) {
      this.store.delete(key);
      return;
    }
    // Suppression par préfixe (ex: del('pronostics:') supprime toutes les clés)
    for (const k of this.store.keys()) {
      if (k.startsWith(key)) this.store.delete(k);
    }
  }

  /** Nombre d'entrées vivantes. */
  size(): number {
    const now = Date.now();
    let count = 0;
    for (const [k, e] of this.store) {
      if (now > e.expiresAt) this.store.delete(k);
      else count++;
    }
    return count;
  }

  /**
   * Vider entièrement le cache.
   *
   * Indispensable pour isoler les tests les uns des autres — le cache est un
   * singleton de module, donc une entrée laissée par un test fausserait le
   * suivant. Utile aussi en exploitation après un changement de tarif ou de
   * visibilité de ligue, pour ne pas attendre l'expiration.
   */
  clear(): void {
    this.store.clear();
  }

  /** Purger toutes les entrées expirées (à appeler périodiquement si le cache grossit). */
  purgeExpired(): void {
    const now = Date.now();
    for (const [k, e] of this.store) {
      if (now > e.expiresAt) this.store.delete(k);
    }
  }
}

// Singleton partagé entre tous les modules
export const cache = new CacheService();

// Purge automatique toutes les 10 minutes pour éviter les fuites mémoire.
// `unref()` : ce minuteur ne doit pas maintenir le process en vie à lui seul —
// il empêchait Jest de rendre la main en fin de suite, et retarderait tout
// autant un arrêt propre du serveur.
setInterval(() => cache.purgeExpired(), 10 * 60 * 1000).unref();

// ── Clés de cache standardisées ──────────────────────────────────────────────
export const CACHE_KEYS = {
  pronostics:   (params: string) => `pronostics:${params}`,  // TTL 60s
  dayCounts:    'pronostics:day-counts',                     // TTL 2min
  daySummary:   (dateFilter: string) => `pronostics:day-summary:${dateFilter}`, // TTL 60s
  publicStats:  'stats:public',                              // TTL 5min
  adminStats:   'stats:admin',                               // TTL 5min
  actualites:   'actualites:published',                      // TTL 2min
  leaderboard:  (period: string) => `leaderboard:${period}`, // TTL 2min
  bilanPremium: (days: number) => `pronostics:bilan-premium:${days}`, // TTL 5min
};

export const CACHE_TTL = {
  pronostics:  60,        // 60 secondes
  dayCounts:   2 * 60,    // 2 minutes
  daySummary:  60,        // 60 secondes
  stats:       5 * 60,    // 5 minutes
  actualites:  2 * 60,    // 2 minutes
  leaderboard: 2 * 60,    // 2 minutes — classement, pas besoin d'être temps réel
};

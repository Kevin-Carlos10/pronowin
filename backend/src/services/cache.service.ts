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

// Purge automatique toutes les 10 minutes pour éviter les fuites mémoire
setInterval(() => cache.purgeExpired(), 10 * 60 * 1000);

// ── Clés de cache standardisées ──────────────────────────────────────────────
export const CACHE_KEYS = {
  pronostics:  (params: string) => `pronostics:${params}`,   // TTL 60s
  publicStats: 'stats:public',                               // TTL 5min
  adminStats:  'stats:admin',                                // TTL 5min
  actualites:  'actualites:published',                       // TTL 2min
};

export const CACHE_TTL = {
  pronostics:  60,        // 60 secondes
  stats:       5 * 60,    // 5 minutes
  actualites:  2 * 60,    // 2 minutes
};

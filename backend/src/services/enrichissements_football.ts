import type { AxiosInstance } from 'axios';
import { CacheFootball, responseFootball, exigerQuotaEnrichissement, Releve } from './cache_football';

/** Réponses partagées entre fiches et matchs, bornées, validées et dédoublonnées.
 * Une réponse périmée n'est jamais présentée comme une réponse fraîche par get(). */
export class EnrichissementsFootball {
  private cache = new CacheFootball<any[]>(2000, 60 * 60_000);
  private objects = new CacheFootball<Record<string, any>>(256);
  constructor(private client: AxiosInstance) {}
  read(path: string, params: Record<string, string | number>, ttl: number): Promise<Releve<any[]>> {
    const key = path + ':' + JSON.stringify(Object.entries(params).sort(([a], [b]) => a.localeCompare(b)));
    return this.cache.read(key, ttl, async () => {
      exigerQuotaEnrichissement();
      const r = await this.client.get(path, { params });
      return responseFootball(r.data);
    });
  }
  async get(path: string, params: Record<string, string | number>, ttl: number): Promise<any[]> {
    const r = await this.read(path, params, ttl);
    if (r.data === null || r.stale) throw new Error('Football data temporarily unavailable');
    return r.data;
  }
  async object(path: string, params: Record<string, string | number>, ttl: number): Promise<Record<string, any>> {
    const key = path + ':' + JSON.stringify(Object.entries(params).sort(([a], [b]) => a.localeCompare(b)));
    const r = await this.objects.read(key, ttl, async () => {
      exigerQuotaEnrichissement();
      const response = await this.client.get(path, { params });
      const body = response.data;
      if (body?.errors && Object.keys(body.errors).length) throw new Error('Football provider error');
      if (!body?.response || typeof body.response !== 'object' || Array.isArray(body.response)) throw new Error('Invalid football response');
      return body.response;
    });
    if (r.data === null || r.stale) throw new Error('Football data temporarily unavailable');
    return r.data;
  }
  async season(league: number, year: number): Promise<any | null> {
    const data = await this.get('/leagues', { id: league }, 24 * 60 * 60_000);
    return data.find(l => l.league?.id === league)?.seasons?.find((s: any) => s.year === year) ?? null;
  }
}
const instances = new WeakMap<AxiosInstance, EnrichissementsFootball>();
export function enrichissementsFootball(client: AxiosInstance): EnrichissementsFootball {
  let instance = instances.get(client);
  if (!instance) { instance = new EnrichissementsFootball(client); instances.set(client, instance); }
  return instance;
}

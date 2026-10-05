import type { AxiosInstance } from 'axios';
import { journal } from '../utils/logger';

/**
 * La fiche d'une équipe : le club, son stade, son entraîneur, son effectif.
 *
 * Trois routes d'API-Football que l'application ne lisait pas (/teams,
 * /coachs, /players/squads). Le bilan de la saison vient de
 * /teams/statistics, déjà lu pour l'analyse d'un match et gardé en cache par
 * `ApiFootballInsights`.
 *
 * Données stables : gardées vingt-quatre heures, trois requêtes par équipe et
 * par jour au plus, quel que soit le nombre de visiteurs.
 */

export interface JoueurEffectif {
  id:       number | null;
  name:     string;
  age:      number | null;
  number:   number | null;
  /** Goalkeeper, Defender, Midfielder, Attacker — tel que l'API le donne. */
  position: string | null;
  photo:    string | null;
}

export interface FicheEquipe {
  id:       number;
  name:     string;
  country:  string | null;
  founded:  number | null;
  logo:     string | null;
  venue: {
    name:     string | null;
    city:     string | null;
    capacity: number | null;
    image:    string | null;
  } | null;
  coach: {
    id:          number | null;
    name:        string;
    age:         number | null;
    nationality: string | null;
    photo:       string | null;
  } | null;
  squad: JoueurEffectif[];
}

const FICHE_TTL = 24 * 60 * 60 * 1000;
const FICHES_MAX = 1000;
const cache = new Map<number, { data: FicheEquipe | 'introuvable'; ts: number }>();

const ORDRE_POSTES: Record<string, number> = { Goalkeeper: 0, Defender: 1, Midfielder: 2, Attacker: 3 };

/** L'entraîneur actuel : celui dont la carrière dans ce club n'a pas de fin. */
export function entraineurActuel(coachs: any[], teamId: number): any | null {
  const enPoste = coachs.filter((c) =>
    (c?.career ?? []).some((p: any) => p?.team?.id === teamId && !p?.end));
  if (enPoste.length) return enPoste[0];
  // Sans carrière exploitable, l'API classe en général l'actuel en premier.
  return coachs[0] ?? null;
}

export class FichesEquipes {
  constructor(
    private readonly client: AxiosInstance,
    private readonly hasKey: () => boolean,
  ) {}

  /** La fiche, `'introuvable'` si l'API ne connaît pas l'équipe, `null` en panne. */
  async fiche(teamId: number): Promise<FicheEquipe | 'introuvable' | null> {
    if (!this.hasKey()) return null;

    const hit = cache.get(teamId);
    if (hit && Date.now() - hit.ts < FICHE_TTL) return hit.data;

    try {
      const r = await this.client.get('/teams', { params: { id: teamId } });
      const t = r.data?.response?.[0];
      if (!t?.team) {
        this.garder(teamId, 'introuvable');
        return 'introuvable';
      }

      const [coachs, effectif] = await Promise.all([
        this.client.get('/coachs', { params: { team: teamId } })
          .then((x) => x.data?.response ?? [])
          .catch((e) => { journal.error('[ApiFootball] /coachs indisponible:', e.message); return []; }),
        this.client.get('/players/squads', { params: { team: teamId } })
          .then((x) => x.data?.response?.[0]?.players ?? [])
          .catch((e) => { journal.error('[ApiFootball] /players/squads indisponible:', e.message); return []; }),
      ]);

      const c = entraineurActuel(coachs, teamId);
      const fiche: FicheEquipe = {
        id:      t.team.id ?? teamId,
        name:    t.team.name ?? '',
        country: t.team.country ?? null,
        founded: typeof t.team.founded === 'number' ? t.team.founded : null,
        logo:    t.team.logo ?? null,
        venue: t.venue?.name ? {
          name:     t.venue.name ?? null,
          city:     t.venue.city ?? null,
          capacity: typeof t.venue.capacity === 'number' ? t.venue.capacity : null,
          image:    t.venue.image ?? null,
        } : null,
        coach: c ? {
          id:          c.id ?? null,
          name:        c.name ?? '',
          age:         typeof c.age === 'number' ? c.age : null,
          nationality: c.nationality ?? null,
          photo:       c.photo ?? null,
        } : null,
        squad: (effectif as any[])
          .map((p) => ({
            id:       p?.id ?? null,
            name:     p?.name ?? '',
            age:      typeof p?.age === 'number' ? p.age : null,
            number:   typeof p?.number === 'number' ? p.number : null,
            position: p?.position ?? null,
            photo:    p?.photo ?? null,
          }))
          .sort((a, b) =>
            (ORDRE_POSTES[a.position ?? ''] ?? 9) - (ORDRE_POSTES[b.position ?? ''] ?? 9)
            || (a.number ?? 999) - (b.number ?? 999)),
      };
      this.garder(teamId, fiche);
      return fiche;
    } catch (e) {
      journal.error('[ApiFootball] fiche équipe indisponible:', (e as Error).message);
      return null;
    }
  }

  private garder(teamId: number, data: FicheEquipe | 'introuvable') {
    if (cache.size >= FICHES_MAX) {
      const plusAncienne = cache.keys().next().value;
      if (plusAncienne !== undefined) cache.delete(plusAncienne);
    }
    cache.set(teamId, { data, ts: Date.now() });
  }
}

import type { AxiosInstance } from 'axios';
import { prisma } from '../lib/prisma';
import { enrichissementsFootball } from './enrichissements_football';
import { RECHERCHE_MAX } from './recherche_matchs';
import { journal } from '../utils/logger';

/**
 * Chercher une équipe ou un joueur, pas seulement un match (7 novembre 2026).
 *
 * La recherche de l'application ne trouvait que des matchs et des
 * compétitions ; Sofascore et FotMob trouvent aussi les équipes et les
 * joueurs, et ouvrent leur fiche — fiches que PronoWin a déjà.
 *
 * - Les équipes se cherchent dans notre base : chaque match y porte le nom et
 *   le logo de ses deux équipes, et l'identifiant API-Football se lit dans
 *   l'adresse du logo. Aucune requête au fournisseur.
 * - Les joueurs se cherchent chez API-Football (`/players/profiles`), à partir
 *   de trois lettres comme lui, chaque terme gardé un jour en cache.
 */

export interface EquipeTrouvee { id: number; nom: string; logo: string | null; competition: string | null }
export interface JoueurTrouve {
  id: number; nom: string; photo: string | null;
  poste: string | null; nationalite: string | null; age: number | null;
}

const MAX_RESULTATS = 10;
const JOUEURS_MIN = 3;
const TTL_JOUEURS = 24 * 60 * 60_000;

/** L'identifiant API-Football d'une équipe, lu dans l'adresse de son logo. */
export function idEquipeDepuisLogo(logo: string | null | undefined): number | null {
  const m = /\/teams\/(\d+)\.(?:png|svg)/.exec(logo ?? '');
  return m ? Number(m[1]) : null;
}

const normaliser = (s: string) => s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();

/**
 * Les équipes dont le nom contient [terme], les plus récemment jouées
 * d'abord ; celles dont le nom commence par le terme passent devant.
 */
export async function rechercherEquipes(terme: string): Promise<EquipeTrouvee[]> {
  const t = terme.trim();
  if (t.length < 2 || t.length > RECHERCHE_MAX) return [];
  const contient = { contains: t, mode: 'insensitive' as const };
  const lignes = await prisma.match.findMany({
    where: { OR: [{ homeTeam: contient }, { awayTeam: contient }, { homeTeamFull: contient }, { awayTeamFull: contient }] },
    select: {
      homeTeam: true, awayTeam: true, homeTeamFull: true, awayTeamFull: true,
      homeTeamLogo: true, awayTeamLogo: true, leagueCountry: true,
    },
    orderBy: { matchDate: 'desc' },
    take: 300,
  });
  const cible = normaliser(t);
  const parId = new Map<number, EquipeTrouvee>();
  for (const l of lignes) {
    for (const [nom, complet, logo] of [
      [l.homeTeam, l.homeTeamFull, l.homeTeamLogo],
      [l.awayTeam, l.awayTeamFull, l.awayTeamLogo],
    ] as const) {
      if (!normaliser(`${nom} ${complet ?? ''}`).includes(cible)) continue;
      const id = idEquipeDepuisLogo(logo);
      if (id == null || parId.has(id)) continue;
      parId.set(id, { id, nom, logo: logo ?? null, competition: l.leagueCountry ?? null });
    }
  }
  const commence = (e: EquipeTrouvee) => normaliser(e.nom).startsWith(cible) ? 0 : 1;
  return [...parId.values()]
    .map((e, rang) => ({ e, rang }))
    .sort((a, b) => commence(a.e) - commence(b.e) || a.rang - b.rang)
    .map(x => x.e)
    .slice(0, MAX_RESULTATS);
}

/** Les joueurs dont le nom contient [terme] ; vide en deçà de trois lettres ou si le fournisseur ne répond pas. */
export async function rechercherJoueurs(client: AxiosInstance, terme: string): Promise<JoueurTrouve[]> {
  const t = terme.trim();
  if (t.length < JOUEURS_MIN || t.length > RECHERCHE_MAX) return [];
  try {
    const rows = await enrichissementsFootball(client).get('/players/profiles', { search: t }, TTL_JOUEURS);
    return rows
      .map((r: any) => r?.player)
      .filter((p: any) => Number.isInteger(p?.id) && typeof p?.name === 'string')
      .slice(0, MAX_RESULTATS)
      .map((p: any): JoueurTrouve => ({
        id: p.id,
        nom: p.name,
        photo: p.photo ?? null,
        poste: p.position ?? null,
        nationalite: p.nationality ?? null,
        age: Number.isInteger(p.age) ? p.age : null,
      }));
  } catch (e) {
    journal.warn('[Recherche] joueurs indisponibles :', (e as Error).message);
    return [];
  }
}

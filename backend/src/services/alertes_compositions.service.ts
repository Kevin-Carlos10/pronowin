/**
 * « Compositions officielles » pour les matchs suivis (20 octobre 2026).
 *
 * Comme sur Sofascore : une notification quand les onze de départ sont
 * publiés, environ une heure avant le coup d'envoi, à ceux qui suivent le
 * match (favori, ou pari en cours sur son pronostic).
 *
 * Vérifié toutes les 5 minutes, et seulement pour les matchs suivis qui
 * commencent dans l'heure : un appel au fournisseur par match et par passage
 * au plus, jusqu'à ce que les compositions sortent (la lecture est en cache
 * deux minutes, partagée avec la fiche du match).
 *
 * Annoncées une fois : en mémoire, et, après un redémarrage, d'après
 * l'historique des notifications.
 */
import { prisma } from '../lib/prisma';
import { country } from '../i18n/football';
import { apiFootballService } from './api_football.service';
import { NotificationService } from './notification.service';
import { suiveursDuMatch } from './suiveurs_match';
import { journal } from '../utils/logger';
import { rencontre } from '../utils/noms_equipes';

export const TITRE_COMPOSITIONS = 'Compositions officielles';
const AVANT_COUP_ENVOI_MS = 65 * 60_000;
/** Un coup d'envoi retardé de quelques minutes reste couvert. */
const APRES_COUP_ENVOI_MS = 10 * 60_000;

const annoncees = new Map<string, number>();
/** Pour les tests. */
export function _oublierCompositionsAnnoncees(): void { annoncees.clear(); }

const formation = (f: string | null | undefined) => (f ? ` (${f})` : '');

export async function annoncerCompositions(
  maintenant = new Date(),
  notifSvc = new NotificationService(),
): Promise<{ annonces: number }> {
  const t = maintenant.getTime();
  for (const [id, ts] of annoncees) if (t - ts > 24 * 3600_000) annoncees.delete(id);

  const matchs = await prisma.match.findMany({
    where: {
      status:    'SCHEDULED',
      source:    'API_FOOTBALL',
      matchDate: { gte: new Date(t - APRES_COUP_ENVOI_MS), lte: new Date(t + AVANT_COUP_ENVOI_MS) },
      OR: [
        { favoritedBy: { some: {} } },
        { pronostic: { bankrollBets: { some: { result: null } } } },
      ],
    },
    include: { pronostic: { select: { id: true } } },
    orderBy: { matchDate: 'asc' },
    take: 30,
  });

  let annonces = 0;
  for (const m of matchs) {
    if (annoncees.has(m.id)) continue;
    const lien = `/pronostics/${m.pronostic?.id ?? m.id}`;
    const deja = await prisma.notification.findFirst({
      where: { title: TITRE_COMPOSITIONS, deepLink: lien }, select: { id: true },
    });
    if (deja) { annoncees.set(m.id, t); continue; }

    const compo = await apiFootballService
      .getLineups(m.homeTeam, m.awayTeam, m.matchDate.toISOString().slice(0, 10), m.externalId)
      .catch(() => null);
    if (!compo?.available) continue;
    annoncees.set(m.id, t);

    const fr = `${country(m.homeTeam, 'fr')}${formation(compo.home?.formation)} – ${country(m.awayTeam, 'fr')}${formation(compo.away?.formation)}`;
    const en = `${country(m.homeTeam, 'en')}${formation(compo.home?.formation)} – ${country(m.awayTeam, 'en')}${formation(compo.away?.formation)}`;
    const destinataires = await suiveursDuMatch(m.id, m.pronostic?.id ?? null);
    for (const userId of destinataires) {
      notifSvc.sendToUser(userId, {
        title: TITRE_COMPOSITIONS, titleEn: 'Official line-ups',
        body:  `${fr} : les onze de départ sont connus.`,
        bodyEn: `${en}: the starting line-ups are out.`,
        data:  { type: 'match', deep_link: lien, match_id: m.id },
      }, 'match').catch((err: any) => journal.error('[Compositions]', err.message));
    }
    annonces++;
    journal.info(`[Compositions] ${rencontre(m.homeTeam, m.awayTeam)} — ${destinataires.length} suiveur(s)`);
  }
  return { annonces };
}

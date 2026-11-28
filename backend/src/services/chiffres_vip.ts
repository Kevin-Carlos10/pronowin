/**
 * Les chiffres du mur Premium et de la vitrine (24 novembre 2026).
 *
 * Depuis le 23 novembre, le taux de réussite est réservé aux abonnés
 * (`taux_reserve.ts`) : le mur Premium et la page d'accueil du site, qui
 * s'adressent par définition aux non-abonnés, n'avaient plus aucun chiffre à
 * montrer. Ceux-ci n'en sont pas un taux : ils disent ce que l'abonnement
 * donne, pas ce qu'il rapporte —
 *
 * - les pronostics VIP publiés ces trente derniers jours (retirés exclus) ;
 * - les compétitions couvertes par les pronostics publiés sur la période ;
 * - les pronostics VIP des matchs du jour (UTC, l'heure de Ouagadougou).
 *
 * Comme le bilan Premium, un chiffre trop petit ne s'annonce pas : « 2
 * pronostics VIP publiés » desservirait l'offre plus qu'il ne la sert. Le
 * serveur tranche (nul sous le seuil) ; l'app et le site se taisent alors,
 * sans recalculer.
 */
import { prisma } from '../lib/prisma';

export const PERIODE_JOURS       = 30;
export const SEUIL_VIP_PUBLIES   = 10;
export const SEUIL_COMPETITIONS  = 3;

export interface ChiffresVip {
  periode_jours:  number;
  /** Nul sous [SEUIL_VIP_PUBLIES]. */
  vip_publies:    number | null;
  /** Nul sous [SEUIL_COMPETITIONS]. */
  competitions:   number | null;
  /** Nul quand aucun pronostic VIP n'est publié pour les matchs du jour. */
  vip_aujourdhui: number | null;
}

/** Les comptes bruts, passés au crible des seuils d'annonce. */
export function chiffresAnnoncables(brut: { vipPublies: number; competitions: number; vipAujourdhui: number }): ChiffresVip {
  return {
    periode_jours:  PERIODE_JOURS,
    vip_publies:    brut.vipPublies >= SEUIL_VIP_PUBLIES ? brut.vipPublies : null,
    competitions:   brut.competitions >= SEUIL_COMPETITIONS ? brut.competitions : null,
    vip_aujourdhui: brut.vipAujourdhui >= 1 ? brut.vipAujourdhui : null,
  };
}

export async function calculerChiffresVip(maintenant: Date = new Date()): Promise<ChiffresVip> {
  const depuis = new Date(maintenant.getTime() - PERIODE_JOURS * 24 * 3600_000);
  const debutJour = new Date(Date.UTC(maintenant.getUTCFullYear(), maintenant.getUTCMonth(), maintenant.getUTCDate()));
  const finJour = new Date(debutJour.getTime() + 24 * 3600_000);
  const publiesSurLaPeriode = { isPublished: true, publicationRecordedAt: { gte: depuis } };

  const [vipPublies, ligues, vipAujourdhui] = await Promise.all([
    prisma.pronostic.count({ where: { ...publiesSurLaPeriode, isPremium: true } }),
    prisma.pronostic.findMany({ where: publiesSurLaPeriode, select: { match: { select: { league: true } } } }),
    prisma.pronostic.count({
      where: {
        isPremium: true, isPublished: true,
        match: { matchDate: { gte: debutJour, lt: finJour }, status: { notIn: ['POSTPONED', 'SUSPENDED'] } },
      },
    }),
  ]);

  return chiffresAnnoncables({
    vipPublies,
    competitions: new Set(ligues.map(l => l.match.league)).size,
    vipAujourdhui,
  });
}

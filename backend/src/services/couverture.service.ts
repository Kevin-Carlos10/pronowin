/**
 * Alerte de couverture (26 novembre 2026).
 *
 * L'abonné enregistre sa sélection dans la bankroll (« Valider ma
 * sélection »). Tant que la mise est ouverte, ce service lit la cote de
 * l'évènement inverse — en direct toutes les deux minutes (le flux `/odds/live`
 * est déjà lu, une fois pour tous les matchs), et avant le coup d'envoi une
 * fois par demi-heure dans les six dernières heures. Dès qu'une mise sur
 * l'inverse garantirait au moins [seuil] % du gain potentiel (50 % par défaut,
 * 30 ou 70 au choix), une notification dit combien miser, et sur quoi.
 *
 * Une seule alerte par mise. Le calcul porte sur la mise enregistrée et sur
 * la cote obtenue chez le bookmaker si l'abonné l'a précisée, sinon la cote
 * publiée. Les cotes lues sont celles du fournisseur (1xBet avant le match) :
 * la notification demande de vérifier celle de son propre bookmaker.
 *
 * Désactivable dans les réglages (catégorie `couverture`).
 */
import { prisma } from '../lib/prisma';
import { apiFootballInsights, apiFootballService } from './api_football.service';
import { NotificationService, isNotifEnabled } from './notification.service';
import { pasDeDevise } from './mise_suggeree';
import { nomDevise } from '../utils/devise';
import { rencontre } from '../utils/noms_equipes';
import { journal } from '../utils/logger';
import {
  calculerCouverture, coteDe, libelleSelection, seuilAtteint, seuilDe,
  selectionDuPronostic, selectionInverse, type Couverture, type MarcheCote, type Selection,
} from './couverture';

/** Avant le coup d'envoi : seulement les six dernières heures… */
export const FENETRE_AVANT_MATCH_MS = 6 * 3600_000;
/** … et une lecture par match toutes les trente minutes. */
export const INTERVALLE_AVANT_MATCH_MS = 30 * 60_000;

const derniereLectureAvantMatch = new Map<string, number>();
/** Pour les tests. */
export function _oublierLecturesAvantMatch(): void { derniereLectureAvantMatch.clear(); }

interface MatchSurveille {
  id: string; homeTeam: string; awayTeam: string; matchDate: Date;
  status: string; externalId: string | number | null; source?: string | null;
}

/** Les marchés du match, au format commun ; nuls si rien n'est lisible. */
export async function marchesDuMatch(m: MatchSurveille, maintenant: Date, forcer = false): Promise<{ marches: MarcheCote[]; source: 'direct' | 'avant_match' } | null> {
  // L'identifiant n'est celui d'API-Football que pour un match qui en vient.
  if (m.source !== 'API_FOOTBALL') return null;
  const fixture = Number(m.externalId);
  if (!Number.isFinite(fixture) || fixture <= 0) return null;

  if (m.status === 'LIVE') {
    const live = await apiFootballInsights.getLiveOdds(fixture).catch(() => null);
    if (!live || live.stale) return null;
    return {
      source: 'direct',
      marches: live.markets.map(mk => ({
        nom: mk.key ?? mk.name,
        valeurs: mk.values.map(v => ({ valeur: v.value, cote: v.odd, ...(v.ligne ? { ligne: v.ligne } : {}) })),
      })),
    };
  }

  if (m.status !== 'SCHEDULED') return null;
  const avant = m.matchDate.getTime() - maintenant.getTime();
  if (!forcer) {
    if (avant > FENETRE_AVANT_MATCH_MS || avant < 0) return null;
    const derniere = derniereLectureAvantMatch.get(m.id);
    if (derniere !== undefined && maintenant.getTime() - derniere < INTERVALLE_AVANT_MATCH_MS) return null;
    derniereLectureAvantMatch.set(m.id, maintenant.getTime());
  }
  const odds = await apiFootballService
    .getOdds1xBet(m.homeTeam, m.awayTeam, m.matchDate.toISOString().slice(0, 10), fixture)
    .catch(() => null);
  if (!odds) return null;
  return {
    source: 'avant_match',
    marches: odds.markets.map(mk => ({ nom: mk.name, valeurs: mk.values.map(v => ({ valeur: v.value, cote: v.odd })) })),
  };
}

export interface CalculPari {
  selection: Selection;
  inverse: Selection;
  coteInverse: number;
  couverture: Couverture;
}

/** La couverture d'une mise dans des marchés donnés, ou nulle. */
export function couvertureDuPari(
  pari: { stakedAmount: number; oddsUsed: number; coteBookmaker: number | null },
  pronostic: { predictionType: string | null; marketName: string | null; marketValue: string | null },
  marches: MarcheCote[],
  devise: string | null | undefined,
): CalculPari | null {
  const selection = selectionDuPronostic(pronostic);
  if (!selection) return null;
  const inverse = selectionInverse(selection);
  const coteInverse = coteDe(marches, inverse);
  if (coteInverse === null) return null;
  const couverture = calculerCouverture(
    pari.stakedAmount, pari.coteBookmaker ?? pari.oddsUsed, coteInverse, pasDeDevise(devise));
  return couverture ? { selection, inverse, coteInverse, couverture } : null;
}

const montant = (n: number) => n.toLocaleString('fr-FR');
const montantEn = (n: number) => n.toLocaleString('en-GB');

/**
 * Le passage périodique : chaque mise ouverte d'un match en direct, ou qui
 * commence dans les six heures, dont l'alerte n'est pas encore partie.
 */
export async function surveillerCouvertures(
  maintenant = new Date(),
  notifSvc = new NotificationService(),
): Promise<{ examinees: number; alertes: number }> {
  const paris = await prisma.bankrollBet.findMany({
    where: {
      result: null,
      couvertureNotifieeLe: null,
      pronostic: {
        match: {
          OR: [
            { status: 'LIVE' },
            { status: 'SCHEDULED', matchDate: { gte: maintenant, lte: new Date(maintenant.getTime() + FENETRE_AVANT_MATCH_MS) } },
          ],
        },
      },
    },
    include: {
      bankroll: { select: { currency: true, userId: true, user: { select: { notificationPrefs: true } } } },
      pronostic: {
        select: {
          id: true, predictionType: true, marketName: true, marketValue: true,
          match: { select: { id: true, homeTeam: true, awayTeam: true, matchDate: true, status: true, externalId: true, source: true } },
        },
      },
    },
  });

  // Une lecture des cotes par match, pas par mise.
  const parMatch = new Map<string, typeof paris>();
  for (const p of paris) {
    const prefs = p.bankroll.user?.notificationPrefs;
    if (!isNotifEnabled(prefs, 'couverture')) continue;
    if (!selectionDuPronostic(p.pronostic)) continue;
    const liste = parMatch.get(p.pronostic.match.id) ?? [];
    liste.push(p);
    parMatch.set(p.pronostic.match.id, liste);
  }

  let alertes = 0;
  for (const liste of parMatch.values()) {
    const match = liste[0].pronostic.match;
    const lecture = await marchesDuMatch(match as MatchSurveille, maintenant);
    if (!lecture) continue;

    for (const p of liste) {
      const devise = p.bankroll.currency;
      const calcul = couvertureDuPari(p, p.pronostic, lecture.marches, devise);
      if (!calcul || !seuilAtteint(calcul.couverture, seuilDe(p.bankroll.user?.notificationPrefs))) continue;

      const c = calcul.couverture;
      const duel = rencontre(match.homeTeam, match.awayTeam);
      const inverseFr = libelleSelection(calcul.inverse, match.homeTeam, match.awayTeam, 'fr');
      const inverseEn = libelleSelection(calcul.inverse, match.homeTeam, match.awayTeam, 'en');
      const d = nomDevise(devise);
      const cote = calcul.coteInverse.toFixed(2);

      // Marquée d'abord : un second passage ne doit jamais renvoyer l'alerte,
      // même si l'envoi échoue.
      const marque = await prisma.bankrollBet.updateMany({
        where: { id: p.id, couvertureNotifieeLe: null },
        data: {
          couvertureNotifieeLe: maintenant,
          couverture: {
            inverse: inverseFr, cote_inverse: calcul.coteInverse, source: lecture.source,
            mise_couverture: c.miseCouverture, gain_garanti: c.gainGaranti, gain_potentiel: c.gainPotentiel,
          },
        },
      });
      if (marque.count === 0) continue;

      await notifSvc.sendToUser(p.bankroll.userId, {
        title:   `Couvre ta mise : +${montant(c.gainGaranti)} ${d} garantis`,
        titleEn: `Hedge your bet: +${montantEn(c.gainGaranti)} ${d} guaranteed`,
        body:    `${duel} — « ${inverseFr} » est à ${cote}. Mise ${montant(c.miseCouverture)} ${d} dessus : `
               + `tu gagnes au moins ${montant(c.gainGaranti)} ${d}, quel que soit le résultat. Vérifie la cote proposée avant de miser.`,
        bodyEn:  `${duel} — "${inverseEn}" is at ${cote}. Stake ${montantEn(c.miseCouverture)} ${d} on it: `
               + `you win at least ${montantEn(c.gainGaranti)} ${d}, whatever the result. Check the odds offered before staking.`,
        data:    { type: 'couverture', deep_link: `/pronostics/${p.pronostic.id}` },
      }, 'couverture').catch(e => journal.error('[Couverture] envoi', (e as Error).message));
      alertes++;
    }
  }
  return { examinees: paris.length, alertes };
}

/**
 * GET /bankroll/couverture/:pronosticId — la couverture de la mise de
 * l'abonné, maintenant, pour la fiche du match. Toujours une réponse : sans
 * marché couvrable ou sans cote, la fiche propose au moins le calcul à la
 * main.
 */
export async function couverturePourAbonne(userId: string, pronosticId: string, maintenant = new Date()) {
  const pari = await prisma.bankrollBet.findFirst({
    where: { pronosticId, bankroll: { userId }, result: null },
    include: {
      bankroll: { select: { currency: true, user: { select: { notificationPrefs: true } } } },
      pronostic: {
        select: {
          predictionType: true, marketName: true, marketValue: true,
          match: { select: { id: true, homeTeam: true, awayTeam: true, matchDate: true, status: true, externalId: true, source: true } },
        },
      },
    },
  });
  if (!pari) return { disponible: false as const, raison: 'aucune_mise' as const };

  const match = pari.pronostic.match;
  const base = {
    mise: pari.stakedAmount,
    cote: pari.coteBookmaker ?? pari.oddsUsed,
    devise: pari.bankroll.currency,
    seuil: seuilDe(pari.bankroll.user?.notificationPrefs),
    alerte_envoyee: pari.couvertureNotifieeLe !== null,
  };
  const selection = selectionDuPronostic(pari.pronostic);
  if (!selection) return { disponible: false as const, raison: 'marche' as const, ...base };
  const inverse = selectionInverse(selection);
  const libelles = {
    inverse_fr: libelleSelection(inverse, match.homeTeam, match.awayTeam, 'fr'),
    inverse_en: libelleSelection(inverse, match.homeTeam, match.awayTeam, 'en'),
  };
  if (!['LIVE', 'SCHEDULED'].includes(match.status)) {
    return { disponible: false as const, raison: 'termine' as const, ...base, ...libelles };
  }

  const lecture = await marchesDuMatch(match as MatchSurveille, maintenant, true);
  const calcul = lecture ? couvertureDuPari(pari, pari.pronostic, lecture.marches, pari.bankroll.currency) : null;
  if (!calcul || !lecture) return { disponible: false as const, raison: 'cote' as const, ...base, ...libelles };

  return {
    disponible: true as const,
    ...base, ...libelles,
    source: lecture.source,
    cote_inverse: calcul.coteInverse,
    mise_couverture: calcul.couverture.miseCouverture,
    gain_garanti: calcul.couverture.gainGaranti,
    gain_potentiel: calcul.couverture.gainPotentiel,
    part: calcul.couverture.part,
    seuil_atteint: seuilAtteint(calcul.couverture, base.seuil),
  };
}

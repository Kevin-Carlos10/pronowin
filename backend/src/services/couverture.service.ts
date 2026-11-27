/**
 * Alerte de couverture (26 novembre 2026, complétée le 27).
 *
 * L'abonné enregistre sa sélection dans la bankroll (« Valider ma
 * sélection »), ou un combiné. Tant que la mise est ouverte, ce service lit la
 * cote de l'évènement inverse — en direct toutes les deux minutes (le flux
 * `/odds/live` est déjà lu, une fois pour tous les matchs), et avant le coup
 * d'envoi dans les six dernières heures : une fois par demi-heure, puis toutes
 * les dix minutes dans la dernière heure, quand les compositions tombent et que
 * les cotes bougent le plus. Dès qu'une mise sur l'inverse garantirait au
 * moins [seuil] % du gain potentiel (50 % par défaut, 30 ou 70 au choix), une
 * notification dit combien miser, et sur quoi.
 *
 * Deux alertes au plus par mise : la première au seuil choisi, la seconde si
 * la couverture atteint ensuite 80 % du gain potentiel. Plus aucune une fois la
 * couverture enregistrée (« J'ai couvert »).
 *
 * Un combiné se couvre quand il ne lui reste qu'une sélection PronoWin à
 * jouer, toutes les autres passées : l'inverse de cette dernière contre le
 * gain du combiné entier.
 *
 * Le calcul porte sur la mise enregistrée et sur la cote obtenue si l'abonné
 * l'a précisée, sinon la cote publiée. Les cotes lues sont celles du
 * fournisseur (1xBet avant le match) : la notification demande de vérifier
 * celle qu'on lui propose.
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
  calculerCouverture, coteDe, libelleSelection, noteRemboursement, remboursable, seuilAtteint, seuilDe,
  selectionDuPronostic, selectionInverse, type Couverture, type MarcheCote, type Selection,
} from './couverture';
import { coteRestante, derniereSelectionOuverte } from './combines.service';
import { couverturePourApi } from './couvertures_enregistrees.service';

/** Avant le coup d'envoi : seulement les six dernières heures… */
export const FENETRE_AVANT_MATCH_MS = 6 * 3600_000;
/** … une lecture par match toutes les trente minutes… */
export const INTERVALLE_AVANT_MATCH_MS = 30 * 60_000;
/** … puis toutes les dix minutes dans la dernière heure. */
export const DERNIERE_HEURE_MS = 3600_000;
export const INTERVALLE_DERNIERE_HEURE_MS = 10 * 60_000;
/** La seconde alerte : 80 % du gain potentiel garantis. */
export const SEUIL_SECONDE_ALERTE = 80;

export function intervalleAvantMatch(avantCoupEnvoiMs: number): number {
  return avantCoupEnvoiMs <= DERNIERE_HEURE_MS ? INTERVALLE_DERNIERE_HEURE_MS : INTERVALLE_AVANT_MATCH_MS;
}

const derniereLectureAvantMatch = new Map<string, number>();
/** Pour les tests. */
export function _oublierLecturesAvantMatch(): void { derniereLectureAvantMatch.clear(); }

interface MatchSurveille {
  id: string; homeTeam: string; awayTeam: string; matchDate: Date;
  status: string; externalId: string | number | null; source?: string | null;
  homeScore?: number | null; awayScore?: number | null;
}

const MATCH_SURVEILLE = {
  id: true, homeTeam: true, awayTeam: true, matchDate: true, status: true, externalId: true, source: true,
  homeScore: true, awayScore: true,
} as const;

/** Les marchés du match, au format commun ; nuls si rien n'est lisible. */
export async function marchesDuMatch(m: MatchSurveille, maintenant: Date, forcer = false): Promise<{
  marches: MarcheCote[]; source: 'direct' | 'avant_match'; minute?: number | null;
} | null> {
  // L'identifiant n'est celui d'API-Football que pour un match qui en vient.
  if (m.source !== 'API_FOOTBALL') return null;
  const fixture = Number(m.externalId);
  if (!Number.isFinite(fixture) || fixture <= 0) return null;

  if (m.status === 'LIVE') {
    const live = await apiFootballInsights.getLiveOdds(fixture).catch(() => null);
    if (!live || live.stale) return null;
    return {
      source: 'direct',
      minute: live.elapsed ?? null,
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
    if (derniere !== undefined && maintenant.getTime() - derniere < intervalleAvantMatch(avant)) return null;
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
  /** La même couverture, en ne visant qu'à récupérer sa mise. */
  miseRemboursee: Couverture;
}

/**
 * La couverture d'une mise dans des marchés donnés, ou nulle. [cote] : la cote
 * à laquelle la sélection a été jouée (pour un combiné, la cote restante).
 */
export function couvertureDe(
  mise: number, cote: number,
  pronostic: { predictionType: string | null; marketName: string | null; marketValue: string | null },
  marches: MarcheCote[],
  devise: string | null | undefined,
): CalculPari | null {
  const selection = selectionDuPronostic(pronostic);
  if (!selection) return null;
  const inverse = selectionInverse(selection);
  const coteInverse = coteDe(marches, inverse);
  if (coteInverse === null) return null;
  const pas = pasDeDevise(devise);
  const couverture = calculerCouverture(mise, cote, coteInverse, pas);
  const miseRemboursee = calculerCouverture(mise, cote, coteInverse, pas, 'mise_remboursee');
  return couverture && miseRemboursee ? { selection, inverse, coteInverse, couverture, miseRemboursee } : null;
}

/** Compatibilité : la couverture d'une mise simple. */
export function couvertureDuPari(
  pari: { stakedAmount: number; oddsUsed: number; coteBookmaker: number | null },
  pronostic: { predictionType: string | null; marketName: string | null; marketValue: string | null },
  marches: MarcheCote[],
  devise: string | null | undefined,
): CalculPari | null {
  return couvertureDe(pari.stakedAmount, pari.coteBookmaker ?? pari.oddsUsed, pronostic, marches, devise);
}

/**
 * 0 : rien à dire ; 1 : le seuil choisi est atteint ; 2 : 80 % aussi. Avec un
 * seuil choisi de 80 % ou plus, il n'y a qu'une alerte.
 */
export function niveauAlerte(c: Couverture, seuil: number): 0 | 1 | 2 {
  if (!seuilAtteint(c, seuil)) return 0;
  return seuil < SEUIL_SECONDE_ALERTE && seuilAtteint(c, SEUIL_SECONDE_ALERTE) ? 2 : 1;
}

const montant = (n: number) => n.toLocaleString('fr-FR');
const montantEn = (n: number) => n.toLocaleString('en-GB');

interface PronosticSurveille {
  id: string; predictionType: string | null; marketName: string | null; marketValue: string | null;
  match: MatchSurveille;
}

/** Une mise à surveiller : simple, ou la dernière sélection d'un combiné. */
interface Cible {
  type: 'pari' | 'combine';
  id: string;
  userId: string;
  devise: string;
  prefs: unknown;
  alertes: number;
  mise: number;
  cote: number;
  pronostic: PronosticSurveille;
}

/** Le contexte d'une lecture en direct : « 63e minute, 1-0 ». */
function contexteDirect(match: MatchSurveille, minute: number | null | undefined, langue: 'fr' | 'en'): string {
  if (minute == null) return '';
  const score = match.homeScore != null && match.awayScore != null ? `, ${match.homeScore}-${match.awayScore}` : '';
  return langue === 'fr' ? `, ${minute}e minute${score}` : `, ${minute}'${score}`;
}

/**
 * Le passage périodique : chaque mise ouverte d'un match en direct, ou qui
 * commence dans les six heures, qui n'a pas reçu ses deux alertes ni été
 * couverte.
 */
export async function surveillerCouvertures(
  maintenant = new Date(),
  notifSvc = new NotificationService(),
): Promise<{ examinees: number; alertes: number }> {
  const fenetre = {
    OR: [
      { status: 'LIVE' as const },
      { status: 'SCHEDULED' as const, matchDate: { gte: maintenant, lte: new Date(maintenant.getTime() + FENETRE_AVANT_MATCH_MS) } },
    ],
  };
  const [paris, combines] = await Promise.all([
    prisma.bankrollBet.findMany({
      where: {
        result: null,
        couvertureAlertes: { lt: 2 },
        couvertureEnregistree: { is: null },
        pronostic: { match: fenetre },
      },
      include: {
        bankroll: { select: { currency: true, userId: true, user: { select: { notificationPrefs: true } } } },
        pronostic: {
          select: { id: true, predictionType: true, marketName: true, marketValue: true, match: { select: MATCH_SURVEILLE } },
        },
      },
    }),
    prisma.bankrollCombine.findMany({
      where: { result: null, couvertureAlertes: { lt: 2 }, couvertureEnregistree: { is: null } },
      include: {
        bankroll: { select: { currency: true, userId: true, user: { select: { notificationPrefs: true } } } },
        selections: {
          include: {
            pronostic: {
              select: { id: true, predictionType: true, marketName: true, marketValue: true, match: { select: MATCH_SURVEILLE } },
            },
          },
        },
      },
    }),
  ]);

  const cibles: Cible[] = [];
  for (const p of paris) {
    cibles.push({
      type: 'pari', id: p.id, userId: p.bankroll.userId, devise: p.bankroll.currency,
      prefs: p.bankroll.user?.notificationPrefs, alertes: p.couvertureAlertes ?? 0,
      mise: p.stakedAmount, cote: p.coteBookmaker ?? p.oddsUsed, pronostic: p.pronostic as PronosticSurveille,
    });
  }
  for (const c of combines) {
    const derniere = derniereSelectionOuverte(c.selections);
    if (!derniere?.pronostic) continue;
    const m = derniere.pronostic.match;
    const dansLaFenetre = m.status === 'LIVE' || (m.status === 'SCHEDULED'
      && m.matchDate.getTime() >= maintenant.getTime()
      && m.matchDate.getTime() <= maintenant.getTime() + FENETRE_AVANT_MATCH_MS);
    if (!dansLaFenetre) continue;
    cibles.push({
      type: 'combine', id: c.id, userId: c.bankroll.userId, devise: c.bankroll.currency,
      prefs: c.bankroll.user?.notificationPrefs, alertes: c.couvertureAlertes ?? 0,
      mise: c.stakedAmount, cote: coteRestante(c.selections, derniere), pronostic: derniere.pronostic as PronosticSurveille,
    });
  }

  // Une lecture des cotes par match, pas par mise.
  const parMatch = new Map<string, Cible[]>();
  for (const c of cibles) {
    if (!isNotifEnabled(c.prefs as any, 'couverture')) continue;
    if (!selectionDuPronostic(c.pronostic)) continue;
    const liste = parMatch.get(c.pronostic.match.id) ?? [];
    liste.push(c);
    parMatch.set(c.pronostic.match.id, liste);
  }

  let alertes = 0;
  for (const liste of parMatch.values()) {
    const match = liste[0].pronostic.match;
    const lecture = await marchesDuMatch(match, maintenant);
    if (!lecture) continue;

    for (const c of liste) {
      const calcul = couvertureDe(c.mise, c.cote, c.pronostic, lecture.marches, c.devise);
      if (!calcul) continue;
      const niveau = niveauAlerte(calcul.couverture, seuilDe(c.prefs));
      if (niveau <= c.alertes) continue;

      const g = calcul.couverture;
      const r = calcul.miseRemboursee;
      const duel = rencontre(match.homeTeam, match.awayTeam);
      const inverseFr = libelleSelection(calcul.inverse, match.homeTeam, match.awayTeam, 'fr');
      const inverseEn = libelleSelection(calcul.inverse, match.homeTeam, match.awayTeam, 'en');
      const selectionFr = libelleSelection(calcul.selection, match.homeTeam, match.awayTeam, 'fr');
      const selectionEn = libelleSelection(calcul.selection, match.homeTeam, match.awayTeam, 'en');
      const d = nomDevise(c.devise);
      const cote = calcul.coteInverse.toFixed(2);
      const seconde = c.alertes > 0;
      const combine = c.type === 'combine';

      // Marquée d'abord : un second passage ne doit jamais renvoyer la même
      // alerte, même si l'envoi échoue.
      const donnees = {
        couvertureAlertes: niveau,
        couvertureNotifieeLe: maintenant,
        couverture: {
          inverse: inverseFr, cote_inverse: calcul.coteInverse, source: lecture.source,
          mise_couverture: g.miseCouverture, gain_garanti: g.gainGaranti, gain_potentiel: g.gainPotentiel,
        },
      };
      const marque = combine
        ? await prisma.bankrollCombine.updateMany({ where: { id: c.id, couvertureAlertes: c.alertes }, data: donnees })
        : await prisma.bankrollBet.updateMany({ where: { id: c.id, couvertureAlertes: c.alertes }, data: donnees });
      if (marque.count === 0) continue;

      const ctxFr = lecture.source === 'direct' ? contexteDirect(match, lecture.minute, 'fr') : '';
      const ctxEn = lecture.source === 'direct' ? contexteDirect(match, lecture.minute, 'en') : '';
      const objetFr = combine ? `il ne manque que « ${selectionFr} » à ton combiné. ` : '';
      const objetEn = combine ? `only "${selectionEn}" is left in your accumulator. ` : '';
      await notifSvc.sendToUser(c.userId, {
        title: seconde
          ? `Couverture encore meilleure : +${montant(g.gainGaranti)} ${d} garantis`
          : `Couvre ${combine ? 'ton combiné' : 'ta mise'} : +${montant(g.gainGaranti)} ${d} garantis`,
        titleEn: seconde
          ? `Even better hedge: +${montantEn(g.gainGaranti)} ${d} guaranteed`
          : `Hedge your ${combine ? 'accumulator' : 'bet'}: +${montantEn(g.gainGaranti)} ${d} guaranteed`,
        body: `${duel}${ctxFr} — ${objetFr}« ${inverseFr} » est à ${cote}. Mise ${montant(g.miseCouverture)} ${d} dessus : `
            + `tu gagnes au moins ${montant(g.gainGaranti)} ${d}, quel que soit le résultat. `
            + `Ou ${montant(r.miseCouverture)} ${d} pour récupérer ta mise et garder +${montant(r.siSelection)} ${d} si ta sélection passe. `
            + 'Vérifie la cote proposée avant de miser.',
        bodyEn: `${duel}${ctxEn} — ${objetEn}"${inverseEn}" is at ${cote}. Stake ${montantEn(g.miseCouverture)} ${d} on it: `
              + `you win at least ${montantEn(g.gainGaranti)} ${d}, whatever the result. `
              + `Or ${montantEn(r.miseCouverture)} ${d} to get your stake back and keep +${montantEn(r.siSelection)} ${d} if your selection wins. `
              + 'Check the odds offered before staking.',
        data: { type: 'couverture', deep_link: combine ? `/bankroll/combine/${c.id}` : `/pronostics/${c.pronostic.id}` },
      }, 'couverture').catch(e => journal.error('[Couverture] envoi', (e as Error).message));
      alertes++;
    }
  }
  return { examinees: cibles.length, alertes };
}

// ─── Pour l'écran ────────────────────────────────────────────────────────────

/** Les deux façons de couvrir, au format de l'application. */
function strategiesPourApi(calcul: CalculPari) {
  const f = (c: Couverture) => ({
    mise: c.miseCouverture, gain_garanti: c.gainGaranti, si_selection: c.siSelection, si_inverse: c.siInverse,
  });
  return { gain_egal: f(calcul.couverture), mise_remboursee: f(calcul.miseRemboursee) };
}

/** Ce que l'écran affiche, pour une mise simple ou la dernière sélection d'un combiné. */
async function couvertureCalculee(
  base: { mise: number; cote: number; devise: string; seuil: number; alertes: number },
  pronostic: PronosticSurveille,
  maintenant: Date,
) {
  const match = pronostic.match;
  const avecBase = { ...base, alerte_envoyee: base.alertes > 0 };
  const selection = selectionDuPronostic(pronostic);
  if (!selection) return { disponible: false as const, raison: 'marche' as const, ...avecBase };
  const inverse = selectionInverse(selection);
  const libelles = {
    selection_fr: libelleSelection(selection, match.homeTeam, match.awayTeam, 'fr'),
    selection_en: libelleSelection(selection, match.homeTeam, match.awayTeam, 'en'),
    inverse_fr: libelleSelection(inverse, match.homeTeam, match.awayTeam, 'fr'),
    inverse_en: libelleSelection(inverse, match.homeTeam, match.awayTeam, 'en'),
    remboursable: remboursable(selection),
    note_remboursement_fr: noteRemboursement(selection, 'fr'),
    note_remboursement_en: noteRemboursement(selection, 'en'),
  };
  if (!['LIVE', 'SCHEDULED'].includes(match.status)) {
    return { disponible: false as const, raison: 'termine' as const, ...avecBase, ...libelles };
  }

  const lecture = await marchesDuMatch(match, maintenant, true);
  const calcul = lecture ? couvertureDe(base.mise, base.cote, pronostic, lecture.marches, base.devise) : null;
  if (!calcul || !lecture) return { disponible: false as const, raison: 'cote' as const, ...avecBase, ...libelles };

  return {
    disponible: true as const,
    ...avecBase, ...libelles,
    source: lecture.source,
    minute: lecture.minute ?? null,
    cote_inverse: calcul.coteInverse,
    mise_couverture: calcul.couverture.miseCouverture,
    gain_garanti: calcul.couverture.gainGaranti,
    gain_potentiel: calcul.couverture.gainPotentiel,
    part: calcul.couverture.part,
    seuil_atteint: seuilAtteint(calcul.couverture, base.seuil),
    strategies: strategiesPourApi(calcul),
  };
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
      pronostic: { select: { id: true, predictionType: true, marketName: true, marketValue: true, match: { select: MATCH_SURVEILLE } } },
      couvertureEnregistree: true,
    },
  });
  if (!pari) return { disponible: false as const, raison: 'aucune_mise' as const };

  const r = await couvertureCalculee({
    mise: pari.stakedAmount,
    cote: pari.coteBookmaker ?? pari.oddsUsed,
    devise: pari.bankroll.currency,
    seuil: seuilDe(pari.bankroll.user?.notificationPrefs),
    alertes: pari.couvertureAlertes ?? (pari.couvertureNotifieeLe ? 1 : 0),
  }, pari.pronostic as PronosticSurveille, maintenant);
  return { ...r, pari_id: pari.id, enregistree: couverturePourApi(pari.couvertureEnregistree) };
}

/**
 * GET /bankroll/combines/:id/couverture — la couverture d'un combiné : sa
 * dernière sélection ouverte, contre le gain du combiné entier.
 */
export async function couvertureCombinePourAbonne(userId: string, combineId: string, maintenant = new Date()) {
  const c = await prisma.bankrollCombine.findUnique({
    where: { id: combineId },
    include: {
      bankroll: { select: { userId: true, currency: true, user: { select: { notificationPrefs: true } } } },
      selections: {
        include: {
          pronostic: { select: { id: true, predictionType: true, marketName: true, marketValue: true, match: { select: MATCH_SURVEILLE } } },
        },
      },
      couvertureEnregistree: true,
    },
  });
  if (!c || c.bankroll.userId !== userId) return null;
  const enregistree = couverturePourApi(c.couvertureEnregistree);
  if (c.result != null) return { disponible: false as const, raison: 'regle' as const, combine_id: c.id, enregistree };
  const derniere = derniereSelectionOuverte(c.selections);
  if (!derniere?.pronostic) {
    const restantes = c.selections.filter(l => !l.annulee && l.result == null).length;
    return { disponible: false as const, raison: 'pas_encore' as const, combine_id: c.id, restantes, enregistree };
  }
  const r = await couvertureCalculee({
    mise: c.stakedAmount,
    cote: coteRestante(c.selections, derniere),
    devise: c.bankroll.currency,
    seuil: seuilDe(c.bankroll.user?.notificationPrefs),
    alertes: c.couvertureAlertes ?? 0,
  }, derniere.pronostic as PronosticSurveille, maintenant);
  return { ...r, combine_id: c.id, pronostic_id: derniere.pronostic.id, enregistree };
}

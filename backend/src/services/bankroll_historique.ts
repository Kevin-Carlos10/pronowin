/**
 * Ce que la bankroll a rendu, mise par mise et jour par jour (27 novembre 2026).
 *
 * La courbe de la page Bankroll, le résumé de la semaine et « Mes
 * statistiques » ne comptaient que les mises simples, et les deux premiers
 * seulement les cinquante dernières que l'app reçoit. Les combinés et les
 * couvertures enregistrées (1.0.42) sortent pourtant du solde et y reviennent.
 * Sans eux, ces trois écrans contredisaient le résultat net et le solde
 * affichés juste au-dessus.
 *
 * Tout se calcule ici, sur l'historique entier, et l'app n'a plus qu'à
 * afficher.
 */
import { prisma } from '../lib/prisma';
import { soldeExact } from './bankroll_journal';

const JOUR_MS = 86_400_000;

/** Une mise réglée : simple ou combinée, couverture comprise. */
export type ResultatRegle = {
  le: Date;
  genre: 'pari' | 'combine';
  result: string;
  /** Le gain ou la perte de la mise, couverture comprise. */
  net: number;
  /**
   * Ce qui a été réellement exposé : la mise, et la couverture, sauf si elles
   * ont été remboursées. C'est la base du rendement.
   */
  mise: number;
};

type MiseLue = {
  result: string | null; profit: number | null; stakedAmount: number;
  settledAt: Date | null; createdAt: Date;
  couvertureEnregistree?: { result: string | null; profit: number | null; mise: number } | null;
};

const arrondi = (n: number) => Math.round(n * 100) / 100;

function versResultat(genre: ResultatRegle['genre'], m: MiseLue): ResultatRegle | null {
  if (m.result == null || m.profit == null) return null;
  const c = m.couvertureEnregistree;
  // La couverture se règle avec le match. Une couverture encore ouverte sur
  // une mise réglée n'arrive pas, mais elle ne compterait alors que dans
  // l'engagé, pas dans le résultat.
  const reglee = c != null && c.result != null && c.profit != null;
  return {
    le: m.settledAt ?? m.createdAt,
    genre,
    result: m.result,
    net: m.profit + (reglee ? c!.profit! : 0),
    mise: (m.result !== 'PUSH' ? m.stakedAmount : 0) + (reglee && c!.result !== 'PUSH' ? c!.mise : 0),
  };
}

/**
 * Toutes les mises réglées d'une bankroll, de la plus ancienne à la plus
 * récente. Une couverture n'est pas une ligne à part : elle se règle avec sa
 * mise, et l'abonné lit le total des deux.
 */
export async function resultatsRegles(bankrollId: string): Promise<ResultatRegle[]> {
  const [paris, combines] = await Promise.all([
    prisma.bankrollBet.findMany({
      where: { bankrollId, result: { not: null } }, include: { couvertureEnregistree: true },
    }),
    prisma.bankrollCombine.findMany({
      where: { bankrollId, result: { not: null } }, include: { couvertureEnregistree: true },
    }),
  ]);
  const liste: ResultatRegle[] = [];
  for (const p of paris) { const r = versResultat('pari', p as MiseLue); if (r) liste.push(r); }
  for (const c of combines) { const r = versResultat('combine', c as MiseLue); if (r) liste.push(r); }
  return liste.sort((a, b) => a.le.getTime() - b.le.getTime());
}

/** Combien de points la courbe envoie au plus. */
export const COURBE_POINTS_MAX = 200;

/**
 * Le résultat net cumulé, mise après mise.
 *
 * Le cumul part de zéro et porte sur tout l'historique. Au-delà de
 * [max] mises, seules les dernières sont envoyées, et `cumul_depart` donne le cumul
 * qui les précède : la courbe reprend là où elle en était, au lieu de
 * repartir de zéro.
 */
export function courbeResultats(liste: ResultatRegle[], max = COURBE_POINTS_MAX) {
  let cumul = 0;
  const points = liste.map((r) => {
    cumul += r.net;
    return { le: r.le.toISOString(), cumul: arrondi(cumul), genre: r.genre };
  });
  const gardes = points.slice(-max);
  const omis = points.length - gardes.length;
  return {
    reglees: liste.length,
    cumul_depart: omis > 0 ? points[omis - 1].cumul : 0,
    points: gardes,
  };
}

/**
 * Les sept derniers jours, d'après la date du **règlement**.
 *
 * L'écran retenait les paris posés dans la semaine. Un pari posé il y a dix
 * jours et gagné hier n'entrait pas dans « Cette semaine », alors que son gain
 * venait d'arriver.
 */
export function bilanSemaine(liste: ResultatRegle[], maintenant: Date = new Date()) {
  const depuis = maintenant.getTime() - 7 * JOUR_MS;
  const semaine = liste.filter((r) => r.le.getTime() >= depuis);
  const paris = semaine.filter((r) => r.genre === 'pari');
  const combines = semaine.filter((r) => r.genre === 'combine');
  return {
    paris: paris.length,
    gagnes: paris.filter((r) => r.result === 'WIN').length,
    perdus: paris.filter((r) => r.result === 'LOSS').length,
    rembourses: paris.filter((r) => r.result === 'PUSH').length,
    combines: combines.length,
    combines_gagnes: combines.filter((r) => r.result === 'WIN').length,
    profit: arrondi(semaine.reduce((n, r) => n + r.net, 0)),
  };
}

/**
 * Le gain net et ce qui a été exposé, sur tout l'historique : la base du
 * rendement.
 */
export function totaux(liste: ResultatRegle[]) {
  return {
    profit: arrondi(liste.reduce((n, r) => n + r.net, 0)),
    mise: arrondi(liste.reduce((n, r) => n + r.mise, 0)),
  };
}

/**
 * Le solde disponible à la fin de chacun des [jours] derniers jours (UTC,
 * l'heure de Ouagadougou), d'après le journal des mouvements.
 *
 * La courbe partait du solde actuel moins les gains et pertes des paris
 * réglés. Elle ignorait les mises en cours, les réinitialisations, les
 * changements de budget, les combinés et les couvertures. Le journal les a
 * tous : la somme des mouvements jusqu'à un instant vaut le solde à cet
 * instant, puisque la ligne « reprise » ou « ouverture » pose le solde de
 * départ.
 *
 * Les jours d'avant la bankroll ne sont pas envoyés : un zéro suivi du budget
 * se serait lu comme un gain.
 */
export async function historiqueSolde(
  bankrollId: string, devise: string, maintenant: Date = new Date(), jours = 30,
) {
  const aujourdhui = Date.UTC(maintenant.getUTCFullYear(), maintenant.getUTCMonth(), maintenant.getUTCDate());
  const premier = new Date(aujourdhui - jours * JOUR_MS);
  const [avant, anterieurs, mouvements] = await Promise.all([
    prisma.bankrollMouvement.aggregate({ where: { bankrollId, creeLe: { lt: premier } }, _sum: { montant: true } }),
    prisma.bankrollMouvement.count({ where: { bankrollId, creeLe: { lt: premier } } }),
    prisma.bankrollMouvement.findMany({ where: { bankrollId, creeLe: { gte: premier } }, orderBy: { creeLe: 'asc' } }),
  ]);

  let solde = avant._sum.montant ?? 0;
  let ouverte = anterieurs > 0;
  let i = 0;
  const points: { date: string; balance: number }[] = [];
  for (let j = 0; j <= jours; j++) {
    const debut = premier.getTime() + j * JOUR_MS;
    const fin = debut + JOUR_MS;
    while (i < mouvements.length && mouvements[i].creeLe.getTime() < fin) {
      solde += mouvements[i].montant;
      i++;
      ouverte = true;
    }
    if (!ouverte) continue;
    points.push({ date: new Date(debut).toISOString().slice(0, 10), balance: soldeExact(solde, devise) });
  }
  return points;
}

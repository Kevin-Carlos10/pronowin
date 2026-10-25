import { prisma } from '../lib/prisma';
import { TITRE_COMPOSITIONS } from './alertes_compositions.service';
import { TITRE_RESUME_PRET } from './resumes_match.service';

/**
 * L'engagement, sur le tableau de bord du panneau (25 octobre 2026).
 *
 * Bulle de la cloche, avant-matchs, « Le résumé est prêt » : ces nouveautés
 * doivent faire suivre des matchs et revenir dans l'application. Ces chiffres
 * ne s'obtenaient qu'en interrogeant la base à la main ; les voici sur une
 * carte : les matchs suivis, les notifications par famille et la part lue,
 * les articles écrits seuls, l'adoption des versions, les paiements Mobile
 * Money.
 *
 * ── Ce que « lue » veut dire ───────────────────────────────────────────────
 *
 * Une notification est marquée lue quand on la touche dans la liste de
 * l'application, ou qu'on vide la liste. Toucher la notification push
 * elle-même ne le dit pas au serveur : la part lue est donc un minimum.
 */

/** Une famille de notifications, reconnue à son titre (français, celui qu'on enregistre). */
type Famille = { cle: string; libelle: string; reconnait: (titre: string) => boolean };

const FAMILLES: Famille[] = [
  { cle: 'buts',         libelle: 'Buts',                     reconnait: t => t.startsWith('But pour ') },
  { cle: 'buts_annules', libelle: 'Buts annulés, score corrigé', reconnait: t => t.startsWith('But annulé') || t === 'Score mis à jour' },
  { cle: 'coup_envoi',   libelle: "Coups d'envoi",            reconnait: t => t === 'Match en direct !' },
  { cle: 'mi_temps',     libelle: 'Mi-temps',                 reconnait: t => t === 'Mi-temps' },
  { cle: 'cartons',      libelle: 'Cartons rouges',           reconnait: t => t.startsWith('Carton rouge') },
  { cle: 'compositions', libelle: 'Compositions officielles', reconnait: t => t === TITRE_COMPOSITIONS },
  { cle: 'fin_match',    libelle: 'Fins de match',            reconnait: t => t.startsWith('Fin de match') },
  { cle: 'resume_pret',  libelle: 'Résumé prêt',              reconnait: t => t === TITRE_RESUME_PRET },
  { cle: 'resultats',    libelle: 'Résultats des pronostics',
    reconnait: t => /^(Pronostic (gagnant|perdant|remboursé)|Résultat corrigé|Sélection modifiée)/.test(t) },
  { cle: 'premium',      libelle: 'Premium',                  reconnait: t => /Premium|Preuve/.test(t) },
];

/** La famille d'une notification, d'après son titre ; « autres » sinon. */
export function familleNotification(titre: string): { cle: string; libelle: string } {
  const f = FAMILLES.find(x => x.reconnait(titre));
  return f ? { cle: f.cle, libelle: f.libelle } : { cle: 'autres', libelle: 'Autres (campagnes, parrainage…)' };
}

/** « 1.0.30 » > « 1.0.9 » : comparaison nombre par nombre. */
export function compareVersions(a: string, b: string): number {
  const pa = a.split('.').map(n => parseInt(n, 10) || 0), pb = b.split('.').map(n => parseInt(n, 10) || 0);
  for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
    const d = (pa[i] ?? 0) - (pb[i] ?? 0);
    if (d !== 0) return d;
  }
  return 0;
}

const JOUR = 86_400_000;
/** Un appareil vu dans les 30 derniers jours compte dans l'adoption des versions. */
const VERSIONS_VUES_MS = 30 * JOUR;
export const PERIODES_ENGAGEMENT = [7, 30];

export async function resumeEngagement(o: { jours?: number } = {}, maintenant = new Date()) {
  const jours = PERIODES_ENGAGEMENT.includes(o.jours ?? 7) ? (o.jours ?? 7) : 7;
  const depuis = new Date(maintenant.getTime() - jours * JOUR);

  const [suivisActifs, nouveauxSuivis, notifs, resumes, avantMatchs, versions, mobileMoney] = await Promise.all([
    // Les suivis qui servent encore : matchs à venir ou en cours.
    prisma.userFavoriteMatch.findMany({
      where:  { match: { status: { in: ['SCHEDULED', 'LIVE'] } } },
      select: { userId: true, matchId: true },
    }),
    prisma.userFavoriteMatch.findMany({
      where:  { createdAt: { gte: depuis } },
      select: { userId: true },
    }),
    prisma.notification.groupBy({
      by: ['title', 'isRead'], where: { createdAt: { gte: depuis } }, _count: { _all: true },
    }),
    prisma.resumeMatch.count({ where: { genre: 'resume', creeLe: { gte: depuis } } }),
    prisma.resumeMatch.count({ where: { genre: 'avant_match', creeLe: { gte: depuis } } }),
    prisma.versionAppCompte.groupBy({
      by: ['plateforme', 'canal', 'version'],
      where: { vuLe: { gte: new Date(maintenant.getTime() - VERSIONS_VUES_MS) } },
      _count: { _all: true },
    }),
    prisma.paiementGeniusPay.aggregate({
      where: { environnement: 'live', premiumAccordeLe: { gte: depuis } },
      _count: { _all: true }, _sum: { montant: true },
    }),
  ]);

  // ── Notifications, par famille ──
  const parFamille = new Map<string, { cle: string; libelle: string; creees: number; lues: number }>();
  let creees = 0, lues = 0;
  for (const g of notifs) {
    const f = familleNotification(g.title);
    const ligne = parFamille.get(f.cle) ?? { ...f, creees: 0, lues: 0 };
    ligne.creees += g._count._all;
    if (g.isRead) ligne.lues += g._count._all;
    parFamille.set(f.cle, ligne);
    creees += g._count._all;
    if (g.isRead) lues += g._count._all;
  }
  const familles = [...parFamille.values()].sort((a, b) => b.creees - a.creees);

  // ── Versions : la plus récente vue, et qui l'a ──
  const cible = versions.map(v => v.version).sort(compareVersions).pop() ?? null;
  const canaux = new Map<string, { plateforme: string; canal: string | null; comptes: number; aJour: number;
    versions: Array<{ version: string; comptes: number }> }>();
  for (const v of versions) {
    const cle = `${v.plateforme}|${v.canal ?? ''}`;
    const c = canaux.get(cle) ?? { plateforme: v.plateforme, canal: v.canal, comptes: 0, aJour: 0, versions: [] };
    c.comptes += v._count._all;
    if (cible && v.version === cible) c.aJour += v._count._all;
    c.versions.push({ version: v.version, comptes: v._count._all });
    canaux.set(cle, c);
  }
  const parCanal = [...canaux.values()]
    .map(c => ({ ...c, versions: c.versions.sort((a, b) => compareVersions(b.version, a.version)) }))
    .sort((a, b) => b.comptes - a.comptes);

  return {
    jours,
    suivis: {
      matchs:     new Set(suivisActifs.map(s => s.matchId)).size,
      personnes:  new Set(suivisActifs.map(s => s.userId)).size,
      nouveaux:   nouveauxSuivis.length,
      nouveauxPersonnes: new Set(nouveauxSuivis.map(s => s.userId)).size,
    },
    notifications: { creees, lues, familles },
    contenus: { resumes, avantMatchs },
    versions: {
      cible,
      comptes: parCanal.reduce((s, c) => s + c.comptes, 0),
      aJour:   parCanal.reduce((s, c) => s + c.aJour, 0),
      parCanal,
    },
    mobileMoney: { payes: mobileMoney._count._all, brut: mobileMoney._sum.montant ?? 0 },
  };
}

export type ResumeEngagement = Awaited<ReturnType<typeof resumeEngagement>>;

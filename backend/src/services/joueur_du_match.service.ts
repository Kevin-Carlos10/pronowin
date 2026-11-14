/**
 * « Joueur du match » — le vote des fans (8 novembre 2026), comme la
 * « Course au Joueur du Match » de Sofascore : « Le vote des fans s'ouvre à
 * la 80e minute ».
 *
 * Avant la 80e minute, la fiche montre la course aux notes du fournisseur ;
 * ensuite, chacun désigne un joueur, et voit la répartition. Ouvert jusqu'à
 * trente heures après le coup d'envoi, puis clos ; le résultat reste visible.
 * Un vote par compte et par match, modifiable tant que c'est ouvert.
 *
 * Le joueur est retrouvé dans les notes du match (`/fixtures/players`) : son
 * nom vient du fournisseur, jamais du téléphone — personne ne peut afficher
 * un nom inventé dans le classement que tout le monde lit. Ce n'est pas un
 * pari : rien n'est misé, aucune cote.
 */
import { prisma } from '../lib/prisma';
import { ErreurMetier, ServiceIndisponible } from '../utils/erreurs';
import { pourcentages } from './votes_match.service';

export const MINUTE_OUVERTURE = 80;
/** Après le coup d'envoi : de quoi couvrir le match et le lendemain matin. */
export const DUREE_OUVERTURE_H = 30;
const CLASSEMENT_MAX = 5;

export type EtatVoteJoueur = 'bientot' | 'ouvert' | 'clos' | 'indisponible';

type MatchVote = {
  id: string; status: string; matchDate: Date; elapsedMinutes: number | null;
  source: string; externalId: number | null;
};

/** Le joueur tel que le fournisseur le note. */
export type JoueurNote = { id: number | null; name: string; team: 'home' | 'away' };

/** Les joueurs notés du match : remplaçable pour les tests. */
let lireJoueurs = async (m: MatchVote): Promise<JoueurNote[] | null> => {
  if (m.source !== 'API_FOOTBALL' || !m.externalId) return null;
  const { apiFootballInsights } = await import('./api_football.service');
  return apiFootballInsights.getPlayerRatings(m.externalId, undefined, m.status === 'LIVE');
};
export function remplacerLecteurJoueurs(f: typeof lireJoueurs): void { lireJoueurs = f; }

async function matchDe(id: string): Promise<MatchVote | null> {
  const select = { id: true, status: true, matchDate: true, elapsedMinutes: true, source: true, externalId: true } as const;
  return (await prisma.match.findUnique({ where: { id }, select }))
    ?? (await prisma.pronostic.findUnique({ where: { id }, select: { match: { select } } }))?.match
    ?? null;
}

export function etatVote(m: Pick<MatchVote, 'status' | 'matchDate' | 'elapsedMinutes'>, maintenant = new Date()): EtatVoteJoueur {
  if (m.status === 'LIVE') return (m.elapsedMinutes ?? 0) >= MINUTE_OUVERTURE ? 'ouvert' : 'bientot';
  if (m.status === 'FINISHED') {
    return maintenant.getTime() - m.matchDate.getTime() <= DUREE_OUVERTURE_H * 3600_000 ? 'ouvert' : 'clos';
  }
  return 'indisponible';
}

/** Des pourcentages entiers dont la somme fait 100, pour n joueurs. */
function repartition(compte: number[]): number[] {
  if (compte.length === 0) return [];
  if (compte.length <= 3) {
    const trois = [...compte, 0, 0, 0].slice(0, 3) as [number, number, number];
    return pourcentages(trois).slice(0, compte.length);
  }
  const total = compte.reduce((a, b) => a + b, 0);
  if (!total) return compte.map(() => 0);
  const exacts = compte.map(n => n / total * 100);
  const entiers = exacts.map(Math.floor);
  const reste = 100 - entiers.reduce((a, b) => a + b, 0);
  const ordre = compte.map((_, i) => i).sort((a, b) => (exacts[b] - entiers[b]) - (exacts[a] - entiers[a]));
  for (let k = 0; k < reste; k++) entiers[ordre[k]]++;
  return entiers;
}

export async function resumeJoueurDuMatch(id: string, userId?: string | null, maintenant = new Date()) {
  const match = await matchDe(id);
  if (!match) return null;
  const [groupes, mien] = await Promise.all([
    prisma.voteJoueurDuMatch.groupBy({
      by: ['joueurId', 'joueurNom', 'equipe'], where: { matchId: match.id }, _count: { _all: true },
    }),
    userId
      ? prisma.voteJoueurDuMatch.findUnique({ where: { matchId_userId: { matchId: match.id, userId } }, select: { joueurId: true } })
      : Promise.resolve(null),
  ]);
  const tries = [...groupes].sort((a, b) => b._count._all - a._count._all || a.joueurNom.localeCompare(b.joueurNom));
  const total = tries.reduce((n, g) => n + g._count._all, 0);
  // Les pourcentages portent sur tous les votes, pas seulement les premiers.
  const pcts = repartition(tries.map(g => g._count._all));
  return {
    etat: etatVote(match, maintenant),
    minute_ouverture: MINUTE_OUVERTURE,
    total,
    classement: tries.slice(0, CLASSEMENT_MAX).map((g, i) => ({
      joueur_id: g.joueurId, nom: g.joueurNom, equipe: g.equipe, votes: g._count._all, pourcentage: pcts[i],
    })),
    mon_vote: mien?.joueurId ?? null,
  };
}

/** Vote, ou change son vote, tant que c'est ouvert ; rend le résumé. */
export async function voterJoueur(id: string, userId: string, joueurId: unknown, maintenant = new Date()) {
  const jid = typeof joueurId === 'number' ? joueurId : typeof joueurId === 'string' ? Number(joueurId) : NaN;
  if (!Number.isInteger(jid) || jid <= 0) throw new ErreurMetier('Joueur invalide.', 422);
  const match = await matchDe(id);
  if (!match) throw new ErreurMetier('Match introuvable.', 404);
  const etat = etatVote(match, maintenant);
  if (etat !== 'ouvert') {
    throw new ErreurMetier(etat === 'bientot'
      ? `Le vote s'ouvre à la ${MINUTE_OUVERTURE}e minute.`
      : 'Le vote est clos pour ce match.', 409);
  }
  const joueurs = await lireJoueurs(match);
  if (!joueurs) throw new ServiceIndisponible('Les joueurs du match sont momentanément indisponibles. Réessaie dans un instant.');
  const joueur = joueurs.find(j => j.id === jid);
  if (!joueur) throw new ErreurMetier('Ce joueur n’a pas joué ce match.', 422);
  await prisma.voteJoueurDuMatch.upsert({
    where:  { matchId_userId: { matchId: match.id, userId } },
    create: { matchId: match.id, userId, joueurId: jid, joueurNom: joueur.name.slice(0, 80), equipe: joueur.team },
    update: { joueurId: jid, joueurNom: joueur.name.slice(0, 80), equipe: joueur.team },
  });
  return (await resumeJoueurDuMatch(match.id, userId, maintenant))!;
}

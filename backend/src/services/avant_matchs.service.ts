/**
 * Avant-matchs automatiques (22 octobre 2026).
 *
 * Les résumés donnaient à la page Actus du contenu après les matchs, rien
 * avant. FotMob et Sofascore publient la veille un « avant-match » : la place
 * des deux équipes, leur forme, leurs dernières confrontations, les absents.
 * Ces données, nous les avons déjà pour la fiche du match ; on les écrit en
 * quelques phrases, dans les deux langues.
 *
 *   « Avant-match : Arsenal (2e) reçoit Chelsea (5e) »
 *   Premier League. Arsenal, 2e avec 17 points, reçoit Chelsea, 5e avec 14
 *   points.
 *   Arsenal : 4 victoires et 1 nul sur ses cinq derniers matchs (dernier :
 *   victoire 2-0 contre Fulham). Chelsea : …
 *
 * Les mêmes matchs que les résumés : ceux dont le pronostic est publié, et
 * ceux des grandes compétitions. Écrit entre 30 h et 1 h avant le coup
 * d'envoi ; dans le fil jusqu'au coup d'envoi — le résumé prend le relais.
 * Même table que les résumés (genre « avant_match ») : le panneau les corrige
 * et les retire de la même façon.
 *
 * ── Ce qui n'est jamais écrit ──────────────────────────────────────────────
 *
 * Le pronostic : l'article dit seulement qu'il est sur la fiche du match, VIP
 * ou non. Aucun mot de pari : le texte s'affiche aussi sur iPhone.
 */
import { prisma } from '../lib/prisma';
import { country } from '../i18n/football';
import { apiFootballService } from './api_football.service';
import type { MatchRecent } from './forme_recente.service';
import { GRANDES_COMPETITIONS, de, type Resume } from './resumes_match.service';
import { journal } from '../utils/logger';

type Langue = 'fr' | 'en';
type Camp = 'dom' | 'ext';

export interface Absent { nom: string; statut: 'absent' | 'suspendu' | 'incertain' }

/** Ce qu'il faut pour écrire un avant-match. Chaque bloc est null s'il manque. */
export interface DonneesAvantMatch {
  domicile: string;
  exterieur: string;
  competition: string;
  classement: Record<Camp, { rang: number; points: number }> | null;
  /** Les cinq derniers matchs terminés, du plus récent au plus ancien. */
  forme: Record<Camp, MatchRecent[]> | null;
  h2h: {
    joues: number; dom: number; ext: number; nuls: number;
    /** La dernière rencontre terminée, vue de nos deux équipes. */
    derniere: { date: string; recevait: Camp; butsDom: number; butsExt: number } | null;
  } | null;
  absents: Record<Camp, Absent[]> | null;
  /** Un pronostic publié : l'article renvoie à la fiche, sans le dévoiler. */
  pronostic: boolean;
}

// ─── Rédaction ───────────────────────────────────────────────────────────────

const ordinal = (n: number, langue: Langue) => {
  if (langue === 'fr') return n === 1 ? '1er' : `${n}e`;
  const d = n % 10, c = n % 100;
  return `${n}${c >= 11 && c <= 13 ? 'th' : d === 1 ? 'st' : d === 2 ? 'nd' : d === 3 ? 'rd' : 'th'}`;
};

/** « 0 victoire », « 2 nuls » ; « 0 wins », « 1 draw ». */
const pluriel = (n: number, mot: string, langue: Langue) =>
  `${n} ${mot}${(langue === 'fr' ? n > 1 : n !== 1) ? 's' : ''}`;

/** « a, b et c » / « a, b and c ». */
const enumerer = (morceaux: string[], langue: Langue) => morceaux.length <= 1 ? morceaux.join('')
  : `${morceaux.slice(0, -1).join(', ')} ${langue === 'fr' ? 'et' : 'and'} ${morceaux[morceaux.length - 1]}`;

const NOMBRES = {
  fr: ['', 'un', 'deux', 'trois', 'quatre', 'cinq'],
  en: ['', 'one', 'two', 'three', 'four', 'five'],
};

function phraseForme(nom: string, matchs: MatchRecent[], langue: Langue): string | null {
  if (!matchs.length) return null;
  const fr = langue === 'fr';
  const v = matchs.filter(m => m.issue === 'V').length;
  const n = matchs.filter(m => m.issue === 'N').length;
  const d = matchs.filter(m => m.issue === 'D').length;
  const bilan = enumerer([
    v ? pluriel(v, fr ? 'victoire' : 'win', langue) : '',
    n ? pluriel(n, fr ? 'nul' : 'draw', langue) : '',
    d ? pluriel(d, fr ? 'défaite' : 'defeat', langue) : '',
  ].filter(Boolean), langue);
  const combien = matchs.length === 1
    ? (fr ? 'sur son dernier match' : 'in their last match')
    : (fr ? `sur ses ${NOMBRES.fr[matchs.length]} derniers matchs` : `in their last ${NOMBRES.en[matchs.length]}`);
  const [dernier] = matchs;
  const adv = country(dernier.adversaire, langue);
  const score = `${dernier.butsPour}-${dernier.butsContre}`;
  const issue = fr
    ? { V: `victoire ${score} contre ${adv}`, N: `nul ${score} face à ${adv}`, D: `défaite ${score} contre ${adv}` }[dernier.issue]
    : { V: `won ${score} v ${adv}`, N: `drew ${score} with ${adv}`, D: `lost ${score} to ${adv}` }[dernier.issue];
  return fr
    ? `${nom} : ${bilan} ${combien} (dernier : ${issue}).`
    : `${nom}: ${bilan} ${combien} (latest: ${issue}).`;
}

const PLUS_D_ABSENTS = 6;

function listeAbsents(absents: Absent[], langue: Langue): string {
  const fr = langue === 'fr';
  if (!absents.length) return fr ? 'aucun signalé' : 'none reported';
  const qualif = (a: Absent) => a.statut === 'absent' ? ''
    : fr ? ` (${a.statut})` : a.statut === 'suspendu' ? ' (suspended)' : ' (doubtful)';
  const noms = absents.slice(0, PLUS_D_ABSENTS).map(a => a.nom + qualif(a));
  const reste = absents.length - noms.length;
  if (reste > 0) noms.push(fr ? `${reste} autre${reste > 1 ? 's' : ''}` : `${reste} other${reste > 1 ? 's' : ''}`);
  return enumerer(noms, langue);
}

const moisAnnee = (iso: string, langue: Langue) => new Date(iso).toLocaleDateString(
  langue === 'fr' ? 'fr-FR' : 'en-GB', { month: 'long', year: 'numeric', timeZone: 'UTC' });

function titre(d: DonneesAvantMatch, langue: Langue): string {
  const dom = country(d.domicile, langue), ext = country(d.exterieur, langue);
  const c = d.classement;
  if (langue === 'fr') {
    return c ? `Avant-match : ${dom} (${ordinal(c.dom.rang, 'fr')}) reçoit ${ext} (${ordinal(c.ext.rang, 'fr')})`
      : `Avant-match : ${dom} – ${ext}`;
  }
  return c ? `Preview: ${dom} (${ordinal(c.dom.rang, 'en')}) host ${ext} (${ordinal(c.ext.rang, 'en')})`
    : `Preview: ${dom} v ${ext}`;
}

function corps(d: DonneesAvantMatch, langue: Langue): string {
  const fr = langue === 'fr';
  const dom = country(d.domicile, langue), ext = country(d.exterieur, langue);
  const paragraphes: string[] = [];

  const c = d.classement;
  const pts = (n: number) => pluriel(n, fr ? 'point' : 'point', langue);
  paragraphes.push(c
    ? (fr ? `${d.competition}. ${dom}, ${ordinal(c.dom.rang, 'fr')} avec ${pts(c.dom.points)}, reçoit ${ext}, ${ordinal(c.ext.rang, 'fr')} avec ${pts(c.ext.points)}.`
      : `${d.competition}. ${dom}, ${ordinal(c.dom.rang, 'en')} on ${pts(c.dom.points)}, host ${ext}, ${ordinal(c.ext.rang, 'en')} on ${pts(c.ext.points)}.`)
    : (fr ? `${d.competition}. ${dom} reçoit ${ext}.` : `${d.competition}. ${dom} host ${ext}.`));

  if (d.forme) {
    const phrases = [phraseForme(dom, d.forme.dom, langue), phraseForme(ext, d.forme.ext, langue)].filter(Boolean);
    if (phrases.length) paragraphes.push(phrases.join(' '));
  }

  const h = d.h2h;
  if (h) {
    if (h.joues === 0) {
      // Pas « jamais » : l'historique du fournisseur a des trous (Shakhtar
      // Donetsk – Sporting CP, essai du 22 octobre 2026).
      paragraphes.push(fr ? 'Aucune confrontation récente entre les deux équipes.' : 'The two sides have not met recently.');
    } else {
      // Les zéros se taisent : « 3 victoires d'Arsenal et 2 nuls ».
      const bilan = fr
        ? `Face-à-face (${h.joues === 1 ? 'dernière rencontre' : `${h.joues} dernières rencontres`}) : `
          + enumerer([
            h.dom ? `${pluriel(h.dom, 'victoire', 'fr')} ${de(dom)}` : '',
            h.ext ? `${pluriel(h.ext, 'victoire', 'fr')} ${de(ext)}` : '',
            h.nuls ? pluriel(h.nuls, 'nul', 'fr') : '',
          ].filter(Boolean), 'fr') + '.'
        : `Head to head (${h.joues === 1 ? 'last meeting' : `last ${h.joues} meetings`}): `
          + enumerer([
            h.dom ? `${pluriel(h.dom, 'win', 'en')} for ${dom}` : '',
            h.ext ? `${pluriel(h.ext, 'win', 'en')} for ${ext}` : '',
            h.nuls ? pluriel(h.nuls, 'draw', 'en') : '',
          ].filter(Boolean), 'en') + '.';
      const r = h.derniere;
      const derniere = r && (() => {
        const [hote, invite, bh, bi] = r.recevait === 'dom' ? [dom, ext, r.butsDom, r.butsExt] : [ext, dom, r.butsExt, r.butsDom];
        return fr ? ` Dernière rencontre : ${hote} ${bh}-${bi} ${invite} (${moisAnnee(r.date, 'fr')}).`
          : ` Last meeting: ${hote} ${bh}-${bi} ${invite} (${moisAnnee(r.date, 'en')}).`;
      })();
      paragraphes.push(bilan + (derniere ?? ''));
    }
  }

  const a = d.absents;
  if (a) {
    // « Absents — Ipswich : S. Lukic (incertain) » se contredisait.
    const incertains = [...a.dom, ...a.ext].some(x => x.statut === 'incertain');
    const entete = fr ? (incertains ? 'Absents ou incertains' : 'Absents')
      : (incertains ? 'Missing or doubtful' : 'Unavailable');
    paragraphes.push(!a.dom.length && !a.ext.length
      ? (fr ? 'Aucun absent signalé pour l\'instant.' : 'No absentees reported so far.')
      : (fr ? `${entete} — ${dom} : ${listeAbsents(a.dom, 'fr')} · ${ext} : ${listeAbsents(a.ext, 'fr')}.`
        : `${entete} — ${dom}: ${listeAbsents(a.dom, 'en')} · ${ext}: ${listeAbsents(a.ext, 'en')}.`));
  }

  if (d.pronostic) {
    paragraphes.push(fr ? 'Le pronostic PronoWin de ce match est sur sa fiche.'
      : 'PronoWin\'s prediction for this match is on its page.');
  }
  return paragraphes.join('\n\n');
}

/**
 * L'avant-match, ou null s'il n'y a pas de quoi l'écrire : il faut au moins
 * deux des trois blocs classement, forme des deux équipes, face-à-face.
 */
export function redigerAvantMatch(d: DonneesAvantMatch): Resume | null {
  const blocs = [
    d.classement !== null,
    d.forme !== null && d.forme.dom.length > 0 && d.forme.ext.length > 0,
    d.h2h !== null,
  ].filter(Boolean).length;
  if (blocs < 2) return null;
  return {
    titre: titre(d, 'fr'), titreEn: titre(d, 'en'),
    resume: corps(d, 'fr'), resumeEn: corps(d, 'en'),
  };
}

// ─── Données ─────────────────────────────────────────────────────────────────

/** Ce que les appels au fournisseur renvoient, rangé par camp. Null si le match lui est inconnu. */
export async function donneesAvantMatch(m: {
  externalId: number; homeTeam: string; awayTeam: string; league: string; leagueCode: string; matchDate: Date;
  pronosticPublie: boolean;
}): Promise<DonneesAvantMatch | null> {
  const svc = apiFootballService;
  const jour = m.matchDate.toISOString().slice(0, 10);
  const [classement, forme, h2h, absents] = await Promise.all([
    svc.getStandings(m.leagueCode, m.matchDate, m.externalId).catch(() => null),
    svc.getFormeRecente(m.externalId).catch(() => null),
    svc.getH2H(m.homeTeam, m.awayTeam, jour, 5, m.externalId).catch(() => null),
    svc.getInjuries(m.homeTeam, m.awayTeam, jour, m.externalId).catch(() => null),
  ]);
  if (!forme && !h2h && (!classement || classement.status !== 'available')) return null;

  // Le classement : les deux équipes dans le même groupe, sinon rien.
  let rangs: DonneesAvantMatch['classement'] = null;
  if (classement?.status === 'available') {
    const idDom = h2h?.aggregates.homeTeam.id, idExt = h2h?.aggregates.awayTeam.id;
    const ligne = (id: number | undefined, nom: string) => classement.rows.find(r =>
      r.isMatchTeam !== false && (id ? r.teamId === id : r.teamName === nom));
    const ld = ligne(idDom, m.homeTeam), le = ligne(idExt, m.awayTeam);
    if (ld && le && ld.groupId === le.groupId) {
      rangs = { dom: { rang: ld.rank, points: ld.points }, ext: { rang: le.rank, points: le.points } };
    }
  }

  let faceAFace: DonneesAvantMatch['h2h'] = null;
  if (h2h) {
    const idDom = h2h.aggregates.homeTeam.id;
    const termines = h2h.matches
      .filter(x => x.status === 'FINISHED' && x.score.fullTime.home !== null && x.score.fullTime.away !== null)
      .sort((a, b) => b.utcDate.localeCompare(a.utcDate));
    const r = termines[0];
    faceAFace = {
      joues: h2h.aggregates.numberOfMatches,
      dom: h2h.aggregates.homeTeam.wins, ext: h2h.aggregates.awayTeam.wins, nuls: h2h.aggregates.homeTeam.draws,
      derniere: r ? {
        date: r.utcDate,
        recevait: r.homeTeam.id === idDom ? 'dom' : 'ext',
        butsDom: (r.homeTeam.id === idDom ? r.score.fullTime.home : r.score.fullTime.away) as number,
        butsExt: (r.homeTeam.id === idDom ? r.score.fullTime.away : r.score.fullTime.home) as number,
      } : null,
    };
  }

  const absent = (p: { name: string; type: string; suspension: boolean }): Absent => ({
    nom: p.name,
    statut: p.suspension ? 'suspendu' : p.type === 'Questionable' ? 'incertain' : 'absent',
  });

  return {
    domicile: m.homeTeam, exterieur: m.awayTeam, competition: m.league,
    classement: rangs,
    forme: forme ? { dom: forme.home, ext: forme.away } : null,
    h2h: faceAFace,
    absents: absents ? {
      dom: absents.filter(p => p.team === 'home').map(absent),
      ext: absents.filter(p => p.team === 'away').map(absent),
    } : null,
    pronostic: m.pronosticPublie,
  };
}

// ─── Publication ─────────────────────────────────────────────────────────────

/** Fenêtre : coup d'envoi dans 1 h à 30 h. */
const AVANT_MIN_MS = 3600_000;
const AVANT_MAX_MS = 30 * 3600_000;
const PAR_PASSAGE = 4;
const CANDIDATS = 40;
/** Pas de quoi écrire, ou fournisseur muet : on réessaie deux heures plus tard. */
const REESSAI_MS = 2 * 3600_000;

const essaisManques = new Map<string, number>();

/** Pour les tests. */
export function _oublierEssais(): void { essaisManques.clear(); }

/**
 * Rédige les avant-matchs manquants. Appelée toutes les 15 minutes ; quatre
 * matchs au plus par passage, les plus proches du coup d'envoi d'abord, les
 * matchs pronostiqués avant les autres. Six appels au fournisseur par match
 * environ, la plupart déjà en cache pour la fiche.
 */
export async function publierAvantMatchs(maintenant = new Date()): Promise<{ publies: number }> {
  const t = maintenant.getTime();
  const candidats = await prisma.match.findMany({
    where: {
      status:    'SCHEDULED',
      source:    'API_FOOTBALL',
      matchDate: { gt: new Date(t + AVANT_MIN_MS), lte: new Date(t + AVANT_MAX_MS) },
      articles:  { none: { genre: 'avant_match' } },
      OR: [
        { pronostic: { publicationRecordedAt: { not: null } } },
        { leagueCode: { in: GRANDES_COMPETITIONS } },
      ],
    },
    include: { pronostic: { select: { isPublished: true } } },
    orderBy: { matchDate: 'asc' },
    take: CANDIDATS,
  });
  const publie = (m: (typeof candidats)[number]) => m.pronostic?.isPublished === true;
  const file = [...candidats.filter(publie), ...candidats.filter(m => !publie(m))];

  let publies = 0, essais = 0;
  for (const m of file) {
    if (essais >= PAR_PASSAGE) break;
    const manque = essaisManques.get(m.id);
    if (manque !== undefined && t - manque < REESSAI_MS) continue;
    essais++;
    const donnees = await donneesAvantMatch({ ...m, pronosticPublie: publie(m) }).catch((e: Error) => {
      journal.warn(`[Avant-matchs] ${m.externalId} : ${e.message}`);
      return null;
    });
    const article = donnees && redigerAvantMatch(donnees);
    if (!article) { essaisManques.set(m.id, t); continue; }
    await prisma.resumeMatch.create({ data: { matchId: m.id, genre: 'avant_match', ligue: m.league, ...article } })
      .then(() => { publies++; essaisManques.delete(m.id); })
      // Deux passages simultanés : le second bute sur l'unicité, sans dommage.
      .catch((e: any) => journal.warn(`[Avant-matchs] ${m.id} : ${e.message}`));
  }
  if (publies) journal.info(`[Avant-matchs] ${publies} avant-match(s) publié(s)`);
  return { publies };
}

/**
 * Les avant-matchs des matchs pas encore commencés, au format des actualités.
 * Ceux des matchs pronostiqués d'abord, s'il faut choisir.
 */
export async function avantMatchsPourActualites(limite = 6, maintenant = new Date()): Promise<any[]> {
  const lus = await prisma.resumeMatch.findMany({
    where:   { genre: 'avant_match', masque: false, match: { matchDate: { gt: maintenant }, status: 'SCHEDULED' } },
    orderBy: { creeLe: 'desc' },
    take:    limite * 3,
    include: { match: { select: { homeTeamLogo: true, awayTeamLogo: true, hasPublishedPronostic: true } } },
  });
  const pronostique = (r: (typeof lus)[number]) => r.match?.hasPublishedPronostic === true;
  return [...lus.filter(pronostique), ...lus.filter(r => !pronostique(r))]
    .slice(0, limite)
    .sort((a, b) => b.creeLe.getTime() - a.creeLe.getTime())
    .map(r => ({
      id:         `avant_match_${r.id}`,
      titre:      r.titre,
      titre_en:   r.titreEn,
      resume:     r.resume,
      resume_en:  r.resumeEn,
      categorie:  r.ligue,
      emoji:      '⚽',
      image_url:  null,
      source_url: null,
      is_pinned:  false,
      created_at: r.creeLe.toISOString(),
      from_rss:   false,
      // « resume_match » : les versions 1.0.25 à 1.0.28 de l'app montrent
      // alors les deux logos et le bouton « Voir le match ». `genre` distingue
      // l'avant-match du résumé pour une prochaine version.
      type:       'resume_match',
      genre:      'avant_match',
      match_id:   r.matchId,
      logo_domicile:  r.match?.homeTeamLogo ?? null,
      logo_exterieur: r.match?.awayTeamLogo ?? null,
      // Pas de score : le match n'a pas commencé.
      score:      null,
    }));
}

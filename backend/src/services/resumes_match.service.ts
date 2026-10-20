/**
 * Résumés automatiques des matchs terminés (18 octobre 2026).
 *
 * Les actualités de l'accueil ne contenaient que le flux de RMC Sport : aucun
 * article n'avait jamais été écrit depuis le panneau. FotMob publie les
 * articles de médias dont il achète les droits ; nous n'en avons pas. Nous
 * avons en revanche, pour chaque match terminé, tout ce qu'il faut pour en
 * écrire un compte rendu : score par période, buteurs, exclusions,
 * statistiques, notes des joueurs. Un contenu à nous, sans question de droits.
 *
 *   « Bayer Leverkusen renverse SC Freiburg (2-1) »
 *   Buts — Bayer Leverkusen : Ibrahim Maza (19'), Patrik Schick (76') ·
 *   SC Freiburg : Derry Lionel Scherhant (14'). …
 *
 * Seuls les matchs dont nous avons publié le pronostic ont un résumé : ce sont
 * ceux que nos utilisateurs suivent, et une dizaine par jour au plus — un
 * appel au fournisseur chacun.
 *
 * ── Ce qui n'est écrit que s'il est sûr ────────────────────────────────────
 *
 * Les buteurs ne sont listés que si les buts relevés redonnent exactement le
 * score final (un but contre son camp se lit des deux façons, on garde celle
 * qui tombe juste). Un pronostic VIP n'est jamais dévoilé : seul son résultat
 * est dit, comme dans l'historique. Aucun mot de pari : le texte s'affiche
 * aussi sur iPhone.
 */
import { prisma } from '../lib/prisma';
import { country, prediction } from '../i18n/football';
import { traduireEquipes } from '../utils/noms_equipes';
import { apiFootballService } from './api_football.service';
import { journal } from '../utils/logger';

type Langue = 'fr' | 'en';
type Camp = 'dom' | 'ext';

export interface ContexteResume {
  domicile: string;
  exterieur: string;
  pronostic?: { libelle: string; libelleEn: string; vip: boolean; resultat: string | null } | null;
}

export interface Resume { titre: string; titreEn: string; resume: string; resumeEn: string }

const TERMINES = new Set(['FT', 'AET', 'PEN']);

const minute = (t: any) =>
  typeof t?.elapsed === 'number' ? `${t.elapsed}${t.extra ? `+${t.extra}` : ''}'` : '';

/** « 8,7 » en français, « 8.7 » en anglais. */
const decimal = (n: number, langue: Langue) => {
  const s = n.toFixed(1);
  return langue === 'fr' ? s.replace('.', ',') : s;
};

interface But { camp: Camp; joueur: string; minute: string; csc: boolean; penalty: boolean }

/**
 * Les buts du match, attribués à l'équipe qui en profite — ou null si les
 * événements ne redonnent pas le score (relevé incomplet).
 *
 * Le fournisseur rattache un but contre son camp tantôt à l'équipe du
 * joueur, tantôt à celle qui en profite : on essaie les deux lectures et on
 * garde celle qui retombe sur le score.
 */
function butsDuMatch(f: any, score: { dom: number; ext: number }): But[] | null {
  const idDom = f.teams?.home?.id, idExt = f.teams?.away?.id;
  const evenements = (f.events ?? []).filter((e: any) =>
    e?.type === 'Goal' && e.detail !== 'Missed Penalty' && e.comments !== 'Penalty Shootout');
  for (const cscPourLAdversaire of [true, false]) {
    const buts: But[] = [];
    for (const e of evenements) {
      const campEquipe: Camp | null = e.team?.id === idDom ? 'dom' : e.team?.id === idExt ? 'ext' : null;
      if (!campEquipe) return null;
      const csc = e.detail === 'Own Goal';
      const camp: Camp = csc && cscPourLAdversaire ? (campEquipe === 'dom' ? 'ext' : 'dom') : campEquipe;
      buts.push({ camp, joueur: e.player?.name?.trim() || '?', minute: minute(e.time), csc, penalty: e.detail === 'Penalty' });
    }
    const dom = buts.filter(b => b.camp === 'dom').length;
    if (dom === score.dom && buts.length - dom === score.ext) return buts;
  }
  return null;
}

function statistique(f: any, camp: Camp, type: string): string | null {
  const id = camp === 'dom' ? f.teams?.home?.id : f.teams?.away?.id;
  const bloc = (f.statistics ?? []).find((s: any) => s?.team?.id === id);
  const v = bloc?.statistics?.find((s: any) => s?.type === type)?.value;
  return v === null || v === undefined || v === '' ? null : String(v);
}

function hommeDuMatch(f: any): { nom: string; note: number } | null {
  let meilleur: { nom: string; note: number } | null = null;
  for (const equipe of f.players ?? []) {
    for (const j of equipe?.players ?? []) {
      const note = parseFloat(j?.statistics?.[0]?.games?.rating);
      if (!Number.isFinite(note) || note <= 0) continue;
      if (!meilleur || note > meilleur.note) meilleur = { nom: j.player?.name ?? '', note };
    }
  }
  return meilleur?.nom ? meilleur : null;
}

const MULTIPLE = {
  fr: ['', '', 'doublé', 'triplé', 'quadruplé'],
  en: ['', '', 'scores twice', 'hat-trick for', 'scores four'],
};

function titre(f: any, ctx: ContexteResume, buts: But[] | null, langue: Langue): string {
  const dom = country(ctx.domicile, langue), ext = country(ctx.exterieur, langue);
  const h = f.goals.home as number, a = f.goals.away as number;
  const statut = f.fixture.status.short;
  const mt = f.score?.halftime;
  const fr = langue === 'fr';

  let t: string;
  if (statut === 'PEN') {
    const ph = f.score?.penalty?.home, pa = f.score?.penalty?.away;
    const domGagne = (ph ?? 0) > (pa ?? 0);
    const [g, p] = domGagne ? [dom, ext] : [ext, dom];
    t = fr
      ? `${g} l'emporte aux tirs au but face à ${p} (${h}-${a}, ${ph}-${pa} t.a.b.)`
      : `${g} win on penalties against ${p} (${h}-${a}, ${ph}-${pa} pens)`;
  } else if (h === a) {
    t = h === 0
      ? (fr ? `${dom} et ${ext} se neutralisent (0-0)` : `Goalless draw between ${dom} and ${ext}`)
      : (fr ? `${dom} et ${ext} dos à dos (${h}-${a})` : `${dom} and ${ext} draw ${h}-${a}`);
  } else {
    const domGagne = h > a;
    const [g, p] = domGagne ? [dom, ext] : [ext, dom];
    const [sg, sp] = domGagne ? [h, a] : [a, h];
    // Mené à la pause, vainqueur à la fin.
    const remontee = mt && typeof mt.home === 'number' && typeof mt.away === 'number'
      && (domGagne ? mt.home < mt.away : mt.away < mt.home);
    const prolongation = statut === 'AET';
    if (fr) {
      const lieu = domGagne ? `face à ${p}` : `chez ${p}`;
      t = remontee ? `${g} renverse ${p} (${h}-${a})`
        : prolongation ? `${g} s'impose après prolongation ${lieu} (${h}-${a})`
        : sg - sp >= 3 ? `${g} s'impose largement ${lieu} (${h}-${a})`
        : `${g} s'impose ${lieu} (${h}-${a})`;
    } else {
      t = remontee ? `${g} come from behind to beat ${p} ${sg}-${sp}`
        : prolongation ? `${g} beat ${p} ${sg}-${sp} after extra time`
        : sg - sp >= 3 ? `${g} thrash ${p} ${sg}-${sp}`
        : domGagne ? `${g} beat ${p} ${sg}-${sp}` : `${g} win ${sg}-${sp} at ${p}`;
    }
  }

  // Le joueur qui a marqué plusieurs fois (hors contre son camp).
  const parJoueur = new Map<string, number>();
  for (const b of buts ?? []) if (!b.csc) parJoueur.set(b.joueur, (parJoueur.get(b.joueur) ?? 0) + 1);
  const [vedette, n] = [...parJoueur.entries()].sort((x, y) => y[1] - x[1])[0] ?? ['', 0];
  if (n >= 2) {
    const mot = MULTIPLE[langue][Math.min(n, 4)];
    t += fr ? `, ${mot} de ${vedette}`
      : n === 3 ? `, ${mot} ${vedette}` : `, ${vedette} ${mot}`;
  }
  return t;
}

function corps(f: any, ctx: ContexteResume, buts: But[] | null, langue: Langue): string {
  const fr = langue === 'fr';
  const nom = (camp: Camp) => country(camp === 'dom' ? ctx.domicile : ctx.exterieur, langue);
  // « Buts : … » en français, « Goals: … » en anglais.
  const sep = fr ? ' : ' : ': ';
  const paragraphes: string[] = [];

  const mt = f.score?.halftime;
  if (typeof mt?.home === 'number' && typeof mt?.away === 'number') {
    paragraphes.push(fr ? `Score à la mi-temps : ${mt.home}-${mt.away}.` : `Half-time: ${mt.home}-${mt.away}.`);
  }

  if (buts && buts.length) {
    const ligne = (camp: Camp) => {
      const liste = buts.filter(b => b.camp === camp).map(b => {
        const precision = b.csc ? (fr ? 'c.s.c., ' : 'o.g., ') : b.penalty ? (fr ? 'pen., ' : 'pen, ') : '';
        return `${b.joueur} (${precision}${b.minute})`;
      });
      return liste.length ? `${nom(camp)}${sep}${liste.join(', ')}` : null;
    };
    const lignes = [ligne('dom'), ligne('ext')].filter(Boolean);
    paragraphes.push(`${fr ? 'Buts' : 'Goals'} — ${lignes.join(' · ')}.`);
  }

  const idDom = f.teams?.home?.id;
  const rouges = (f.events ?? []).filter((e: any) => e?.type === 'Card' && /red/i.test(e.detail ?? ''));
  if (rouges.length) {
    const liste = rouges.map((e: any) =>
      `${e.player?.name ?? '?'} (${nom(e.team?.id === idDom ? 'dom' : 'ext')}, ${minute(e.time)})`);
    paragraphes.push(`${fr ? (rouges.length > 1 ? 'Exclusions' : 'Exclusion') : (rouges.length > 1 ? 'Red cards' : 'Red card')}${sep}${liste.join(', ')}.`);
  }

  const paires = ([
    ['Ball Possession', 'possession'],
    ['Total Shots', fr ? 'tirs' : 'shots'],
    ['Shots on Goal', fr ? 'tirs cadrés' : 'shots on target'],
  ] as const).flatMap(([type, libelle]) => {
    const d = statistique(f, 'dom', type), e = statistique(f, 'ext', type);
    if (d === null || e === null) return [];
    const espace = (v: string) => fr ? v.replace('%', ' %') : v;
    return [`${libelle} ${espace(d)} – ${espace(e)}`];
  });
  if (paires.length) {
    const texte = paires.join(', ');
    paragraphes.push(`${fr ? 'Statistiques' : 'Stats'}${sep}${texte}.`);
  }

  const homme = hommeDuMatch(f);
  if (homme) {
    paragraphes.push(`${fr ? 'Homme du match' : 'Player of the match'}${sep}${homme.nom} (${decimal(homme.note, langue)}).`);
  }

  const p = ctx.pronostic;
  if (p && ['WIN', 'LOSS', 'PUSH'].includes(p.resultat ?? '')) {
    const issue = {
      WIN:  fr ? 'gagnant' : 'won',
      LOSS: fr ? 'perdant' : 'lost',
      PUSH: fr ? 'remboursé' : 'void',
    }[p.resultat as 'WIN' | 'LOSS' | 'PUSH'];
    // Un VIP reste verrouillé : son résultat se dit, pas son choix.
    paragraphes.push(p.vip
      ? (fr ? `Pronostic VIP PronoWin : ${issue}.` : `PronoWin VIP prediction: ${issue}.`)
      // Entre guillemets : un libellé comme « Double chance : Nul / Marseille »
      // a déjà ses deux-points.
      : (fr ? `Pronostic PronoWin : « ${p.libelle} » — ${issue}.` : `PronoWin prediction: "${p.libelleEn}" — ${issue}.`));
  }

  return paragraphes.join('\n\n');
}

/**
 * Le résumé d'un match terminé, ou null si la fiche du fournisseur n'est pas
 * encore celle d'un match fini (statut, score qui ne correspond pas).
 */
export function redigerResume(f: any, ctx: ContexteResume, scoreEnBase?: { dom: number | null; ext: number | null }): Resume | null {
  if (!TERMINES.has(f?.fixture?.status?.short)) return null;
  const h = f.goals?.home, a = f.goals?.away;
  if (typeof h !== 'number' || typeof a !== 'number') return null;
  if (scoreEnBase && (scoreEnBase.dom !== h || scoreEnBase.ext !== a)) return null;
  const buts = butsDuMatch(f, { dom: h, ext: a });
  return {
    titre:    titre(f, ctx, buts, 'fr'),
    titreEn:  titre(f, ctx, buts, 'en'),
    resume:   corps(f, ctx, buts, 'fr'),
    resumeEn: corps(f, ctx, buts, 'en'),
  };
}

/** Fenêtre : matchs commencés il y a 2 h à 48 h. */
const APRES_COUP_ENVOI_MS = 2 * 3600_000;
const FENETRE_MS = 48 * 3600_000;
/** Un pronostic pas encore réglé : on attend jusqu'à 6 h après le coup d'envoi. */
const ATTENTE_REGLEMENT_MS = 6 * 3600_000;
const PAR_PASSAGE = 5;

/**
 * Rédige les résumés manquants. Appelée toutes les 10 minutes ; cinq matchs
 * au plus par passage, un appel au fournisseur chacun.
 */
export async function publierResumes(maintenant = new Date()): Promise<{ publies: number }> {
  const t = maintenant.getTime();
  const candidats = await prisma.match.findMany({
    where: {
      status:    'FINISHED',
      source:    'API_FOOTBALL',
      matchDate: { gte: new Date(t - FENETRE_MS), lte: new Date(t - APRES_COUP_ENVOI_MS) },
      resume:    null,
      pronostic: { publicationRecordedAt: { not: null } },
    },
    include: { pronostic: true },
    orderBy: { matchDate: 'desc' },
    take: PAR_PASSAGE,
  });

  let publies = 0;
  for (const m of candidats) {
    const p = m.pronostic;
    if (p && !p.result && m.matchDate.getTime() > t - ATTENTE_REGLEMENT_MS) continue;
    let fiche: any = null;
    try {
      const r = await apiFootballService.httpClient.get('/fixtures', { params: { id: m.externalId } });
      fiche = (r.data?.response ?? [])[0] ?? null;
    } catch (e: any) {
      journal.warn(`[Résumés] fiche ${m.externalId} indisponible : ${e.message}`);
      continue;
    }
    const resume = fiche && redigerResume(fiche, {
      domicile: m.homeTeam, exterieur: m.awayTeam,
      pronostic: p ? {
        libelle:   traduireEquipes(p.predictionLabel, [m.homeTeam, m.awayTeam]),
        libelleEn: p.predictionLabelEn || prediction(p.predictionLabel, 'en', m.homeTeam, m.awayTeam).text,
        vip: p.isPremium, resultat: p.result,
      } : null,
    }, { dom: m.homeScore, ext: m.awayScore });
    if (!resume) continue;
    await prisma.resumeMatch.create({ data: { matchId: m.id, ligue: m.league, ...resume } })
      .then(() => { publies++; })
      // Deux passages simultanés : le second bute sur l'unicité, sans dommage.
      .catch((e: any) => journal.warn(`[Résumés] ${m.id} : ${e.message}`));
  }
  if (publies) journal.info(`[Résumés] ${publies} résumé(s) publié(s)`);
  return { publies };
}

/** Les derniers résumés, au format des actualités de l'accueil. */
export async function resumesPourActualites(limite = 8): Promise<any[]> {
  const resumes = await prisma.resumeMatch.findMany({
    where:   { creeLe: { gte: new Date(Date.now() - 3 * 24 * 3600_000) } },
    orderBy: { creeLe: 'desc' },
    take:    limite,
    // Les logos et le score : le visuel d'un résumé, faute de photo.
    include: { match: { select: { homeTeamLogo: true, awayTeamLogo: true, homeScore: true, awayScore: true } } },
  });
  return resumes.map(r => ({
    id:         `resume_${r.id}`,
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
    // Pour une prochaine version de l'app : ouvrir la fiche du match.
    type:       'resume_match',
    match_id:   r.matchId,
    // Le visuel d'un résumé dans l'app (1.0.26) : les deux logos et le score.
    logo_domicile:  r.match?.homeTeamLogo ?? null,
    logo_exterieur: r.match?.awayTeamLogo ?? null,
    score: r.match && r.match.homeScore !== null && r.match.awayScore !== null
      ? `${r.match.homeScore}-${r.match.awayScore}` : null,
  }));
}

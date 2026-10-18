/**
 * Alertes de but pour les matchs suivis (18 octobre 2026).
 *
 * Un utilisateur qui a mis un match en favori, ou qui suit son pronostic dans
 * sa bankroll, recevait le coup d'envoi et la fin du match — rien entre les
 * deux. Il apprend désormais chaque but, comme sur Sofascore :
 * « But pour Arsenal ! — Arsenal 1-0 Chelsea · B. Saka 23' ».
 *
 * ── Le direct comparé à lui-même ───────────────────────────────────────────
 *
 * Un but se détecte en comparant le score du direct du fournisseur
 * (`live=all`) d'un cycle de synchronisation au suivant — pas à la base. La
 * liste des matchs écrit aussi le score en base, depuis un relevé vieux de
 * 25 s au plus : un score plus ancien réécrit par-dessus aurait fait annoncer
 * deux fois le même but, un score plus récent l'aurait tu.
 *
 * Au démarrage du serveur, le premier relevé sert de référence : aucun but
 * n'est annoncé pour un match déjà commencé, plutôt qu'une salve d'alertes à
 * chaque déploiement.
 */
import { country } from '../i18n/football';
import type { AFFixture } from './api_football.service';

export interface Score { dom: number; ext: number }

/** Un match absent du direct plus longtemps que ça est oublié. */
const OUBLI_MS = 15 * 60_000;

/** Dernier score lu dans le direct, par match (id du fournisseur). */
let scoresDuDirect = new Map<number, Score & { vuLe: number }>();

/** Pour les tests. */
export function _oublierScoresDuDirect(): void { scoresDuDirect = new Map(); }

/**
 * Relève les scores du direct et rend ceux qui ont changé depuis le relevé
 * précédent, avec le score d'avant.
 *
 * Un match qui sort brièvement du direct (mi-temps mal renseignée, panne d'un
 * cycle) garde son dernier score : à son retour, les buts manqués entre-temps
 * sont annoncés une fois.
 */
export function releverScores(direct: AFFixture[], maintenant = Date.now()): Map<number, { avant: Score; fixture: AFFixture }> {
  const changes = new Map<number, { avant: Score; fixture: AFFixture }>();
  for (const f of direct) {
    const dom = f.goals.home, ext = f.goals.away;
    if (typeof dom !== 'number' || typeof ext !== 'number') continue;
    const avant = scoresDuDirect.get(f.fixture.id);
    if (avant && (avant.dom !== dom || avant.ext !== ext)) {
      changes.set(f.fixture.id, { avant: { dom: avant.dom, ext: avant.ext }, fixture: f });
    }
    scoresDuDirect.set(f.fixture.id, { dom, ext, vuLe: maintenant });
  }
  for (const [id, s] of scoresDuDirect) {
    if (maintenant - s.vuLe > OUBLI_MS) scoresDuDirect.delete(id);
  }
  return changes;
}

/** « 23' », « 90+3' » ; vide si le fournisseur n'a pas donné la minute. */
function minute(elapsed: number | null | undefined, extra: number | null | undefined): string {
  if (typeof elapsed !== 'number') return '';
  return `${elapsed}${extra ? `+${extra}` : ''}'`;
}

/**
 * Le buteur du but qui vient d'être marqué, s'il est sûr.
 *
 * Les événements du direct peuvent avoir un temps de retard sur le score : le
 * dernier but listé serait alors le précédent, et l'alerte nommerait le
 * mauvais joueur. On ne le nomme que si le nombre de buts listés correspond
 * au score. Un but contre son camp n'est pas nommé : le fournisseur ne dit
 * pas de façon constante à quelle équipe il le rattache.
 */
function buteur(f: AFFixture, equipeId: number, total: number): { nom: string; minute: string } | null {
  const buts = (f.events ?? []).filter(e => e?.type === 'Goal' && e.detail !== 'Missed Penalty');
  if (buts.length !== total) return null;
  const dernier = buts[buts.length - 1];
  if (!dernier || dernier.detail === 'Own Goal' || dernier.team?.id !== equipeId) return null;
  const nom = dernier.player?.name?.trim();
  if (!nom) return null;
  return {
    nom: dernier.detail === 'Penalty' ? `${nom} (pen.)` : nom,
    minute: minute(dernier.time?.elapsed, dernier.time?.extra),
  };
}

const TEXTES = {
  fr: {
    but: (equipe: string) => `But pour ${equipe} !`,
    annule: (equipe: string) => `But annulé pour ${equipe}`,
    corrige: 'Score mis à jour',
  },
  en: {
    but: (equipe: string) => `Goal for ${equipe}!`,
    annule: (equipe: string) => `Goal disallowed for ${equipe}`,
    corrige: 'Score update',
  },
};

/**
 * Le texte de l'alerte, ou null si le score n'a pas changé.
 *
 * Un camp qui marque : « But pour X ! ». Un camp dont le score baisse — but
 * refusé par la VAR, ou corrigé par le fournisseur : « But annulé pour X ».
 * Les deux camps à la fois, entre deux relevés : « Score mis à jour ».
 */
export function messageDeBut(
  f: AFFixture,
  avant: Score,
  equipes: { dom: string; ext: string },
  langue: 'fr' | 'en',
): { title: string; body: string } | null {
  const apres = { dom: f.goals.home ?? 0, ext: f.goals.away ?? 0 };
  const dDom = apres.dom - avant.dom, dExt = apres.ext - avant.ext;
  if (dDom === 0 && dExt === 0) return null;

  const dom = country(equipes.dom, langue), ext = country(equipes.ext, langue);
  const score = `${dom} ${apres.dom}-${apres.ext} ${ext}`;
  const t = TEXTES[langue];
  const minuteDuJeu = minute(f.fixture.status.elapsed, f.fixture.status.extra);
  const corps = (detail: string) => detail ? `${score} · ${detail}` : score;

  // Un seul camp a bougé.
  if (dDom === 0 || dExt === 0) {
    const auDomicile = dExt === 0;
    const equipe = auDomicile ? dom : ext;
    if ((auDomicile ? dDom : dExt) > 0) {
      const qui = buteur(f, auDomicile ? f.teams.home.id : f.teams.away.id, apres.dom + apres.ext);
      return { title: t.but(equipe), body: corps(qui ? `${qui.nom} ${qui.minute}`.trim() : minuteDuJeu) };
    }
    return { title: t.annule(equipe), body: corps(minuteDuJeu) };
  }
  return { title: t.corrige, body: corps(minuteDuJeu) };
}

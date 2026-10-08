// Marchés 1xBet hors de l'API de cotes — phase 1 : ceux qui se règlent avec
// le seul score (mi-temps et final).
//
// L'API ne renvoie qu'une trentaine des marchés que 1xBet affiche pour un
// match. Les autres se saisissaient en texte libre : libellés bancals
// (« Équipes un gagne Au moins une mi-temps »), jamais traduits, et un
// résultat à forcer à la main. Ici, chaque marché a un nom stable (stocké en
// `market_name`, traduit par le catalogue partagé), une valeur construite
// toujours de la même façon (`market_value`, des éléments séparés par « / »
// que le moteur de libellés sait lire), et une règle de règlement.
//
// Convention 1xBet reprise telle quelle : dans un combiné, « Oui / Non » porte
// sur la combinaison entière. « V1 et les deux équipes marquent – Non » se
// gagne dès que l'un des deux manque (cote 1,146 face à 4,45 pour « Oui »).
//
// Ce fichier est la source ; le panneau en reçoit une copie générée
// (admin-web/public/marches-complementaires.js, voir
// backend/scripts/generate-football-translations.cjs).
'use strict';

const LIGNES = [0.5, 1.5, 2.5, 3.5, 4.5, 5.5, 6.5];

// Les éléments qu'un marché demande, dans l'ordre de sa valeur.
//   equipe  : Home | Away            issue / issueMt : Home | Draw | Away
//   double  : 1X | 12 | X2           ouiNon : Yes | No
//   total   : Over n | Under n       auMoins : Over n          (n en x,5)
const MARCHES = [
  { nom: 'To Win Either Half',           options: ['equipe', 'ouiNon'],                    miTemps: true },
  { nom: 'Draw In Either Half',          options: ['ouiNon'],                              miTemps: true },
  { nom: 'Goal In Both Halves',          options: ['ouiNon'],                              miTemps: true },
  { nom: 'To Score In Both Halves',      options: ['equipe', 'ouiNon'],                    miTemps: true },
  { nom: 'Result/Both Teams Score',      options: ['issue', 'ouiNon'] },
  { nom: 'Double Chance/Both Teams Score', options: ['double', 'ouiNon'] },
  { nom: 'Both Teams Score/Total',       options: ['total', 'ouiNon'] },
  { nom: 'European Handicap',            options: ['issue', 'handicap'] },
  { nom: 'HT/FT/Total',                  options: ['issueMt', 'issue', 'total', 'ouiNon'], miTemps: true },
  { nom: 'To Win To Nil',                options: ['equipe', 'ouiNon'] },
  { nom: 'Either Team To Win To Nil',    options: ['ouiNon'] },
  { nom: 'Double Chance/Team Total',     options: ['double', 'equipe', 'total', 'ouiNon'] },
  { nom: 'At Least One Team To Score',   options: ['auMoins', 'ouiNon'] },
  { nom: 'At Least One Team Not To Score/Total', options: ['total', 'ouiNon'] },
];

const JETONS = {
  equipe:  ['Home', 'Away'],
  issue:   ['Home', 'Draw', 'Away'],
  issueMt: ['Home', 'Draw', 'Away'],
  double:  ['1X', '12', 'X2'],
  ouiNon:  ['Yes', 'No'],
};

// ── Construire la valeur ────────────────────────────────────────────────────

function signe(n) { return (n > 0 ? '+' : '') + n; }

/**
 * La valeur stockée pour un choix du panneau, ou `null` s'il est incomplet.
 * `choix` porte une entrée par option : { equipe: 'Home', ouiNon: 'Yes',
 * total: 'Over 2.5', handicap: -1, … }.
 *
 * Handicap européen : le handicap est celui de l'équipe choisie (« Home / -1 »,
 * « Away / +1 ») ; pour le nul, celui de l'équipe à domicile (« Draw / -1 »),
 * comme l'écrit 1xBet (« X (-1) »). Écrit « équipe / handicap » plutôt que
 * « équipe handicap » : le moteur de libellés sait alors traduire
 * « Nul / -1 » dans les deux langues.
 */
function encoder(nom, choix) {
  const m = MARCHES.find(x => x.nom === nom);
  if (!m || !choix) return null;
  if (nom === 'European Handicap') {
    const h = Number(choix.handicap);
    if (!JETONS.issue.includes(choix.issue) || !Number.isInteger(h) || h === 0) return null;
    return choix.issue + ' / ' + signe(h);
  }
  const jetons = [];
  for (const o of m.options) {
    const v = choix[o];
    if (JETONS[o] ? !JETONS[o].includes(v) : !lireLigne(v, o === 'auMoins')) return null;
    jetons.push(v);
  }
  return jetons.join(' / ');
}

// ── Lire la valeur ──────────────────────────────────────────────────────────

/** « Over 2.5 » → { plus: true, ligne: 2.5 } ; seulement des lignes en x,5. */
function lireLigne(jeton, plusSeulement) {
  const m = /^(Over|Under) (\d+(?:\.5))$/.exec(String(jeton ?? '').trim());
  if (!m || (plusSeulement && m[1] !== 'Over')) return null;
  const ligne = Number(m[2]);
  return LIGNES.includes(ligne) ? { plus: m[1] === 'Over', ligne } : null;
}

function lire(m, valeur) {
  const jetons = String(valeur ?? '').split('/').map(s => s.trim());
  if (jetons.length !== m.options.length) return null;
  const t = {};
  for (let i = 0; i < jetons.length; i++) {
    const o = m.options[i];
    if (JETONS[o]) {
      if (!JETONS[o].includes(jetons[i])) return null;
      t[o] = jetons[i];
    } else {
      const l = lireLigne(jetons[i], o === 'auMoins');
      if (!l) return null;
      t[o] = l;
    }
  }
  return t;
}

function lireHandicap(valeur) {
  const m = /^(Home|Draw|Away)\s*\/\s*([+-]\d+)$/.exec(String(valeur ?? '').trim());
  if (!m || Number(m[2]) === 0) return null;
  // Pour le nul, le handicap est celui de l'équipe à domicile.
  return { issue: m[1], equipe: m[1] === 'Draw' ? 'Home' : m[1], h: Number(m[2]) };
}

// ── Régler ──────────────────────────────────────────────────────────────────

function gagnant(s) { return s.home > s.away ? 'Home' : s.home < s.away ? 'Away' : 'Draw'; }
function buts(s, equipe) { return equipe === 'Home' ? s.home : s.away; }
function encaisses(s, equipe) { return equipe === 'Home' ? s.away : s.home; }
function total(s) { return s.home + s.away; }
function lesDeux(s) { return s.home > 0 && s.away > 0; }
function respecte(l, n) { return l.plus ? n > l.ligne : n < l.ligne; }
function dansDouble(d, issue) {
  return { '1X': ['Home', 'Draw'], '12': ['Home', 'Away'], 'X2': ['Draw', 'Away'] }[d].includes(issue);
}

// L'évènement décrit par le marché a-t-il eu lieu ? (« Oui » le parie, « Non »
// parie le contraire.)
const CONDITIONS = {
  'To Win Either Half':      (t, ft, fh, sh) => gagnant(fh) === t.equipe || gagnant(sh) === t.equipe,
  'Draw In Either Half':     (t, ft, fh, sh) => gagnant(fh) === 'Draw' || gagnant(sh) === 'Draw',
  'Goal In Both Halves':     (t, ft, fh, sh) => total(fh) > 0 && total(sh) > 0,
  'To Score In Both Halves': (t, ft, fh, sh) => buts(fh, t.equipe) > 0 && buts(sh, t.equipe) > 0,
  'Result/Both Teams Score': (t, ft) => gagnant(ft) === t.issue && lesDeux(ft),
  'Double Chance/Both Teams Score': (t, ft) => dansDouble(t.double, gagnant(ft)) && lesDeux(ft),
  'Both Teams Score/Total':  (t, ft) => lesDeux(ft) && respecte(t.total, total(ft)),
  'HT/FT/Total':             (t, ft, fh) => gagnant(fh) === t.issueMt && gagnant(ft) === t.issue && respecte(t.total, total(ft)),
  'To Win To Nil':           (t, ft) => gagnant(ft) === t.equipe && encaisses(ft, t.equipe) === 0,
  'Either Team To Win To Nil': (t, ft) => gagnant(ft) !== 'Draw' && Math.min(ft.home, ft.away) === 0,
  'Double Chance/Team Total': (t, ft) => dansDouble(t.double, gagnant(ft)) && respecte(t.total, buts(ft, t.equipe)),
  'At Least One Team To Score': (t, ft) => Math.max(ft.home, ft.away) > t.auMoins.ligne,
  'At Least One Team Not To Score/Total': (t, ft) => !lesDeux(ft) && respecte(t.total, total(ft)),
};

/**
 * WIN / LOSS d'un pronostic sur l'un de ces marchés, ou `null` : marché qui
 * n'est pas d'ici, valeur illisible, ou mi-temps inconnue alors qu'il en a
 * besoin — le pronostic reste alors à régler à la main, plutôt que d'être
 * réglé sur une supposition.
 */
function regler(nom, valeur, ft, fh) {
  const m = MARCHES.find(x => x.nom === nom);
  if (!m || !ft) return null;
  if (m.miTemps && !fh) return null;
  const sh = fh ? { home: ft.home - fh.home, away: ft.away - fh.away } : null;

  if (nom === 'European Handicap') {
    const h = lireHandicap(valeur);
    if (!h) return null;
    const corrige = h.equipe === 'Home'
      ? { home: ft.home + h.h, away: ft.away }
      : { home: ft.home, away: ft.away + h.h };
    return gagnant(corrige) === h.issue ? 'WIN' : 'LOSS';
  }

  const t = lire(m, valeur);
  if (!t) return null;
  const arrive = CONDITIONS[nom](t, ft, fh, sh);
  return arrive === (t.ouiNon === 'Yes') ? 'WIN' : 'LOSS';
}

module.exports = { MARCHES, JETONS, LIGNES, encoder, regler };

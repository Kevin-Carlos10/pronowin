/**
 * Les cotes d'un match en cours, pour le formulaire du panneau (27 novembre
 * 2026).
 *
 * Le formulaire lisait toujours `/odds`, le flux d'avant-match. Ce flux
 * s'arrête au coup d'envoi : pour publier un pronostic en direct, le panneau
 * proposait des cotes périmées depuis le début du match. Pour un match en
 * cours, il lit désormais `/odds/live`, le flux que l'app lit déjà, renouvelé
 * toutes les 2 minutes, et le remet au format du formulaire.
 *
 * Les marchés reprennent leurs noms d'avant-match (« Match Winner »,
 * « Goals Over/Under »…) et leurs valeurs (« Over 2.5 »). Le règlement
 * automatique (`settlement.ts`), la couverture et les traductions les
 * reconnaissent sous ces noms.
 *
 * On ne garde que les marchés du match entier dont l'issue se lit sans
 * ambiguïté : résultat, double chance, nombre de buts, les deux équipes
 * marquent, remboursé si match nul. Les autres marchés du direct (handicap,
 * prochain but…) ont des règles propres au direct ; il vaut mieux les saisir à
 * la main que publier un sens incertain. Les quarts de ligne de buts (2,25)
 * restent aussi de côté : la mise y est coupée en deux, ce que le règlement
 * automatique ne fait pas.
 */
import type { LiveOdds } from './api_football_insights.service';
import {
  KNOWN_TYPE_MAP, type KnownPredictionType, type MatchOddsResult, type OddsMarket,
} from './api_football.service';

/** Les noms du flux en direct (en minuscules), vers le nom d'avant-match. */
const MARCHES: Record<string, 'Match Winner' | 'Double Chance' | 'Goals Over/Under' | 'Both Teams Score' | 'Home/Away'> = {
  'match winner': 'Match Winner',
  'fulltime result': 'Match Winner',
  'full time result': 'Match Winner',
  '1x2': 'Match Winner',
  'match result': 'Match Winner',
  'double chance': 'Double Chance',
  'goals over/under': 'Goals Over/Under',
  'over/under line': 'Goals Over/Under',
  'over/under': 'Goals Over/Under',
  'match goals': 'Goals Over/Under',
  'total goals': 'Goals Over/Under',
  'both teams score': 'Both Teams Score',
  'both teams to score': 'Both Teams Score',
  // Remboursé si match nul : « Home/Away » est son nom avant le match.
  'draw no bet': 'Home/Away',
  'home/away': 'Home/Away',
};

function issue(v: string): string | null {
  const x = v.trim().toLowerCase();
  if (x === 'home' || x === '1') return 'Home';
  if (x === 'draw' || x === 'x') return 'Draw';
  if (x === 'away' || x === '2') return 'Away';
  return null;
}

function paire(v: string): string | null {
  const x = v.trim().toLowerCase().replace(/\s+/g, '');
  if (['home/draw', '1x', '1/x'].includes(x)) return 'Home/Draw';
  if (['home/away', '12', '1/2'].includes(x)) return 'Home/Away';
  if (['draw/away', 'x2', 'x/2'].includes(x)) return 'Draw/Away';
  return null;
}

/** La valeur au format d'avant-match, ou nulle si elle ne se lit pas. */
function valeur(nom: string, v: { value: string; ligne?: string }): string | null {
  switch (nom) {
    case 'Match Winner': return issue(v.value);
    case 'Home/Away': {
      const i = issue(v.value);
      return i === 'Home' || i === 'Away' ? i : null;
    }
    case 'Double Chance': return paire(v.value);
    case 'Both Teams Score': {
      const x = v.value.trim().toLowerCase();
      return x === 'yes' ? 'Yes' : x === 'no' ? 'No' : null;
    }
    case 'Goals Over/Under': {
      const sens = v.value.trim().toLowerCase();
      const ligne = Number(v.ligne);
      if ((sens !== 'over' && sens !== 'under') || !v.ligne || !Number.isFinite(ligne) || ligne < 0) return null;
      // Demi ou entière seulement : pas de quart de ligne.
      if (Math.abs(ligne * 2 - Math.round(ligne * 2)) > 1e-9) return null;
      return `${sens === 'over' ? 'Over' : 'Under'} ${v.ligne}`;
    }
    default: return null;
  }
}

/** Les cotes en direct au format de `getOdds1xBet`, pour le même formulaire. */
export function cotesDuDirectPourPanneau(live: LiveOdds, homeTeam: string, awayTeam: string): MatchOddsResult {
  const parNom = new Map<string, Map<string, number>>();
  for (const m of live.markets) {
    const nom = MARCHES[(m.key ?? '').trim().toLowerCase()];
    if (!nom) continue;
    const valeurs = parNom.get(nom) ?? new Map<string, number>();
    for (const v of m.values) {
      const val = valeur(nom, v);
      // Le premier marché du flux l'emporte quand deux écritures se recouvrent
      // (« Match Goals » et « Over/Under Line »).
      if (val && Number.isFinite(v.odd) && v.odd > 1 && !valeurs.has(val)) valeurs.set(val, v.odd);
    }
    if (valeurs.size) parNom.set(nom, valeurs);
  }

  const markets: OddsMarket[] = [...parNom].map(([name, valeurs]) => ({
    name,
    values: [...valeurs].map(([value, odd]) => {
      const type = KNOWN_TYPE_MAP[name]?.[value];
      return { value, odd, ...(type ? { type } : {}) };
    }),
  }));

  const cote = (nom: string, val: string) => parNom.get(nom)?.get(val) ?? null;
  const options: MatchOddsResult['options'] = [];
  const pousser = (type: KnownPredictionType, label: string, odd: number | null) => {
    if (odd != null) options.push({ type, label, odd });
  };
  pousser('win1',    `${homeTeam} gagne`,        cote('Match Winner', 'Home'));
  pousser('draw',    'Match nul',                 cote('Match Winner', 'Draw'));
  pousser('win2',    `${awayTeam} gagne`,         cote('Match Winner', 'Away'));
  pousser('btts',    'Les deux équipes marquent', cote('Both Teams Score', 'Yes'));
  pousser('over25',  '+2.5 buts',                 cote('Goals Over/Under', 'Over 2.5'));
  pousser('under25', '-2.5 buts',                 cote('Goals Over/Under', 'Under 2.5'));
  pousser('over35',  '+3.5 buts',                 cote('Goals Over/Under', 'Over 3.5'));
  pousser('under35', '-3.5 buts',                 cote('Goals Over/Under', 'Under 3.5'));

  const minute = live.elapsed != null ? ` · ${live.elapsed}e minute` : '';
  const ancien = live.stale ? ' · flux momentanément figé' : '';
  return { source: `Cotes en direct${minute}${ancien}`, options, markets };
}

/**
 * Un match est-il en cours pour le formulaire ? Même règle que le panneau
 * (`pronostic_form.ejs`) : le statut LIVE en base peut avoir un peu de
 * retard sur le coup d'envoi.
 */
export function enCoursPourPanneau(statut: string, coupEnvoi: Date, maintenant = new Date()): boolean {
  if (statut === 'LIVE') return true;
  const ecart = maintenant.getTime() - coupEnvoi.getTime();
  return statut === 'SCHEDULED' && ecart >= 0 && ecart < 120 * 60_000;
}

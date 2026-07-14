import axios from 'axios';

const BASE = 'https://api.the-odds-api.com/v4';

// Mapping ligues → clé sport Odds API
const LEAGUE_MAP: [string, string][] = [
  ['world cup',            'soccer_fifa_world_cup'],
  ['coupe du monde',       'soccer_fifa_world_cup'],
  ['champions league',     'soccer_uefa_champs_league'],
  ['ligue des champions',  'soccer_uefa_champs_league'],
  ['europa league',        'soccer_uefa_europa_league'],
  ['conference league',    'soccer_uefa_europa_conference_league'],
  ['premier league',       'soccer_england_premier_league'],
  ['ligue 1',              'soccer_france_ligue_one'],
  ['ligue1',               'soccer_france_ligue_one'],
  ['la liga',              'soccer_spain_la_liga'],
  ['bundesliga',           'soccer_germany_bundesliga'],
  ['serie a',              'soccer_italy_serie_a'],
  ['eredivisie',           'soccer_netherlands_eredivisie'],
  ['primeira liga',        'soccer_portugal_primeira_liga'],
  ['super lig',            'soccer_turkey_super_league'],
  ['afcon',                'soccer_africa_cup_of_nations'],
  ['can ',                 'soccer_africa_cup_of_nations'],
  ['coupe d\'afrique',     'soccer_africa_cup_of_nations'],
];

// Normalise un nom d'équipe pour la comparaison (minuscules, sans accents)
function normalize(s: string) {
  return s.toLowerCase()
    .normalize('NFD').replace(/[̀-ͯ]/g, '')
    .replace(/[^a-z0-9 ]/g, '')
    .trim();
}

function teamMatch(a: string, b: string) {
  const na = normalize(a);
  const nb = normalize(b);
  return na === nb || na.includes(nb) || nb.includes(na);
}

export interface MatchOdds {
  home: number;
  draw: number;
  away: number;
  bookmakerCount: number;
  source: string; // nom du bookmaker ou "moyenne"
}

export class OddsService {

  async getOddsForMatch(
    homeTeam: string,
    awayTeam: string,
    league: string,
  ): Promise<MatchOdds> {
    const apiKey = process.env.ODDS_API_KEY;
    if (!apiKey) throw new Error('ODDS_API_KEY manquante dans .env');

    const sportKey = this._resolveSportKey(league);

    // Récupérer tous les événements de ce sport avec cotes EU
    const { data: events } = await axios.get(`${BASE}/sports/${sportKey}/odds/`, {
      params: {
        apiKey,
        regions:    'eu',
        markets:    'h2h',
        oddsFormat: 'decimal',
      },
    });

    // Trouver l'événement correspondant
    const event = (events as any[]).find(e =>
      teamMatch(e.home_team, homeTeam) && teamMatch(e.away_team, awayTeam),
    );

    if (!event) {
      throw new Error(
        `Match "${homeTeam} vs ${awayTeam}" introuvable dans The Odds API pour la ligue "${league}". ` +
        `Vérifiez que le match est programmé dans les prochains jours.`,
      );
    }

    // Collecter toutes les cotes de tous les bookmakers
    const homes: number[] = [];
    const draws: number[] = [];
    const aways: number[] = [];

    for (const bm of event.bookmakers as any[]) {
      const h2h = bm.markets?.find((m: any) => m.key === 'h2h');
      if (!h2h) continue;
      const homeOdd = h2h.outcomes.find((o: any) => teamMatch(o.name, homeTeam))?.price;
      const drawOdd = h2h.outcomes.find((o: any) => o.name === 'Draw')?.price;
      const awayOdd = h2h.outcomes.find((o: any) => teamMatch(o.name, awayTeam))?.price;
      if (homeOdd) homes.push(homeOdd);
      if (drawOdd) draws.push(drawOdd);
      if (awayOdd) aways.push(awayOdd);
    }

    if (!homes.length) throw new Error('Aucune cote disponible pour ce match.');

    const avg = (arr: number[]) =>
      Math.round((arr.reduce((a, b) => a + b, 0) / arr.length) * 100) / 100;

    return {
      home:           avg(homes),
      draw:           avg(draws),
      away:           avg(aways),
      bookmakerCount: homes.length,
      source:         `moyenne de ${homes.length} bookmaker(s)`,
    };
  }

  private _resolveSportKey(league: string): string {
    const l = league.toLowerCase();
    for (const [keyword, key] of LEAGUE_MAP) {
      if (l.includes(keyword)) return key;
    }
    // Fallback générique football mondial
    return 'soccer_fifa_world_cup';
  }
}

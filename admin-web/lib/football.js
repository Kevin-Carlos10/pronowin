/**
 * Les familles d'appels à API-Football, telles que l'API les compte
 * (`familleDe`, backend `services/consommation_football.service.ts`), et ce
 * qu'elles servent dans PronoWin.
 *
 * Le chemin seul (« /fixtures/lineups ») ne dit pas à l'administrateur quel
 * écran ou quelle tâche couper quand le quota s'épuise ; le libellé, si.
 */
const FAMILLES_FOOTBALL = {
  '/fixtures?live':       'Scores en direct',
  '/fixtures?id':         'Détail de matchs',
  '/fixtures?date':       'Matchs du jour',
  '/fixtures':            'Matchs — autres recherches (forme, calendrier)',
  '/fixtures/events':     'Événements de match (buts, cartons)',
  '/fixtures/lineups':    'Compositions',
  '/fixtures/statistics': 'Statistiques de match',
  '/fixtures/players':    'Notes des joueurs',
  '/fixtures/headtohead': 'Confrontations directes',
  '/odds':                'Cotes',
  '/odds/live':           'Cotes en direct',
  '/predictions':         'Prédictions du fournisseur',
  '/standings':           'Classements',
  '/injuries':            'Blessés et suspendus',
  '/players/topscorers':  'Meilleurs buteurs',
  '/players/topassists':  'Meilleurs passeurs',
  '/players/topyellowcards': 'Cartons jaunes',
  '/players/topredcards': 'Cartons rouges',
  '/players':             'Fiches joueurs',
  '/sidelined':           'Absences (fiches joueurs)',
  '/transfers':           'Transferts (fiches joueurs)',
  '/players/squads':      'Effectifs (fiches équipes)',
  '/teams':               'Fiches équipes',
  '/teams/statistics':    "Statistiques d'équipe",
  '/coachs':              'Entraîneurs (fiches équipes)',
  '/leagues':             'Compétitions',
  '/status':              'État du compte',
};

const libelleFamille = (f) => FAMILLES_FOOTBALL[f] ?? String(f ?? '');

module.exports = { FAMILLES_FOOTBALL, libelleFamille };

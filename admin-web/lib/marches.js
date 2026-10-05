/**
 * Les marchés de paris, en français.
 *
 * Le nom brut anglais du fournisseur de cotes reste stocké en base
 * (`market_name`) ; seul l'affichage est traduit. La table vivait dans le
 * script du formulaire de pronostic ; l'écran de fiabilité en a besoin aussi,
 * et deux copies auraient fini par diverger. Le formulaire la reçoit
 * désormais du serveur (`res.locals.MARCHES_FR`).
 */
const MARCHES_FR = {
  'Match Winner':                      'Vainqueur du match',
  'First Half Winner':                 'Vainqueur 1ère mi-temps',
  'Second Half Winner':                'Vainqueur 2ème mi-temps',
  'Asian Handicap':                    'Handicap asiatique',
  'Asian Handicap First Half':         'Handicap asiatique — 1ère MT',
  'Asian Handicap (2nd Half)':         'Handicap asiatique — 2ème MT',
  'Goals Over/Under':                  'Total buts +/-',
  'Goals Over/Under First Half':       'Total buts +/- — 1ère MT',
  'Goals Over/Under - Second Half':    'Total buts +/- — 2ème MT',
  'HT/FT Double':                      'Double mi-temps / fin de match',
  'Both Teams Score':                  'Les deux équipes marquent',
  'Both Teams Score - First Half':     'Les deux équipes marquent — 1ère MT',
  'Both Teams To Score - Second Half': 'Les deux équipes marquent — 2ème MT',
  'Exact Score':                       'Score exact',
  'Highest Scoring Half':              'Mi-temps la plus prolifique',
  'Correct Score - First Half':        'Score exact — 1ère MT',
  'Correct Score - Second Half':       'Score exact — 2ème MT',
  'Double Chance':                     'Double chance',
  'Double Chance - First Half':        'Double chance — 1ère MT',
  'Double Chance - Second Half':       'Double chance — 2ème MT',
  'Total - Home':                      'Total buts domicile',
  'Total - Away':                      'Total buts extérieur',
  'Odd/Even':                          'Pair/Impair',
  'Odd/Even - First Half':             'Pair/Impair — 1ère MT',
  'Odd/Even - Second Half':            'Pair/Impair — 2ème MT',
  'Home Odd/Even':                     'Pair/Impair domicile',
  'Away Odd/Even':                     'Pair/Impair extérieur',
  'To Qualify':                        'Qualification',
  'Home Team Total Goals(1st Half)':   'Total buts domicile (1ère MT)',
  'Away Team Total Goals(1st Half)':   'Total buts extérieur (1ère MT)',
  'Home Team Total Goals(2nd Half)':   'Total buts domicile (2ème MT)',
  'Away Team Total Goals(2nd Half)':   'Total buts extérieur (2ème MT)',
};

/** Les huit types de pronostic connus, sans nom d'équipe. */
const TYPES_PRONOSTIC_FR = {
  win1:    'Victoire à domicile (1)',
  draw:    'Match nul (X)',
  win2:    "Victoire à l'extérieur (2)",
  btts:    'Les deux équipes marquent',
  over25:  'Plus de 2,5 buts',
  under25: 'Moins de 2,5 buts',
  over35:  'Plus de 3,5 buts',
  under35: 'Moins de 3,5 buts',
};

/**
 * Le libellé d'une clé de marché du serveur : un type connu (`win1`), ou
 * `other:<marché brut>` pour un pronostic saisi sur un autre marché.
 */
function libelleMarche(cle) {
  const c = String(cle ?? '');
  if (c.startsWith('other:')) {
    const brut = c.slice('other:'.length);
    return brut ? (MARCHES_FR[brut] ?? brut) : 'Autre marché';
  }
  return TYPES_PRONOSTIC_FR[c] ?? c;
}

module.exports = { MARCHES_FR, TYPES_PRONOSTIC_FR, libelleMarche };

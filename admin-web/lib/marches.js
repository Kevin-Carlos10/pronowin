/**
 * Les marchés de paris, en français.
 *
 * Le nom brut anglais du fournisseur de cotes reste stocké en base
 * (`market_name`) ; seul l'affichage est traduit. La table vivait dans le
 * script du formulaire de pronostic ; l'écran de fiabilité en a besoin aussi,
 * et deux copies auraient fini par diverger. Le formulaire la reçoit
 * désormais du serveur (`res.locals.MARCHES_FR`).
 */
const football = require('../../backend/src/i18n/football');
const MARCHES_FR = Object.fromEntries(football.catalog.markets.flatMap(m =>
  [m.en, ...m.aliases].map(name => [name, m.fr])));

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
    return brut ? football.market(brut, 'fr').text : 'Autre marché';
  }
  return TYPES_PRONOSTIC_FR[c] ?? c;
}

module.exports = { MARCHES_FR, TYPES_PRONOSTIC_FR, libelleMarche };

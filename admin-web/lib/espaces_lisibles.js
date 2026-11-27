/**
 * Des séparateurs de milliers qu'on voit (27 novembre 2026).
 *
 * `toLocaleString('fr-FR')` sépare les milliers par une espace fine insécable
 * (U+202F). Dans les grands chiffres des tuiles — Inter en gras, interlettrage
 * resserré — elle ne mesurait plus que 2,4 px : « 1 921 500 » se lisait
 * « 1921500 » sur la page Bankroll, à côté d'un « 2 000 000 » à peine plus
 * aéré.
 *
 * Plutôt que de reprendre chacune des quinze vues qui formatent un montant,
 * chaque page rendue remplace l'espace fine par l'espace insécable ordinaire
 * (U+00A0) : elle reste insécable, mais se voit.
 */
const ESPACE_FINE = / /g;

function espacesLisibles(texte) {
  return typeof texte === 'string' ? texte.replace(ESPACE_FINE, ' ') : texte;
}

/** Enveloppe `res.render`, avec ou sans rappel, comme Express le fait. */
function middleware(req, res, next) {
  const rendre = res.render.bind(res);
  res.render = (vue, options, rappel) => {
    if (typeof options === 'function') { rappel = options; options = {}; }
    rendre(vue, options || {}, (erreur, html) => {
      if (rappel) return rappel(erreur, espacesLisibles(html));
      if (erreur) return req.next(erreur);
      res.send(espacesLisibles(html));
    });
  };
  next();
}

module.exports = { espacesLisibles, middleware };

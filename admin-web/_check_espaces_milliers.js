/**
 * Les séparateurs de milliers restent visibles (27 novembre 2026).
 *
 * `toLocaleString('fr-FR')` sépare les milliers par une espace fine (U+202F)
 * qui, dans les grands chiffres des tuiles, ne mesurait plus que 2,4 px :
 * « 1 921 500 » se lisait « 1921500 ». Chaque page rendue la remplace par
 * l'espace insécable ordinaire (lib/espaces_lisibles.js).
 *
 *   node _check_espaces_milliers.js
 */
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const { espacesLisibles, middleware } = require('./lib/espaces_lisibles');

const millier = (1921500).toLocaleString('fr-FR');
assert.ok(millier.includes(' '), 'le formatage français ne produit plus l’espace fine : ce contrôle est à revoir');
assert.equal(espacesLisibles(millier), '1 921 500');
assert.equal(espacesLisibles(undefined), undefined);

// Le rendu passe par l'enveloppe, avec ou sans rappel.
function reponse(html, erreur = null) {
  const res = { envoye: null };
  res.render = (vue, options, rappel) => rappel(erreur, html);
  res.send = (h) => { res.envoye = h; };
  return res;
}
{
  const res = reponse('<p>' + millier + ' FCFA</p>');
  middleware({}, res, () => {});
  res.render('vue', { a: 1 });
  assert.equal(res.envoye, '<p>1 921 500 FCFA</p>');
}
{
  const res = reponse('<b>' + millier + '</b>');
  middleware({}, res, () => {});
  let recu;
  res.render('vue', (err, html) => { recu = html; });
  assert.equal(recu, '<b>1 921 500</b>');
}
{
  const echec = new Error('vue absente');
  const res = reponse(undefined, echec);
  let transmis;
  middleware({ next: (e) => { transmis = e; } }, res, () => {});
  res.render('vue', {});
  assert.equal(transmis, echec);
  assert.equal(res.envoye, null);
}

// Et le serveur la branche bien.
const serveur = fs.readFileSync(path.join(__dirname, 'server.js'), 'utf8');
assert.match(serveur, /app\.use\(require\('\.\/lib\/espaces_lisibles'\)\.middleware\)/);

console.log('OK : les séparateurs de milliers des pages rendues sont des espaces insécables visibles.');

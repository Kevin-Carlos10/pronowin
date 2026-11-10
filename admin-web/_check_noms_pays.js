'use strict';
/**
 * Le pays des utilisateurs s'affiche en toutes lettres (10 novembre 2026) :
 * « BF » → « Burkina Faso », dans la langue de l'administration ; un code
 * inconnu reste tel quel, une valeur vide devient « — ».
 */
const assert = require('assert');
const ejs = require('ejs');
const { nomPays } = require('./lib/noms_pays');
const { translator } = require('./lib/ui-language');

assert.strictEqual(nomPays('BF'), 'Burkina Faso');
assert.strictEqual(nomPays('sn'), 'Sénégal');
assert.strictEqual(nomPays('SN', 'en'), 'Senegal');
assert.strictEqual(nomPays('XX'), 'XX');
assert.strictEqual(nomPays(''), '—');
assert.strictEqual(nomPays(null), '—');

// La fiche d'un utilisateur : la ligne « Pays » porte le nom.
const ligne = ejs.render(
  "<% function row(l, v) { %><%= l %>=<%= v %>;<% } %><% row('Pays', typeof nomPays === 'function' ? nomPays(user.countryCode) : user.countryCode) %>",
  { user: { countryCode: 'CI' }, nomPays: c => nomPays(c, 'fr'), tAdmin: translator('fr') });
assert.ok(ligne.includes('Pays=C'), ligne);
assert.ok(!ligne.includes('Pays=CI;'), 'le code brut ne doit plus s’afficher : ' + ligne);

console.log('OK : le pays des utilisateurs s’affiche en toutes lettres (fiche et tableau de bord).');

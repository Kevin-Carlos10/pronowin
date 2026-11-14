/**
 * Les noms de joueurs du flux de cotes arrivent en minuscules
 * (« Erling braut haaland ») et le libellé public les reprenait tels quels
 * dans l'application. Le formulaire leur rend leurs majuscules à la saisie,
 * sans toucher aux particules ni aux valeurs qui ne sont pas des noms.
 *
 * La fonction est lue dans la vue et exécutée telle quelle : un contrôle qui
 * en porterait une copie ne vérifierait que lui-même.
 */
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const vue = fs.readFileSync(path.join(__dirname, 'views', 'pronostic_form.ejs'), 'utf8');
const debut = vue.indexOf('const PARTICULES');
const fin = vue.indexOf('/* ── fin des noms propres ── */', debut);
assert.ok(debut > 0 && fin > debut, 'fonction nomPropre introuvable dans le formulaire');

const bac = {};
vm.runInNewContext(vue.slice(debut, fin) + '\nthis.nomPropre = nomPropre;', bac);
const { nomPropre } = bac;

const cas = [
  ['Erling braut haaland', 'Erling Braut Haaland'],
  ['kylian mbappé', 'Kylian Mbappé'],
  ['virgil van dijk', 'Virgil van Dijk'],
  ['kevin De bruyne', 'Kevin De Bruyne'],
  ['scott mcTominay', 'Scott McTominay'],
  ["n'golo kanté", "N'golo Kanté"],
  ['jean-philippe mateta', 'Jean-Philippe Mateta'],
  // Ce qui n'est pas un nom ne bouge pas.
  ['Plus de 2.5', 'Plus de 2.5'],
  ['Bayern München/Nul', 'Bayern München/Nul'],
  ['Oui', 'Oui'],
  ['haaland', 'haaland'],
];
for (const [entree, attendu] of cas) {
  assert.strictEqual(nomPropre(entree), attendu, `nomPropre(${JSON.stringify(entree)})`);
}
assert.ok(vue.includes('return nomPropre(String(value)'),
  'translateMarketValue doit passer par nomPropre');
console.log('OK : noms de joueurs capitalisés, particules et valeurs non nominales préservées.');

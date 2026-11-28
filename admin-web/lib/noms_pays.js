'use strict';
/**
 * Le nom d'un pays à partir de son code (10 novembre 2026).
 *
 * L'administration affichait le pays des utilisateurs tel que l'app
 * l'enregistre : « BF », « CI », « SN ». Les noms viennent des données ICU de
 * Node, dans la langue de l'administration : « Burkina Faso », « Côte
 * d'Ivoire » — « Ivory Coast » en anglais.
 *
 * Un code inconnu, ou qui n'est pas un code de pays, s'affiche tel quel.
 */
const formats = {};

function nomPays(code, langue = 'fr') {
  if (typeof code !== 'string' || !code.trim()) return '—';
  const c = code.trim().toUpperCase();
  if (!/^[A-Z]{2}$/.test(c)) return code;
  try {
    formats[langue] = formats[langue] || new Intl.DisplayNames([langue], { type: 'region' });
    const nom = formats[langue].of(c);
    return nom && nom !== c ? nom : c;
  } catch {
    return c;
  }
}

module.exports = { nomPays };

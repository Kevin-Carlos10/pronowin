/**
 * Les canaux de vente, tels que l'API les nomme (`canalDe`, backend
 * `services/revenus_canaux.service.ts`), et leur libellé à l'écran.
 *
 * Une seule table pour la page Revenus, la page Fidélité et l'export
 * comptable : le comptable doit lire dans son fichier les mêmes mots que
 * l'administrateur à l'écran.
 */
const CANAUX_FR = {
  mobile_money: 'Mobile Money',
  apple:        'App Store',
  google:       'Google Play',
  partenaire:   'Code partenaire',
  offert:       "Offert par l'équipe",
  autre:        'Autre',
};

const libelleCanal = (c) => CANAUX_FR[c] ?? String(c ?? '');

module.exports = { CANAUX_FR, libelleCanal };

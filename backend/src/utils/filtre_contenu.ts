/**
 * Ce qu'un commentaire ne peut pas contenir.
 *
 * L'App Store (règle 1.2) et Google Play exigent, dès que des membres publient
 * des contenus visibles par d'autres, une méthode pour filtrer les contenus
 * répréhensibles. Trois familles sont refusées à la publication :
 *
 *  - les injures, propos haineux et sexuels, comparés après normalisation
 *    (minuscules, sans accents, chiffres déguisés en lettres, lettres
 *    répétées réduites) : « C0NNNARD » est reconnu ;
 *  - les liens ;
 *  - les numéros de téléphone : les arnaques aux « coupons sûrs » des
 *    communautés de paris passent par un numéro WhatsApp.
 *
 * Le filtre écarte l'évident ; le signalement et la modération traitent le
 * reste. Une liste exhaustive n'existe pas, et une liste trop large bloquerait
 * des messages honnêtes : les jurons d'exaspération (« putain de match ») ne
 * visent personne et restent admis, les insultes adressées et les mots
 * haineux non.
 */

export type RefusContenu = 'TERMES_INTERDITS' | 'LIEN_INTERDIT' | 'TELEPHONE_INTERDIT';

/** Mots refusés, écrits normalement ; comparés une fois normalisés. */
const MOTS = [
  // Injures adressées
  'connard', 'connards', 'connasse', 'salope', 'salopes', 'salaud', 'pute', 'putes',
  'encule', 'encules', 'enculer', 'enfoire', 'enfoires', 'batard', 'batards',
  'fdp', 'ntm', 'tg', 'ftg', 'abruti', 'debile', 'mongol', 'attarde',
  // Haine, discriminations
  'pd', 'pede', 'pedes', 'tapette', 'tafiole', 'gouine', 'negre', 'negro', 'bougnoule',
  'bicot', 'youpin', 'chinetoque', 'macaque',
  // Sexuel
  'chatte', 'sucer', 'suceuse', 'porno',
  // Anglais
  'fuck', 'fucking', 'fucker', 'motherfucker', 'cunt', 'bitch', 'bitches', 'whore', 'slut',
  'nigger', 'nigga', 'faggot', 'fag', 'asshole', 'dickhead', 'pussy', 'kys',
];

/** Expressions refusées, comparées mot à mot une fois normalisées. */
const EXPRESSIONS = [
  'fils de pute', 'nique ta mere', 'niquer ta mere', 'ta mere la pute', 'va te faire foutre',
  'va te faire enculer', 'ferme ta gueule', 'suicide toi', 'tue toi', 'kill yourself',
  'son of a bitch', 'go to hell',
];

/** « 0 », « 4 », « @ »… comme on les écrit pour contourner un filtre. */
const LEET: Record<string, string> = { '0': 'o', '1': 'i', '3': 'e', '4': 'a', '5': 's', '7': 't', '@': 'a', '$': 's' };

/** Minuscules, sans accents ni chiffres déguisés, chaque lettre répétée réduite à une. */
export function normaliser(texte: string): string {
  return texte
    .toLowerCase()
    .normalize('NFD').replace(/[̀-ͯ]/g, '')
    .replace(/[013457@$]/g, (c) => LEET[c] ?? c)
    .replace(/[^a-z]+/g, ' ')
    .replace(/([a-z])\1+/g, '$1')
    .trim();
}

const MOTS_NORMALISES = new Set(MOTS.map(normaliser));
const EXPRESSIONS_NORMALISEES = EXPRESSIONS.map(normaliser);

const LIEN = /(https?:\/\/|www\.|\bt\.me\/|\bwa\.me\/|\bbit\.ly\b|\b[a-z0-9-]+\.(com|net|org|io|me|bet|xyz|info|fr|ci|bf|sn|tg|ml|cm|ly|gl|co|app|site|online|shop)\b)/i;
/** Huit chiffres au moins, séparés au plus par des espaces ou des tirets.
 *  Les cotes (« 1.85 2.10 ») sont coupées par leurs points : elles passent. */
const TELEPHONE = /(?:\+\s?)?(?:\d[ \-]?){7,}\d/;

/** Le motif du refus, ou `null` si le commentaire peut être publié. */
export function refusContenu(texte: string): RefusContenu | null {
  if (LIEN.test(texte)) return 'LIEN_INTERDIT';
  if (TELEPHONE.test(texte)) return 'TELEPHONE_INTERDIT';
  const mots = normaliser(texte).split(' ');
  for (const mot of mots) {
    if (MOTS_NORMALISES.has(mot)) return 'TERMES_INTERDITS';
  }
  const phrase = ` ${mots.join(' ')} `;
  if (EXPRESSIONS_NORMALISEES.some((e) => phrase.includes(` ${e} `))) return 'TERMES_INTERDITS';
  return null;
}

export const MESSAGES_REFUS: Record<RefusContenu, string> = {
  TERMES_INTERDITS:   'Ce commentaire contient des termes interdits par les règles de la communauté.',
  LIEN_INTERDIT:      'Les liens ne sont pas autorisés dans les commentaires.',
  TELEPHONE_INTERDIT: 'Les numéros de téléphone ne sont pas autorisés dans les commentaires.',
};

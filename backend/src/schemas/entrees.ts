import { z } from 'zod';

import { booleen, identifiant, nombre, nombreFacultatif, texteFacultatif } from '../middleware/valider';

/**
 * Schémas d'entrée des routes sensibles (constat S3). Les autres routes
 * suivront : chaque nouveau schéma remplace des contrôles écrits à la main
 * dans un contrôleur.
 */

const Maj = (libelle: string) => libelle.charAt(0).toUpperCase() + libelle.slice(1);
const cote = (libelle: string) => nombre(libelle).refine((n) => n >= 1, `${Maj(libelle)} vaut au moins 1.`);
const coteFacultative = (libelle: string) =>
  nombreFacultatif(libelle).refine((n) => n === undefined || n >= 1, `${Maj(libelle)} vaut au moins 1.`);

/** POST /pronostics/admin/pronostic — le formulaire du panneau. */
export const pronosticAdmin = z.object({
  match_id:         identifiant('le match'),
  prediction_type:  identifiant('le type de pronostic'),
  prediction_label: z.string({ required_error: 'Indiquez le libellé du pronostic.' })
    .trim().min(1, 'Indiquez le libellé du pronostic.').max(200),
  market_name:      texteFacultatif(120),
  market_value:     texteFacultatif(120),
  // Cotes du match : absentes, elles valent 0 (« non renseignée ») comme en
  // base ; présentes, ce sont des cotes.
  odds_home:        coteFacultative('la cote domicile').transform((n) => n ?? 0),
  odds_draw:        coteFacultative('la cote du nul').transform((n) => n ?? 0),
  odds_away:        coteFacultative('la cote extérieur').transform((n) => n ?? 0),
  // Le minimum de publication (1,2) reste vérifié par le service, seul à
  // savoir si le pronostic est publié ; ici, une cote vide ou illisible ne
  // devient plus NaN.
  odds_recommended: cote('la cote conseillée'),
  confidence_score: nombre('la confiance').refine(
    (n) => Number.isInteger(n) && n >= 1 && n <= 5, 'La confiance doit être une note entière de 1 à 5.'),
  analyst_note:     texteFacultatif(4000),
  is_premium:       booleen,
  publish:          booleen,
});

/** POST /bankroll/budget */
export const budgetBankroll = z.object({
  total_budget: nombre('le budget').refine((n) => n > 0 && n <= 1e12, 'Budget invalide.'),
  currency:     z.string().trim().toUpperCase().max(8).optional(),
});

/** POST /bankroll/bet */
export const pariBankroll = z.object({
  pronostic_id:  identifiant('le pronostic'),
  staked_amount: nombre('la mise').refine((n) => n > 0, 'La mise doit être positive.'),
});

/** POST /bankroll/bet/:id/confirmer — sans montant : « oui, c'est bien elle ». */
export const confirmationMise = z.object({
  mise_reelle: nombreFacultatif('la mise réelle').refine(
    (n) => n === undefined || (n >= 0 && n <= 1e12), 'Mise invalide.'),
});

/** POST /notifications/register-token */
export const jetonNotification = z.object({
  fcm_token: z.string({ required_error: 'fcm_token requis.', invalid_type_error: 'fcm_token requis.' })
    .trim().min(1, 'fcm_token requis.').max(4096, 'fcm_token requis.'),
  platform:  z.enum(['android', 'ios']).catch('android'),
});

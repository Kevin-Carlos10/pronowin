import dotenv from 'dotenv';

/**
 * Les bancs qui écrivent dans une vraie base ne s'exécutent que sur une base
 * locale.
 *
 * Ils créent des comptes, des preuves, des achats, et `seuils_mise_a_jour`
 * écrit la configuration servie à toutes les applications installées. Lancés
 * avec un `DATABASE_URL` qui pointe ailleurs — un poste configuré contre la
 * production, un serveur où l'on lance `npm test` —, une interruption en plein
 * banc laisserait ces écritures derrière elle (constat Q4 de l'audit du
 * 24 septembre 2026).
 *
 * Hors base locale, ces bancs sont sautés, et le disent.
 */
dotenv.config();

const url = process.env.DATABASE_URL ?? '';
export const BASE_LOCALE = /@(localhost|127\.0\.0\.1|\[::1\])(:\d+)?\//.test(url);

if (!BASE_LOCALE) {
  // eslint-disable-next-line no-console
  console.warn('[bancs] DATABASE_URL ne désigne pas une base locale : bancs sur base réelle sautés.');
}

/** `describe`, ou `describe.skip` hors base locale. */
export const decrireSurBaseLocale: jest.Describe = BASE_LOCALE ? describe : describe.skip;

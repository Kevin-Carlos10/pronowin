import { prisma } from '../lib/prisma';

/**
 * Configuration publique de l'app, modifiable depuis le panneau admin.
 *
 * Deux sources, dans cet ordre :
 *   1. la table `app_settings`, écrite depuis l'administration ;
 *   2. les variables d'environnement, valeur de repli.
 *
 * Ce repli n'est pas décoratif : tant que personne n'a rien enregistré, le
 * comportement reste exactement celui d'avant l'introduction de la table. Et
 * si la base est momentanément injoignable, l'endpoint public continue de
 * répondre avec les valeurs du `.env` plutôt que de tomber — un écran de mise
 * à jour cassé vaut mieux qu'une app qui ne démarre pas.
 */

/** Clés reconnues. Toute autre clé envoyée par l'admin est ignorée. */
export const CLES_CONFIG = [
  'APP_MIN_VERSION',
  'APP_LATEST_VERSION',
  'APP_FORCE_UPDATE',
  'APK_MIN_VERSION',
  'APK_LATEST_VERSION',
  'APK_FORCE_UPDATE',
  'APK_URL',
  'APP_UPDATE_MESSAGE',

  // ── Code d'affiliation partenaire ─────────────────────────────────────────
  //
  // `PROMO_CODE` est le code general. Les trois suivants ne servent que si un
  // partenaire exige le sien : laisses vides, ils heritent du general.
  //
  // Pourquoi cette forme plutot qu'un seul code : l'ecran laisse choisir entre
  // 1xBet, Melbet et Betwinner, mais n'affichait qu'un code. Si les trois
  // enseignes n'attribuent pas le meme, deux utilisateurs sur trois ouvraient
  // un compte avec un code qui ne credite personne — et reclamaient malgre tout
  // leur mois offert. La forme generale + surcharges couvre les deux cas sans
  // obliger a trancher aujourd'hui.
  'PROMO_CODE',
  'PROMO_CODE_1XBET',
  'PROMO_CODE_MELBET',
  'PROMO_CODE_BETWINNER',
] as const;

export type CleConfig = (typeof CLES_CONFIG)[number];

const EST_BOOLEEN: ReadonlySet<string> = new Set([
  'APP_FORCE_UPDATE', 'APK_FORCE_UPDATE',
]);

/** Valeurs enregistrées en base, indexées par clé. */
async function _enBase(): Promise<Record<string, string>> {
  try {
    const lignes = await prisma.appSetting.findMany({
      where: { key: { in: [...CLES_CONFIG] } },
    });
    return Object.fromEntries(lignes.map(l => [l.key, l.value]));
  } catch {
    return {};
  }
}

/**
 * Configuration effective : base d'abord, `.env` ensuite, défaut en dernier.
 *
 * Retourne aussi, pour chaque clé, si la valeur vient de la base — le panneau
 * admin l'affiche, pour qu'on distingue « réglé ici » de « hérité du serveur ».
 */
export async function lireConfig(): Promise<{
  valeurs: Record<CleConfig, string>;
  origine: Record<CleConfig, 'base' | 'env'>;
}> {
  const base = await _enBase();

  const DEFAUTS: Record<CleConfig, string> = {
    APP_MIN_VERSION:    '1.0.0',
    APP_LATEST_VERSION: '1.0.0',
    APP_FORCE_UPDATE:   'false',
    APK_MIN_VERSION:    process.env.APP_MIN_VERSION    ?? '1.0.0',
    APK_LATEST_VERSION: process.env.APP_LATEST_VERSION ?? '1.0.0',
    APK_FORCE_UPDATE:   'false',
    APK_URL:            '',
    APP_UPDATE_MESSAGE: 'Une nouvelle version de PronoWin est disponible avec des améliorations et corrections.',

    // Aucun code par defaut. Un code d'affiliation invente ne credite personne :
    // vide, l'ecran mobile annonce l'indisponibilite plutot que d'en afficher
    // un qui ne marche pas.
    PROMO_CODE:            process.env.XBET_PROMO_CODE ?? '',
    PROMO_CODE_1XBET:      '',
    PROMO_CODE_MELBET:     '',
    PROMO_CODE_BETWINNER:  '',
  };

  const valeurs = {} as Record<CleConfig, string>;
  const origine = {} as Record<CleConfig, 'base' | 'env'>;

  for (const cle of CLES_CONFIG) {
    if (base[cle] !== undefined) {
      valeurs[cle] = base[cle];
      origine[cle] = 'base';
    } else {
      valeurs[cle] = process.env[cle] ?? DEFAUTS[cle];
      origine[cle] = 'env';
    }
  }
  return { valeurs, origine };
}

/**
 * Enregistre les clés fournies. Les autres sont ignorées silencieusement —
 * l'administration ne doit pas pouvoir écrire n'importe quelle clé, ce serait
 * une surface d'écriture arbitraire dans la configuration du serveur.
 *
 * Retourne les clés réellement écrites.
 */
/**
 * Code d'affiliation a proposer pour une plateforme donnee.
 *
 * Surcharge par plateforme si elle est renseignee, code general sinon. Une
 * chaine vide n'est pas un code : elle vaut « pas de surcharge », pas
 * « surcharge vide » — sans quoi effacer un champ dans l'administration
 * couperait le code au lieu de retablir le general.
 */
export function codePromoPour(
  valeurs: Record<CleConfig, string>,
  plateforme?: string | null,
): string {
  const cle = `PROMO_CODE_${(plateforme ?? '').toUpperCase()}` as CleConfig;
  const surcharge = (valeurs as Record<string, string>)[cle]?.trim();
  return surcharge && surcharge.length > 0 ? surcharge : (valeurs.PROMO_CODE ?? '').trim();
}

/** Tous les codes, plateforme par plateforme — prêt à publier au mobile. */
export function codesPromoParPlateforme(
  valeurs: Record<CleConfig, string>,
  plateformes: readonly string[],
): Record<string, string> {
  return Object.fromEntries(
    plateformes.map(p => [p, codePromoPour(valeurs, p)]).filter(([, v]) => v !== ''),
  );
}

export async function ecrireConfig(
  entrees: Record<string, unknown>,
  parQui?: string,
): Promise<CleConfig[]> {
  const ecrites: CleConfig[] = [];

  for (const cle of CLES_CONFIG) {
    if (!(cle in entrees)) continue;

    const brut = entrees[cle];
    if (brut === null || brut === undefined) continue;

    let valeur = String(brut).trim();

    // Les booléens sont normalisés : « on » (case à cocher HTML), « 1 », « TRUE »
    // et « true » doivent produire la même chose, sinon le drapeau reste faux
    // alors que l'admin a bien coché la case.
    if (EST_BOOLEEN.has(cle)) {
      valeur = ['true', 'on', '1', 'oui'].includes(valeur.toLowerCase()) ? 'true' : 'false';
    }

    // Une URL d'APK doit être une adresse http(s) ou vide. Enregistrer autre
    // chose produirait un bouton « Mettre à jour » qui n'ouvre rien.
    if (cle === 'APK_URL' && valeur !== '' && !/^https?:\/\//i.test(valeur)) {
      throw new Error("L'URL de l'APK doit commencer par http:// ou https://, ou rester vide.");
    }

    // Les versions suivent « x.y.z ». Un champ mal saisi ferait comparer à
    // zéro, donc n'annoncerait jamais la mise à jour.
    if (cle.endsWith('_VERSION') && !/^\d+(\.\d+){0,2}$/.test(valeur)) {
      throw new Error(`Version invalide pour ${cle} : attendu « x.y.z » (reçu « ${valeur} »).`);
    }

    await prisma.appSetting.upsert({
      where:  { key: cle },
      update: { value: valeur, updatedBy: parQui ?? null },
      create: { key: cle, value: valeur, updatedBy: parQui ?? null },
    });
    ecrites.push(cle);
  }

  return ecrites;
}

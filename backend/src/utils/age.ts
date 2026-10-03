/**
 * Majorité — **source unique**, et seule autorité côté serveur.
 *
 * L'âge se calculait jusqu'ici dans un seul contrôleur, par division :
 *
 *     Math.floor((Date.now() - dob.getTime()) / (365.25 * 86400000))
 *
 * Approximation qui se trompe d'un jour autour de l'anniversaire, selon les
 * années bissextiles traversées. Sur un seuil légal, se tromper d'un jour n'est
 * pas anodin : c'est exactement le jour où quelqu'un devient majeur.
 *
 * Surtout, ce calcul ne s'appliquait qu'à `PATCH /profile`, et seulement
 * lorsqu'une date était transmise (`if (birth_date)`). Un compte dont la date
 * arrivait par un autre chemin n'était jamais contrôlé, et le reste de l'API
 * se contentait de vérifier qu'une date **existait**.
 */
export const AGE_MINIMUM = 18;

/** Âge révolu, en années pleines, par arithmétique calendaire. */
export function ageRevolu(naissance: Date, maintenant = new Date()): number {
  let age = maintenant.getUTCFullYear() - naissance.getUTCFullYear();

  const moisEcoule = maintenant.getUTCMonth() - naissance.getUTCMonth();
  const jourEcoule = maintenant.getUTCDate()  - naissance.getUTCDate();

  // L'anniversaire de cette année n'est pas encore passé.
  if (moisEcoule < 0 || (moisEcoule === 0 && jourEcoule < 0)) age -= 1;

  return age;
}

/**
 * Date valide **et** majeur.
 *
 * Une date invalide, absente ou située dans le futur ne peut pas établir la
 * majorité : dans le doute, on refuse.
 */
export function estMajeur(naissance: Date | null | undefined,
                          maintenant = new Date()): boolean {
  if (!naissance) return false;
  const d = naissance instanceof Date ? naissance : new Date(naissance);
  if (isNaN(d.getTime())) return false;
  if (d.getTime() > maintenant.getTime()) return false;
  return ageRevolu(d, maintenant) >= AGE_MINIMUM;
}

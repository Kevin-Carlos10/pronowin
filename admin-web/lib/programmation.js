/**
 * L'heure d'une programmation, du formulaire au serveur et retour.
 *
 * Un champ `datetime-local` n'a pas de fuseau : « 09:00 » tout court. Le
 * navigateur, qui connaît le sien, le convertit à l'envoi en instant ISO
 * (champ caché `quand_iso`, voir `views/_programmation_script.ejs`). Sans
 * script, la valeur est lue à l'heure de Ouagadougou — GMT, sans heure d'été :
 * celle de l'équipe.
 */
const FUSEAU = 'Africa/Ouagadougou';

/** L'instant choisi, ou `null` si le formulaire n'en porte pas de valable. */
function instantDepuisFormulaire(corps, champ) {
  const iso = String(corps?.quand_iso ?? '');
  if (/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d+)?)?Z$/.test(iso)) {
    const d = new Date(iso);
    if (Number.isFinite(d.getTime())) return d;
  }
  const brut = String(corps?.[champ] ?? '');
  const m = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})$/.exec(brut);
  if (!m) return null;
  const d = new Date(Date.UTC(+m[1], +m[2] - 1, +m[3], +m[4], +m[5]));
  return Number.isFinite(d.getTime()) ? d : null;
}

/** « 06 oct., 09:00 » à l'heure de Ouagadougou. */
const heureLocale = (iso) => iso
  ? new Date(iso).toLocaleString('fr-FR', { timeZone: FUSEAU, day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' })
  : '—';

/** Valeur par défaut d'un champ `datetime-local` : dans une heure, à la minute ronde. */
const valeurChampDans = (minutes = 60, maintenant = new Date()) => {
  const d = new Date(maintenant.getTime() + minutes * 60_000);
  d.setUTCSeconds(0, 0);
  return d.toISOString().slice(0, 16);
};

module.exports = { instantDepuisFormulaire, heureLocale, valeurChampDans, FUSEAU };

/**
 * Les sélections nationales, en français — pour le texte des notifications.
 *
 * Le fournisseur de données écrit les pays en anglais (« Belgium »). Le
 * mobile traduit les noms à la lecture (`lib/core/utils/noms_equipes.dart`),
 * mais une notification part du serveur : elle arrivait sur l'écran
 * verrouillé avec « France 2-1 Belgium », sous un pronostic « Belgique
 * gagne » (vidéo du 5 octobre 2026).
 *
 * Seules les sélections nationales sont concernées : un nom de club ne se
 * traduit pas. La catégorie qui suit le nom (« U21 », « W ») est conservée.
 *
 * La table des pays est celle du catalogue partagé (`i18n/football`), dont
 * le mobile et le panneau reçoivent la même copie générée : cette fonction en
 * portait une seconde, recopiée à la main.
 */
import { catalog, country } from '../i18n/football';

// Tolère un nom absent : une notification ne doit jamais faire échouer le
// règlement d'un pari qui l'envoie.
export function nomEquipe(nom: string | null | undefined): string {
  if (!nom) return nom ?? '';
  return country(nom, 'fr');
}

/** « France – Belgique » : l'affiche d'un match, telle que l'écrit l'application. */
export function rencontre(domicile: string | null | undefined, exterieur: string | null | undefined): string {
  return `${nomEquipe(domicile)} – ${nomEquipe(exterieur)}`;
}

/**
 * Traduit, dans un libellé de pronostic (« Norway gagne »), le nom anglais
 * des équipes du match — et d'elles seules : traduire tous les pays connus
 * toucherait aussi les noms de joueurs (« Jordan Henderson »).
 */
export function traduireEquipes(libelle: string, equipes: string[]): string {
  let s = libelle;
  for (const equipe of equipes) {
    const fr = nomEquipe(equipe);
    for (const pays of catalog.countries as { en: string; fr: string; aliases: string[] }[]) {
      if (pays.fr !== fr) continue;
      for (const nom of [pays.en, ...pays.aliases]) {
        if (!nom || nom === fr) continue;
        const echappe = nom.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
        s = s.replace(new RegExp(`(?<!\\p{L})${echappe}(?!\\p{L})`, 'gu'), fr);
      }
    }
  }
  return s;
}

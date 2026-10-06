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
 * ── Sur la duplication ──────────────────────────────────────────────────────
 *
 * Cette table existe aussi côté mobile. `noms_equipes.test.ts` lit le
 * fichier Dart et refuse que les deux s'éloignent.
 */
export const PAYS: Readonly<Record<string, string>> = {
  "Albania": "Albanie", "Andorra": "Andorre", "Armenia": "Arménie", "Austria": "Autriche", "Azerbaijan": "Azerbaïdjan",
  "Belarus": "Biélorussie", "Belgium": "Belgique", "Bosnia & Herzegovina": "Bosnie-Herzégovine",
  "Bosnia and Herzegovina": "Bosnie-Herzégovine", "Bulgaria": "Bulgarie", "Croatia": "Croatie",
  "Cyprus": "Chypre", "Czech Republic": "Tchéquie", "Czechia": "Tchéquie", "Denmark": "Danemark",
  "England": "Angleterre", "Estonia": "Estonie", "Faroe Islands": "Îles Féroé", "Finland": "Finlande",
  "Georgia": "Géorgie", "Germany": "Allemagne", "Greece": "Grèce", "Hungary": "Hongrie", "Iceland": "Islande",
  "Israel": "Israël", "Italy": "Italie", "Kazakhstan": "Kazakhstan", "Kosovo": "Kosovo", "Latvia": "Lettonie",
  "Lithuania": "Lituanie", "Moldova": "Moldavie", "Montenegro": "Monténégro", "Netherlands": "Pays-Bas",
  "North Macedonia": "Macédoine du Nord", "FYR Macedonia": "Macédoine du Nord", "Northern Ireland": "Irlande du Nord",
  "Norway": "Norvège", "Poland": "Pologne", "Rep. Of Ireland": "Irlande", "Republic of Ireland": "Irlande",
  "Ireland": "Irlande", "Romania": "Roumanie", "Russia": "Russie", "Scotland": "Écosse", "Serbia": "Serbie",
  "Slovakia": "Slovaquie", "Slovenia": "Slovénie", "Spain": "Espagne", "Sweden": "Suède", "Switzerland": "Suisse",
  "Turkey": "Turquie", "Türkiye": "Turquie", "Ukraine": "Ukraine", "Wales": "Pays de Galles",
  "Algeria": "Algérie", "Benin": "Bénin", "Botswana": "Botswana", "Burundi": "Burundi", "Cameroon": "Cameroun",
  "Cape Verde Islands": "Cap-Vert", "Cape Verde": "Cap-Vert", "Central African Republic": "Centrafrique",
  "Chad": "Tchad", "Comoros": "Comores", "Congo": "Congo", "Congo DR": "RD Congo", "DR Congo": "RD Congo",
  "Djibouti": "Djibouti", "Egypt": "Égypte", "Equatorial Guinea": "Guinée équatoriale", "Eritrea": "Érythrée",
  "Eswatini": "Eswatini", "Ethiopia": "Éthiopie", "Gambia": "Gambie", "Guinea": "Guinée", "Guinea-Bissau": "Guinée-Bissau",
  "Ivory Coast": "Côte d'Ivoire", "Cote D'Ivoire": "Côte d'Ivoire", "Kenya": "Kenya", "Lesotho": "Lesotho",
  "Liberia": "Liberia", "Libya": "Libye", "Madagascar": "Madagascar", "Malawi": "Malawi", "Mauritania": "Mauritanie",
  "Mauritius": "Maurice", "Morocco": "Maroc", "Mozambique": "Mozambique", "Namibia": "Namibie",
  "Nigeria": "Nigeria", "Rwanda": "Rwanda", "Sao Tome and Principe": "Sao Tomé-et-Principe",
  "Senegal": "Sénégal", "Seychelles": "Seychelles", "Sierra Leone": "Sierra Leone", "Somalia": "Somalie",
  "South Africa": "Afrique du Sud", "South Sudan": "Soudan du Sud", "Sudan": "Soudan", "Tanzania": "Tanzanie",
  "Tunisia": "Tunisie", "Uganda": "Ouganda", "Zambia": "Zambie", "Zimbabwe": "Zimbabwe", "Argentina": "Argentine",
  "Bolivia": "Bolivie", "Brazil": "Brésil", "Canada": "Canada", "Chile": "Chili", "Colombia": "Colombie",
  "Costa Rica": "Costa Rica", "Curacao": "Curaçao", "Ecuador": "Équateur", "El Salvador": "Salvador",
  "Guatemala": "Guatemala", "Haiti": "Haïti", "Honduras": "Honduras", "Jamaica": "Jamaïque",
  "Mexico": "Mexique", "Panama": "Panama", "Paraguay": "Paraguay", "Peru": "Pérou", "Trinidad and Tobago": "Trinité-et-Tobago",
  "Uruguay": "Uruguay", "USA": "États-Unis", "United States": "États-Unis", "Venezuela": "Venezuela",
  "Australia": "Australie", "Bahrain": "Bahreïn", "China": "Chine", "China PR": "Chine", "India": "Inde",
  "Indonesia": "Indonésie", "Iran": "Iran", "Iraq": "Irak", "Japan": "Japon", "Jordan": "Jordanie",
  "Korea Republic": "Corée du Sud", "South Korea": "Corée du Sud", "North Korea": "Corée du Nord",
  "Kuwait": "Koweït", "Lebanon": "Liban", "Malaysia": "Malaisie", "New Zealand": "Nouvelle-Zélande",
  "Oman": "Oman", "Palestine": "Palestine", "Qatar": "Qatar", "Saudi Arabia": "Arabie saoudite",
  "Syria": "Syrie", "Thailand": "Thaïlande", "United Arab Emirates": "Émirats arabes unis", "Uzbekistan": "Ouzbékistan",
  "Vietnam": "Viêt Nam", "Yemen": "Yémen",
};

const CATEGORIE = /^(.+?)\s+(U\d{2}|W)$/;

// Tolère un nom absent : une notification ne doit jamais faire échouer le
// règlement d'un pari qui l'envoie.
export function nomEquipe(nom: string | null | undefined): string {
  if (!nom) return nom ?? '';
  const brut = nom.trim();
  const direct = PAYS[brut];
  if (direct) return direct;
  const m = CATEGORIE.exec(brut);
  if (m) {
    const base = PAYS[m[1].trim()];
    if (base) return `${base} ${m[2]}`;
  }
  return nom;
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
    for (const [en, traduit] of Object.entries(PAYS)) {
      if (traduit !== fr) continue;
      const echappe = en.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
      s = s.replace(new RegExp(`(?<!\\p{L})${echappe}(?!\\p{L})`, 'gu'), fr);
    }
  }
  return s;
}

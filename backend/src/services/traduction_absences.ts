/**
 * Motifs d'absence, traduits à la frontière du fournisseur.
 *
 * API-Football renvoie « Hamstring Injury », « Hip Injury », « Knee Injury ».
 * Une table vivait côté mobile et couvrait l'essentiel — mais elle avait des
 * trous, et **rien ne les signalait** : l'écran affichait « Blessure
 * musculaire » et « Hamstring Injury » l'un sous l'autre, dans la même liste.
 *
 * Deux changements par rapport à cette table :
 *
 *  1. **Une règle générale plutôt qu'une liste d'exceptions.** « X Injury » se
 *     traduit à partir d'une partie du corps, si bien qu'un nouveau membre
 *     n'exige plus une nouvelle entrée. C'est ce qui manquait : la table
 *     contenait `hamstring` mais l'API envoie `Hamstring Injury`.
 *  2. **Les inconnus se signalent.** Un motif non reconnu est rendu tel quel —
 *     mieux vaut un mot anglais qu'une traduction inventée — mais il est
 *     journalisé, ce qui rend le trou visible au lieu de le laisser à l'écran.
 *
 * Traduit ici, comme les recommandations et les marchés : tous les
 * consommateurs en bénéficient, et aucun écran n'a à connaître l'anglais.
 */

/** Partie du corps → complément français, préposition comprise. */
const PARTIES: Record<string, string> = {
  knee:      'au genou',
  ankle:     'à la cheville',
  thigh:     'à la cuisse',
  hamstring: 'aux ischio-jambiers',
  muscle:    'musculaire',
  calf:      'au mollet',
  groin:     'à l\'aine',
  back:      'au dos',
  shoulder:  'à l\'épaule',
  foot:      'au pied',
  hip:       'à la hanche',
  head:      'à la tête',
  neck:      'à la nuque',
  arm:       'au bras',
  hand:      'à la main',
  wrist:     'au poignet',
  elbow:     'au coude',
  toe:       'à l\'orteil',
  rib:       'aux côtes',
  chest:     'à la poitrine',
  abdominal: 'abdominale',
  achilles:  'au tendon d\'Achille',
  ligament:  'ligamentaire',
  fitness:   'physique',
};

/** Motifs qui ne décrivent pas une blessure. */
const AUTRES: Record<string, string> = {
  'yellow cards':     'Suspendu (cartons jaunes)',
  'yellow card':      'Suspendu (carton jaune)',
  'red card':         'Suspendu (carton rouge)',
  'suspended':        'Suspendu',
  'inactive':         'Indisponible',
  'injury':           'Blessé',
  'injured':          'Blessé',
  'illness':          'Maladie',
  'personal reasons': 'Raisons personnelles',
  'national team':    'Sélection nationale',
  'coach decision':   'Choix de l\'entraîneur',
  'rest':             'Au repos',
  'broken leg':       'Jambe cassée',
  'broken foot':      'Pied cassé',
  'broken arm':       'Bras cassé',
  'questionable':     'Incertain',
  'missing fixture':  'Absent',
  'unknown':          'Motif inconnu',
};

const inconnus = new Set<string>();

/**
 * Traduit un motif d'absence.
 *
 * Rend le texte d'origine si rien ne correspond : perdre l'information serait
 * pire que l'afficher en anglais.
 */
export function traduireAbsence(motif: unknown): string {
  if (typeof motif !== 'string') return '';
  const texte = motif.trim();
  if (!texte) return '';

  const cle = texte.toLowerCase();

  const direct = AUTRES[cle];
  if (direct) return direct;

  // « Hamstring Injury » → partie = « hamstring ».
  const blessure = cle.match(/^(.+?)\s+injury$/);
  if (blessure) {
    const partie = PARTIES[blessure[1].trim()];
    if (partie) return `Blessure ${partie}`;
  }

  // « Knee » seul, sans le mot « injury ».
  const seule = PARTIES[cle];
  if (seule) return `Blessure ${seule}`;

  if (!inconnus.has(cle)) {
    inconnus.add(cle);
    console.warn(`[Absences] motif non traduit : « ${texte} »`);
  }
  return texte;
}

/** Une absence est-elle une suspension plutôt qu'une indisponibilité physique ? */
export function estSuspension(motif: unknown): boolean {
  if (typeof motif !== 'string') return false;
  const cle = motif.toLowerCase();
  return cle.includes('card') || cle.includes('suspend');
}

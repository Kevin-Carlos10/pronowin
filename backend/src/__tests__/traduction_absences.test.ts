import { traduireAbsence, estSuspension } from '../services/traduction_absences';

/**
 * L'onglet Blessures affichait, dans la même liste :
 *
 *     R. Asencio      Blessure musculaire
 *     Eder Militao    Hamstring Injury
 *     F. Mendy        Hip Injury
 *     T. Pitarch      Blessure au genou
 *
 * Une table de traduction existait bien, côté mobile, et sa règle était juste.
 * Mais elle avait des trous — elle contenait `hamstring` quand l'API envoie
 * `Hamstring Injury` — et **rien ne les signalait**.
 */
describe('les motifs de la capture', () => {
  it('Hamstring Injury', () => {
    expect(traduireAbsence('Hamstring Injury')).toBe('Blessure aux ischio-jambiers');
  });

  it('Hip Injury', () => {
    expect(traduireAbsence('Hip Injury')).toBe('Blessure à la hanche');
  });

  it('Knee Injury', () => {
    expect(traduireAbsence('Knee Injury')).toBe('Blessure au genou');
  });

  it('Muscle Injury', () => {
    expect(traduireAbsence('Muscle Injury')).toBe('Blessure musculaire');
  });

  it('Groin Injury', () => {
    expect(traduireAbsence('Groin Injury')).toBe('Blessure à l\'aine');
  });
});

describe('la règle générale remplace la liste d\'exceptions', () => {
  // C'est le point : une nouvelle partie du corps ne demande plus une nouvelle
  // entrée « X Injury », seulement la partie elle-même.
  it('traduit une partie du corps jamais listée sous forme « X Injury »', () => {
    for (const [motif, attendu] of [
      ['Elbow Injury', 'Blessure au coude'],
      ['Wrist Injury', 'Blessure au poignet'],
      ['Rib Injury',   'Blessure aux côtes'],
    ]) {
      expect(traduireAbsence(motif)).toBe(attendu);
    }
  });

  it('accepte la partie seule, sans le mot « injury »', () => {
    expect(traduireAbsence('Knee')).toBe('Blessure au genou');
  });

  it('la casse et les espaces n\'ont pas d\'importance', () => {
    expect(traduireAbsence('  KNEE INJURY  ')).toBe('Blessure au genou');
  });
});

describe('les motifs qui ne décrivent pas une blessure', () => {
  it('suspensions', () => {
    expect(traduireAbsence('Red Card')).toBe('Suspendu (carton rouge)');
    expect(traduireAbsence('Yellow Cards')).toBe('Suspendu (cartons jaunes)');
    expect(traduireAbsence('Suspended')).toBe('Suspendu');
  });

  it('indisponibilités diverses', () => {
    expect(traduireAbsence('Illness')).toBe('Maladie');
    expect(traduireAbsence('Personal Reasons')).toBe('Raisons personnelles');
    expect(traduireAbsence('Coach Decision')).toBe('Choix de l\'entraîneur');
  });
});

describe('ce qui n\'est pas traduit', () => {
  // Perdre l'information serait pire que l'afficher en anglais — et le journal
  // rend le trou visible, ce qui manquait à la table précédente.
  it('un motif inconnu est rendu tel quel', () => {
    expect(traduireAbsence('Sanction fédérale interne')).toBe('Sanction fédérale interne');
  });

  it('une valeur vide ou absente ne produit rien', () => {
    expect(traduireAbsence('')).toBe('');
    expect(traduireAbsence('   ')).toBe('');
    expect(traduireAbsence(null)).toBe('');
    expect(traduireAbsence(undefined)).toBe('');
    expect(traduireAbsence(42)).toBe('');
  });
});

describe('suspension ou indisponibilité physique', () => {
  it('reconnaît une suspension', () => {
    expect(estSuspension('Red Card')).toBe(true);
    expect(estSuspension('Yellow Cards')).toBe(true);
    expect(estSuspension('Suspended')).toBe(true);
  });

  it('ne confond pas une blessure avec une suspension', () => {
    expect(estSuspension('Hamstring Injury')).toBe(false);
    expect(estSuspension('Illness')).toBe(false);
  });

  it('une valeur absente n\'est pas une suspension', () => {
    expect(estSuspension(null)).toBe(false);
  });
});

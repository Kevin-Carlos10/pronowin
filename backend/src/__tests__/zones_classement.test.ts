import { zoneDepuisDescription } from '../services/zones_classement';

/**
 * Un classement sans ses zones ne dit pas ce qui se joue.
 *
 * « 7ᵉ avec 3 points » ne signifie rien tant qu'on ignore si cette place
 * qualifie pour l'Europe ou frôle la relégation — et c'est justement ce qui
 * change la nature d'un match : une équipe qui joue son maintien ne dispute
 * pas la même rencontre qu'une équipe déjà sauvée.
 *
 * L'information existait chez le fournisseur (`description`) et n'était pas
 * lue.
 */
describe('zones reconnues', () => {
  const cas: Array<[string, string, string]> = [
    ['Promotion - Champions League (Group Stage)', 'Ligue des champions', 'c1'],
    ['Promotion - Europa League (Group Stage)',    'Ligue Europa',        'c3'],
    ['Promotion - Europa Conference League (Qualification)',
                                                  'Ligue Conférence',    'c4'],
    ['Relegation - LaLiga2',                      'Relégation',          'relegation'],
    ['Relegation - Championship',                 'Relégation',          'relegation'],
    ['Promotion - Premier League',                'Promotion',           'promotion'],
  ];

  for (const [description, libelle, nature] of cas) {
    it(`« ${description} »`, () => {
      const z = zoneDepuisDescription(description);
      expect(z?.libelle).toBe(libelle);
      expect(z?.nature).toBe(nature);
    });
  }

  // L'ordre des motifs compte : « Europa Conference League » contient le mot
  // « Europa » et serait rangé en C3 si la règle C3 passait d'abord.
  it('ne confond pas la Ligue Conférence avec la Ligue Europa', () => {
    expect(zoneDepuisDescription('Europa Conference League')?.nature).toBe('c4');
    expect(zoneDepuisDescription('Europa League')?.nature).toBe('c3');
  });

  it('distingue un barrage d\'une relégation directe', () => {
    expect(zoneDepuisDescription('Relegation Play-off')?.nature).toBe('barrage');
    expect(zoneDepuisDescription('Relegation')?.nature).toBe('relegation');
  });

  it('la casse et les espaces n\'ont pas d\'importance', () => {
    expect(zoneDepuisDescription('  CHAMPIONS LEAGUE  ')?.nature).toBe('c1');
  });
});

describe('ce qui ne se traduit pas', () => {
  // Mieux vaut une ligne sans zone qu'une ligne rangée dans la mauvaise.
  it('une description inconnue ne produit aucune zone', () => {
    expect(zoneDepuisDescription('Copa Libertadores Play-in')).toBeNull();
  });

  it('une valeur absente ou vide', () => {
    expect(zoneDepuisDescription(null)).toBeNull();
    expect(zoneDepuisDescription(undefined)).toBeNull();
    expect(zoneDepuisDescription('')).toBeNull();
    expect(zoneDepuisDescription('   ')).toBeNull();
  });

  it('une valeur qui n\'est pas une chaîne', () => {
    expect(zoneDepuisDescription(42)).toBeNull();
    expect(zoneDepuisDescription({})).toBeNull();
  });

  // La couleur doit dépendre de la nature, jamais du libellé : deux
  // championnats nomment différemment la même zone.
  it('deux libellés différents partagent la même nature', () => {
    const a = zoneDepuisDescription('Relegation - LaLiga2');
    const b = zoneDepuisDescription('Relegation - Serie B');
    expect(a?.nature).toBe(b?.nature);
  });
});

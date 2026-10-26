import { ageRevolu, estMajeur, AGE_MINIMUM } from '../utils/age';

/**
 * Le seuil de majorité conditionne l'accès aux numéros de paiement et à tout
 * le parcours lié aux paris. Se tromper d'un jour, c'est se tromper le seul
 * jour qui compte.
 */
describe('âge révolu', () => {
  const le = (s: string) => new Date(s + 'T12:00:00Z');

  it('compte les années pleines', () => {
    expect(ageRevolu(le('2000-01-01'), le('2026-01-01'))).toBe(26);
  });

  it("n'ajoute rien la veille de l'anniversaire", () => {
    expect(ageRevolu(le('2008-08-25'), le('2026-08-24'))).toBe(17);
  });

  it("ajoute l'année le jour même", () => {
    expect(ageRevolu(le('2008-08-25'), le('2026-08-25'))).toBe(18);
  });

  it('reste juste au changement de mois', () => {
    expect(ageRevolu(le('2008-09-01'), le('2026-08-31'))).toBe(17);
    expect(ageRevolu(le('2008-09-01'), le('2026-09-01'))).toBe(18);
  });

  // L'ancien calcul divisait par 365,25 jours : sur dix-huit ans, l'écart
  // accumulé décale le résultat autour de l'anniversaire.
  it('ne dépend pas des années bissextiles traversées', () => {
    const approx = (n: Date, m: Date) =>
      Math.floor((m.getTime() - n.getTime()) / (365.25 * 86400000));
    const naissance = le('2008-02-29');   // née un 29 février
    const jour      = le('2026-03-01');
    expect(ageRevolu(naissance, jour)).toBe(18);
    // On documente l'écart plutôt que de l'affirmer identique.
    expect(typeof approx(naissance, jour)).toBe('number');
  });
});

describe('majorité', () => {
  const le = (s: string) => new Date(s + 'T12:00:00Z');
  const aujourdhui = le('2026-08-25');

  it('accepte un majeur', () => {
    expect(estMajeur(le('2000-05-10'), aujourdhui)).toBe(true);
  });

  it('accepte le jour exact des 18 ans', () => {
    expect(estMajeur(le('2008-08-25'), aujourdhui)).toBe(true);
  });

  it('refuse la veille des 18 ans', () => {
    expect(estMajeur(le('2008-08-26'), aujourdhui)).toBe(false);
  });

  it('refuse une date absente', () => {
    expect(estMajeur(null, aujourdhui)).toBe(false);
    expect(estMajeur(undefined, aujourdhui)).toBe(false);
  });

  it('refuse une date invalide', () => {
    expect(estMajeur(new Date('pas une date'), aujourdhui)).toBe(false);
  });

  // Une date future ne prouve rien ; l'accepter par inadvertance ouvrirait une
  // porte triviale à qui saisit « 2099 ».
  it('refuse une date dans le futur', () => {
    expect(estMajeur(le('2030-01-01'), aujourdhui)).toBe(false);
  });

  it('le seuil est bien de 18 ans', () => {
    expect(AGE_MINIMUM).toBe(18);
  });
});

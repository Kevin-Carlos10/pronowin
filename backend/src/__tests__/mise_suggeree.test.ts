import {
  miseSuggeree,
  partSelonConfiance,
  pasDeDevise,
} from '../services/mise_suggeree';

/**
 * Une mise suggérée ne dépasse pas ce qu'on possède, et ne s'appelle pas Kelly.
 *
 * ── Trois défauts de calcul ────────────────────────────────────────────────
 *
 * `Math.max(100, …)` imposait un plancher de 100 sans regarder le solde : avec
 * 50 en banque, l'application conseillait de miser 100. L'arrondi à la
 * centaine, pensé pour le franc CFA, s'appliquait à toutes les devises. Et le
 * même arrondi écrasait les petits capitaux — 3 % de 1 000 vaut 30, l'arrondi
 * rendait 0, le plancher remontait à 100, soit trois fois la part annoncée.
 *
 * ── Et un défaut de nom ────────────────────────────────────────────────────
 *
 * Le calcul s'appelait « Kelly simplifié ». Le critère de Kelly met en rapport
 * une probabilité et une cote ; celui-ci applique une part fixe selon la note
 * de 1 à 5 cochée par l'analyste. La règle est défendable — lui emprunter le
 * nom d'une formule mathématique ne l'est pas.
 */
describe('la part engagée selon la confiance', () => {
  it('monte avec la note, et plafonne à 5 %', () => {
    expect(partSelonConfiance(5)).toBe(0.05);
    expect(partSelonConfiance(4)).toBe(0.03);
    expect(partSelonConfiance(3)).toBe(0.03);
    expect(partSelonConfiance(2)).toBe(0.015);
    expect(partSelonConfiance(1)).toBe(0.015);
  });

  it('ne dépasse jamais 5 %, même pour une note aberrante', () => {
    // Le contrôleur passait `60` — un pourcentage pris pour une note. La
    // fonction doit rester bornée quoi qu'on lui donne.
    expect(partSelonConfiance(60)).toBe(0.05);
    expect(partSelonConfiance(0)).toBe(0.015);
    expect(partSelonConfiance(-3)).toBe(0.015);
  });
});

describe('le pas d\'arrondi suit la devise', () => {
  it('compte par centaines là où la subdivision n\'a pas cours', () => {
    expect(pasDeDevise('XOF')).toBe(100);
    expect(pasDeDevise('XAF')).toBe(100);
    expect(pasDeDevise('GNF')).toBe(100);
  });

  it('compte à l\'unité en euros', () => {
    // Arrondir une mise en euros à la centaine n'a aucun sens.
    expect(pasDeDevise('EUR')).toBe(1);
  });

  it('prend le pas le plus fin pour une devise inconnue', () => {
    // Mieux vaut un montant précis qu'un montant arrondi selon les habitudes
    // d'un autre pays.
    expect(pasDeDevise('USD')).toBe(1);
    expect(pasDeDevise(null)).toBe(1);
    expect(pasDeDevise('')).toBe(1);
  });

  it('ignore la casse', () => {
    expect(pasDeDevise('xof')).toBe(100);
  });
});

describe('la mise suggérée', () => {
  it('ne dépasse jamais le solde — le cas signalé', () => {
    // 50 en banque : l'application conseillait 100.
    const m = miseSuggeree(50, 5, 'XOF');
    expect(m).toBeLessThanOrEqual(50);
    expect(m).toBeGreaterThan(0);
  });

  it('respecte la part annoncée sur un petit capital', () => {
    // 3 % de 1 000 valent 30. L'arrondi à la centaine rendait 0, puis le
    // plancher remontait à 100 : dix pour cent du capital.
    expect(miseSuggeree(1000, 4, 'XOF')).toBe(30);
  });

  it('arrondit aux centaines sur un capital courant', () => {
    // 5 % de 50 000 valent 2 500 : rond, et déjà au pas.
    expect(miseSuggeree(50_000, 5, 'XOF')).toBe(2500);
    // 3 % de 42 000 valent 1 260 → 1 300 à la centaine la plus proche.
    expect(miseSuggeree(42_000, 4, 'XOF')).toBe(1300);
  });

  it('compte à l\'unité en euros', () => {
    // 3 % de 200 € valent 6 € — et non « 0 » puis « 100 € ».
    expect(miseSuggeree(200, 4, 'EUR')).toBe(6);
  });

  it('rend zéro sans capital', () => {
    // Contrepartie : proposer une mise à qui n'a rien serait pire que rien.
    expect(miseSuggeree(0, 5, 'XOF')).toBe(0);
    expect(miseSuggeree(-100, 5, 'XOF')).toBe(0);
    expect(miseSuggeree(Number.NaN, 5, 'XOF')).toBe(0);
  });

  it('propose toujours quelque chose tant qu\'il reste de quoi miser', () => {
    // Contrepartie de la précédente : un capital minuscule mais réel ne doit
    // pas rendre une suggestion nulle, qui bloquerait l'écran sans le dire.
    const m = miseSuggeree(20, 1, 'XOF');
    expect(m).toBeGreaterThan(0);
    expect(m).toBeLessThanOrEqual(20);
  });

  it('reste proportionnelle sur toute l\'échelle des soldes', () => {
    // Le garde-fou qui compte : la mise ne doit jamais représenter une part
    // sensiblement plus grande que celle annoncée.
    for (const solde of [200, 1000, 5000, 12_345, 100_000]) {
      const m = miseSuggeree(solde, 4, 'XOF');
      expect(m / solde).toBeLessThanOrEqual(0.05);
      expect(m).toBeLessThanOrEqual(solde);
    }
  });
});

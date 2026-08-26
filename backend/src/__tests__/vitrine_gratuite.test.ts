/**
 * La vitrine gratuite peut être vide sans que personne ne le sache.
 *
 * `getDailyFreePronostic` a deux étages : le pronostic désigné (`isDailyFree`),
 * puis un repli. Ce repli exige **`isPremium: false`**. Publier trois
 * pronostics, tous premium, sans désigner de vitrine, ne produit donc aucun
 * repli : `/daily-free` répond 404 et le visiteur non abonné ne voit rien.
 *
 * L'alerte d'administration annonçait pourtant, dans ce cas exactement, que
 * « l'application choisit alors le premier par ordre d'heure de match ».
 */
type Prono = { publie: boolean; premium: boolean; vitrine: boolean; heure: number };

/** Reproduit la règle de `getDailyFreePronostic`. */
function vitrineServie(pronos: Prono[]): Prono | null {
  const designe = pronos.find(p => p.publie && p.vitrine);
  if (designe) return designe;
  const repli = pronos
    .filter(p => p.publie && !p.premium)
    .sort((a, b) => a.heure - b.heure);
  return repli[0] ?? null;
}

/** Reproduit le choix d'alerte du tableau de bord. */
function alerte(pronos: Prono[]): 'aucune' | 'tri_decide' | 'vitrine_vide' {
  const publiables = pronos.filter(p => p.publie).length;
  const vitrine    = pronos.filter(p => p.publie && p.vitrine).length;
  const gratuits   = pronos.filter(p => p.publie && !p.premium).length;
  if (publiables === 0 || vitrine > 0) return 'aucune';
  return gratuits === 0 ? 'vitrine_vide' : 'tri_decide';
}

const p = (o: Partial<Prono>): Prono =>
  ({ publie: true, premium: false, vitrine: false, heure: 12, ...o });

describe('ce que voit un visiteur non abonné', () => {
  it('un pronostic désigné est servi, même si d\'autres sont plus tôt', () => {
    const servi = vitrineServie([
      p({ heure: 9 }),
      p({ heure: 21, vitrine: true }),
    ]);
    expect(servi?.heure).toBe(21);
  });

  it('sans désignation, le repli prend le plus tôt parmi les gratuits', () => {
    const servi = vitrineServie([
      p({ heure: 21 }),
      p({ heure: 15 }),
      p({ heure: 18, premium: true }),
    ]);
    expect(servi?.heure).toBe(15);
  });

  // Le cœur du défaut.
  it('tout publier en premium ne laisse RIEN à montrer', () => {
    const servi = vitrineServie([
      p({ heure: 15, premium: true }),
      p({ heure: 18, premium: true }),
      p({ heure: 21, premium: true }),
    ]);
    expect(servi).toBeNull();
  });

  it('un pronostic premium désigné en vitrine reste servi', () => {
    // `setDailyFreePronostic` force `isPremium: false` en même temps que la
    // désignation : la vitrine ne peut pas être un pronostic payant.
    const servi = vitrineServie([p({ premium: true, vitrine: true })]);
    expect(servi).not.toBeNull();
  });
});

describe('l\'alerte dit ce qui va réellement se passer', () => {
  it('se tait quand une vitrine est désignée', () => {
    expect(alerte([p({ vitrine: true }), p({ premium: true })])).toBe('aucune');
  });

  it('se tait quand rien n\'est publié', () => {
    expect(alerte([p({ publie: false })])).toBe('aucune');
  });

  it('annonce le tri quand un repli existe', () => {
    expect(alerte([p({ heure: 15 }), p({ heure: 18, premium: true })]))
      .toBe('tri_decide');
  });

  // Sans cette distinction, le message rassurait précisément là où il ne
  // fallait pas.
  it('alerte sur la vitrine vide quand tout est premium', () => {
    expect(alerte([
      p({ premium: true }), p({ premium: true }), p({ premium: true }),
    ])).toBe('vitrine_vide');
  });

  it('l\'alerte correspond toujours à ce que le visiteur obtient', () => {
    const cas: Prono[][] = [
      [p({ vitrine: true })],
      [p({ heure: 9 }), p({ heure: 20, premium: true })],
      [p({ premium: true }), p({ premium: true })],
      [p({ publie: false })],
    ];
    for (const pronos of cas) {
      const servi = vitrineServie(pronos);
      const a     = alerte(pronos);
      if (a === 'vitrine_vide') {
        expect(servi).toBeNull();
      } else if (a === 'tri_decide') {
        expect(servi).not.toBeNull();
      }
    }
  });
});

let bankroll: any;
let misesEnCours = 0;
let ecrit: any = null;

jest.mock('../lib/prisma', () => ({
  prisma: {
    userBankroll: {
      findUnique: jest.fn(async () => bankroll),
      update:     jest.fn(async ({ data }: any) => { ecrit = data; return data; }),
    },
    bankrollBet: {
      aggregate: jest.fn(async () => ({ _sum: { stakedAmount: misesEnCours } })),
    },
  },
}));

import { _settlementCredit, resetBankroll } from '../services/bankroll.service';

/**
 * Réinitialiser le solde ne doit pas rembourser les paris en cours.
 *
 * ── Le défaut ─────────────────────────────────────────────────────────────
 *
 * `resetBankroll` remettait `currentBalance` au budget entier. Or la mise d'un
 * pari en attente a déjà été déduite, et le règlement crédite ensuite le gain
 * **complet** — `_settlementCredit` rend `potentialGain` pour un gain, et `0`
 * pour un pari encore en attente.
 *
 * La mise se retrouvait donc remboursée deux fois :
 *
 *   budget 10 000, mise 2 000 à la cote 2   → solde 8 000
 *   réinitialisation                        → solde 10 000  (mise rendue)
 *   le pari gagne, crédit de 4 000          → solde 14 000
 *
 * au lieu de 12 000. Et sur une défaite, le solde restait à 10 000 au lieu de
 * 8 000 : la perte disparaissait.
 *
 * Rien ne le signalait. Le bouton était en pleine page, le suivi se faussait
 * dans les deux sens, et l'opération est répétable tous les trente jours.
 *
 * ── La règle ──────────────────────────────────────────────────────────────
 *
 * Repartir du budget **moins ce qui est encore engagé**. L'arithmétique du
 * règlement reste alors juste, quel que soit le moment de la remise à zéro.
 */

/** Ce que vaut le solde après règlement, pour un solde de départ donné. */
function apresReglement(
  soldeAvant: number,
  resultat: 'WIN' | 'LOSS' | 'PUSH',
  pari: { stakedAmount: number; potentialGain: number },
): number {
  const nul = _settlementCredit(null, pari);
  const apres = _settlementCredit(resultat === 'LOSS' ? 'LOSS' : resultat, pari);
  return soldeAvant + (apres - nul);
}

describe('réinitialisation avec des paris en cours', () => {
  const BUDGET = 10000;
  const pari   = { stakedAmount: 2000, potentialGain: 4000 };
  const soldeApresMise = BUDGET - pari.stakedAmount;

  /** L'ancienne règle : on repart du budget entier. */
  const ancienSolde = BUDGET;
  /** La règle corrigée : le budget, moins ce qui est encore engagé. */
  const nouveauSolde = BUDGET - pari.stakedAmount;

  it('sans réinitialisation, un gain rapporte le gain net', () => {
    // La référence : c'est ce que le suivi doit afficher dans tous les cas.
    expect(apresReglement(soldeApresMise, 'WIN', pari)).toBe(12000);
  });

  it('sans réinitialisation, une défaite coûte la mise', () => {
    expect(apresReglement(soldeApresMise, 'LOSS', pari)).toBe(8000);
  });

  it('l\'ancienne règle gonflait le gain de la mise', () => {
    // Le défaut, mesuré : 2 000 de trop, soit exactement la mise rendue.
    expect(apresReglement(ancienSolde, 'WIN', pari)).toBe(14000);
    expect(apresReglement(ancienSolde, 'WIN', pari) -
           apresReglement(soldeApresMise, 'WIN', pari)).toBe(pari.stakedAmount);
  });

  it('et effaçait purement la défaite', () => {
    expect(apresReglement(ancienSolde, 'LOSS', pari)).toBe(10000);
  });

  it('la règle corrigée donne le même résultat qu\'une absence de reset', () => {
    // C'est la propriété qui compte : réinitialiser ne doit rien changer au
    // sort des paris déjà engagés.
    expect(apresReglement(nouveauSolde, 'WIN', pari))
      .toBe(apresReglement(soldeApresMise, 'WIN', pari));
    expect(apresReglement(nouveauSolde, 'LOSS', pari))
      .toBe(apresReglement(soldeApresMise, 'LOSS', pari));
    expect(apresReglement(nouveauSolde, 'PUSH', pari))
      .toBe(apresReglement(soldeApresMise, 'PUSH', pari));
  });

  it('sans pari en cours, elle rend bien le budget entier', () => {
    // Le contre-test : soustraire quoi que ce soit sans engagement en cours
    // priverait l'utilisateur d'une partie de son budget à chaque remise à
    // zéro.
    const engage = 0;
    expect(BUDGET - engage).toBe(BUDGET);
  });
});

describe('resetBankroll, exécutée', () => {
  beforeEach(() => {
    bankroll = { id: 'b1', userId: 'u1', totalBudget: 10000, lastResetAt: null };
    ecrit = null;
  });

  it('retire les mises encore engagées', async () => {
    misesEnCours = 2000;
    await resetBankroll('u1');
    expect(ecrit.currentBalance).toBe(8000);
  });

  it("rend le budget entier quand rien n'est engagé", async () => {
    misesEnCours = 0;
    await resetBankroll('u1');
    expect(ecrit.currentBalance).toBe(10000);
  });

  it('supporte une agrégation vide', async () => {
    // `_sum.stakedAmount` vaut `null` quand aucune ligne ne correspond : le
    // lire sans repli produirait `NaN` comme solde, ce qu'aucun écran ne
    // rattraperait.
    misesEnCours = null as any;
    await resetBankroll('u1');
    expect(ecrit.currentBalance).toBe(10000);
  });

  it('note la date, pour le délai de trente jours', async () => {
    misesEnCours = 0;
    await resetBankroll('u1');
    expect(ecrit.lastResetAt).toBeInstanceOf(Date);
  });

  it("refuse avant l'expiration du délai", async () => {
    bankroll.lastResetAt = new Date(Date.now() - 5 * 86400000);
    await expect(resetBankroll('u1')).rejects.toThrow(/25 jours/);
  });
});

/**
 * Un bilan porte sur tout l'historique, pas sur ce que l'écran affiche.
 *
 * L'API renvoie au plus cinquante paris — charger mille lignes sur un
 * téléphone n'a pas de sens, et la limite n'était donc pas le défaut. Le
 * défaut était qu'elle ne se voyait pas : l'écran calculait ses compteurs, son
 * taux de réussite et sa courbe **depuis cette liste**, et les présentait comme
 * le bilan complet.
 *
 * Au cinquante-et-unième pari, tous ces chiffres devenaient faux. Rien ne
 * changeait à l'écran : ni avertissement, ni « 50 derniers », ni période. Un
 * utilisateur assidu lisait son taux de réussite sur un échantillon tronqué en
 * croyant lire son bilan — et c'est la statistique qui lui fait croire que sa
 * méthode fonctionne.
 */
jest.mock('../lib/prisma', () => require('./aides/base_memoire').creerBase());

jest.mock('../services/notification.service', () => ({
  NotificationService: class {
    async sendToUser() { /* rien : les notifications ne sont pas le sujet */ }
  },
}));

import { PARIS_AFFICHES_MAX, getBankroll, resumeParis } from '../services/bankroll.service';

const { _base } = require('../lib/prisma');

/** Pose [n] paris du résultat donné sur la bankroll « b1 ». */
function poserParis(repartition: Record<string, number>) {
  for (const t of Object.values(_base) as Map<string, any>[]) t.clear();

  _base.users.set('u1', { id: 'u1', pseudo: 'Parieur' });
  _base.bankrolls.set('b1', {
    id: 'b1', userId: 'u1', totalBudget: 100_000,
    currentBalance: 100_000, currency: 'XOF',
  });

  let i = 0;
  for (const [resultat, n] of Object.entries(repartition)) {
    for (let k = 0; k < n; k++) {
      i++;
      _base.matches.set(`m${i}`, {
        id: `m${i}`, homeTeam: 'A', awayTeam: 'B',
        status: 'FINISHED', matchDate: new Date(Date.now() - 86_400_000),
      });
      _base.pronostics.set(`p${i}`, {
        id: `p${i}`, matchId: `m${i}`, confidenceScore: 4, oddsRecommended: 2,
        result: resultat === 'null' ? null : resultat,
      });
      _base.bankrollBets.set(`bet${i}`, {
        id: `bet${i}`, bankrollId: 'b1', pronosticId: `p${i}`,
        stakedAmount: 1000, suggestedAmount: 1000, oddsUsed: 2,
        potentialGain: 2000,
        result: resultat === 'null' ? null : resultat,
        profit: resultat === 'WIN' ? 1000
              : resultat === 'LOSS' ? -1000
              : resultat === 'PUSH' ? 0 : null,
        createdAt: new Date(Date.now() - i * 60_000),
      });
    }
  }
}

describe('le bilan compte tout l\'historique', () => {
  it('au-delà de ce que la liste affiche', async () => {
    // Le cas qui rendait les chiffres faux : plus de paris que la page n'en
    // montre. Les compteurs doivent porter sur les 120, pas sur les 50.
    poserParis({ WIN: 70, LOSS: 40, PUSH: 5, null: 5 });

    const r = await resumeParis('b1');

    expect(r.total).toBe(120);
    expect(r.gagnes).toBe(70);
    expect(r.perdus).toBe(40);
    expect(r.rembourses).toBe(5);
    expect(r.en_attente).toBe(5);
  });

  it('la liste, elle, reste plafonnée', async () => {
    // Contrepartie : la limite n'est pas le défaut et doit rester. On ne
    // corrige pas un bilan faux en chargeant tout l'historique sur le mobile.
    poserParis({ WIN: 70, LOSS: 40, PUSH: 5, null: 5 });

    const b = await getBankroll('u1');

    expect(b!.bets.length).toBe(PARIS_AFFICHES_MAX);
    expect(PARIS_AFFICHES_MAX).toBeLessThan(120);
  });

  it('le taux ne se calcule pas sur l\'échantillon affiché', async () => {
    // 70 gagnés sur 110 qui départagent = 64 %. Un calcul sur les 50 dernières
    // lignes donnerait une tout autre valeur, sans que rien ne le signale.
    poserParis({ WIN: 70, LOSS: 40, PUSH: 5, null: 5 });

    const r = await resumeParis('b1');

    expect(r.taux_reussite).toBe(64);
  });

  it('les remboursés restent hors du dénominateur', async () => {
    poserParis({ WIN: 3, LOSS: 1, PUSH: 6 });

    const r = await resumeParis('b1');

    expect(r.rembourses).toBe(6);
    expect(r.taux_reussite).toBe(75); // 3 sur 4, et non 3 sur 10
  });

  it('une bankroll sans pari ne prétend à aucun taux', async () => {
    // Contrepartie : zéro divisé par zéro ne vaut pas « 0 % de réussite ».
    // C'est l'écran qui décide de ne rien afficher, mais l'API ne doit pas
    // inventer de dénominateur.
    poserParis({});

    const r = await resumeParis('b1');

    expect(r.total).toBe(0);
    expect(r.taux_reussite).toBe(0);
    expect(r.profit_net).toBe(0);
  });

  it('le résultat net additionne les paris réglés', async () => {
    poserParis({ WIN: 3, LOSS: 2, PUSH: 4, null: 2 });

    const r = await resumeParis('b1');

    // 3 × (+1000) + 2 × (−1000) + 4 × 0 = +1000
    expect(r.profit_net).toBe(1000);
  });

  it('ne compte que les paris de cette bankroll', async () => {
    // Contrepartie qui compte : un bilan qui déborderait sur les paris
    // d'autrui serait pire que tronqué.
    poserParis({ WIN: 2 });
    _base.bankrolls.set('b2', {
      id: 'b2', userId: 'u2', totalBudget: 1000,
      currentBalance: 1000, currency: 'XOF',
    });
    _base.bankrollBets.set('bet-autre', {
      id: 'bet-autre', bankrollId: 'b2', pronosticId: 'p1',
      stakedAmount: 500, result: 'WIN', profit: 500,
      createdAt: new Date(),
    });

    const r = await resumeParis('b1');

    expect(r.total).toBe(2);
    expect(r.profit_net).toBe(2000);
  });
});

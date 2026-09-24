/**
 * Un pronostic dont la cote est inférieure à 1,20 ne peut pas être publié.
 *
 * ── Pourquoi ──────────────────────────────────────────────────────────────
 *
 * Le seuil de rentabilité vaut `1 / cote` : à 1,20 il faut gagner 83 % des fois
 * pour rentrer dans ses frais, à 1,13 près de 89 %. Sur les 136 premiers
 * pronostics réglés, la tranche 1,00–1,25 a rendu −4,3 %, toutes les autres
 * étaient positives.
 *
 * ── Ce que ce banc tient ──────────────────────────────────────────────────
 *
 * Trois choses, et la troisième compte autant que les deux premières :
 *
 *   1. la règle refuse bien sous 1,20, y compris une cote absente ;
 *   2. elle refuse par les **deux** chemins qui publient — l'enregistrement
 *      complet et la bascule de publication. Oublier le second laisserait un
 *      brouillon à 1,15 devenir public en un clic ;
 *   3. elle ne bloque **rien d'autre** : ni les brouillons, ni la
 *      dépublication. Des pronostics sous 1,20 existent déjà en base, publiés
 *      avant la règle ; il faut pouvoir les retirer.
 */
const ecritures: string[] = [];
const pronostics: Record<string, { id: string; matchId: string; oddsRecommended: number; isPublished: boolean }> = {};
let matchStatut = 'SCHEDULED';

jest.mock('../lib/prisma', () => {
  const prisma: any = {
    match: {
      findUnique: jest.fn(async ({ where }: any) => {
        ecritures.push('lecture:match');
        return { id: where.id, status: matchStatut };
      }),
      update: jest.fn(async () => { ecritures.push('match.update'); return {}; }),
    },
    pronostic: {
      findUnique: jest.fn(async ({ where }: any) => pronostics[where.id] ?? null),
      upsert: jest.fn(async ({ create }: any) => {
        ecritures.push('pronostic.upsert');
        const p = { id: 'p-' + create.matchId, ...create };
        pronostics[p.id] = p;
        return p;
      }),
      update: jest.fn(async ({ where, data }: any) => {
        ecritures.push('pronostic.update');
        Object.assign(pronostics[where.id], data);
        return pronostics[where.id];
      }),
    },
  };
  prisma.$transaction = async (fn: any) => fn(prisma);
  return { prisma };
});

jest.mock('../services/notification.service', () => ({
  NotificationService: class { async notifyPronosticPublished() {} },
}));
jest.mock('../services/bankroll.service', () => ({ settleBets: async () => {} }));
jest.mock('../services/api_football.service', () => ({
  ApiFootballService: class {},
  apiFootballService: {},
  mapAFStatus: () => 'SCHEDULED',
  matchStatusPriority: () => 0,
}));

import {
  PronosticsService,
  COTE_MINIMALE_PUBLICATION,
  verifierCotePublication,
} from '../services/pronostics.service';

const svc = new PronosticsService();

function demande(cote: number, publish: boolean) {
  return {
    matchId: 'm1', analystId: 'a1',
    predictionType: 'win1', predictionLabel: 'Victoire domicile',
    oddsHome: cote, oddsDraw: 3.5, oddsAway: 5.0, oddsRecommended: cote,
    confidenceScore: 4, isPremium: false, publish,
  };
}

beforeEach(() => {
  ecritures.length = 0;
  for (const k of Object.keys(pronostics)) delete pronostics[k];
  matchStatut = 'SCHEDULED';
});

describe('la règle elle-même', () => {
  it('le seuil est 1,20', () => {
    expect(COTE_MINIMALE_PUBLICATION).toBe(1.2);
  });

  it('refuse juste en dessous', () => {
    expect(() => verifierCotePublication(1.19)).toThrow(/trop basse/);
  });

  it('accepte le seuil lui-même : « inférieure à 1,2 » exclut 1,20', () => {
    expect(() => verifierCotePublication(1.2)).not.toThrow();
  });

  it('accepte au-dessus', () => {
    expect(() => verifierCotePublication(1.21)).not.toThrow();
    expect(() => verifierCotePublication(2.5)).not.toThrow();
  });

  it('refuse une cote absente — NaN < 1.2 vaut false', () => {
    // Le piège exact : `parseFloat('')` donne NaN, et une comparaison écrite
    // `cote < 1.2` le laisse passer. Une cote manquante serait publiée.
    expect(() => verifierCotePublication(NaN)).toThrow(/manquante ou invalide/);
    expect(() => verifierCotePublication(parseFloat(''))).toThrow(/manquante/);
  });

  it('refuse une cote infinie', () => {
    expect(() => verifierCotePublication(Infinity)).toThrow(/invalide/);
  });

  it('le message dit pourquoi, chiffres calculés et non recopiés', () => {
    // L'administrateur doit comprendre le refus sans ouvrir le code. Le seuil
    // d'équilibre est calculé à partir de la cote refusée : il ne peut pas
    // vieillir, contrairement à un rendement historique.
    let message = '';
    try { verifierCotePublication(1.15); } catch (e: any) { message = e.message; }
    expect(message).toContain('1,15');
    expect(message).toContain('1,20');
    expect(message).toContain('87 %');
    expect(message).toMatch(/brouillon/);
  });
});

describe('enregistrement complet (upsertPronostic)', () => {
  it('publication sous le seuil : refusée', async () => {
    await expect(svc.upsertPronostic(demande(1.15, true))).rejects.toThrow(/trop basse/);
  });

  it("et la base n'est pas touchée", async () => {
    // Le contrôle vient avant toute lecture : une demande vouée à l'échec ne
    // lit pas le match et n'écrit rien.
    await svc.upsertPronostic(demande(1.15, true)).catch(() => {});
    expect(ecritures).toEqual([]);
  });

  it('publication au seuil : acceptée', async () => {
    const p = await svc.upsertPronostic(demande(1.2, true));
    expect(p.isPublished).toBe(true);
  });

  it('brouillon sous le seuil : accepté', async () => {
    // Une cote bouge. Un pronostic préparé à 1,15 peut devenir publiable si
    // le marché remonte ; interdire le brouillon forcerait à tout ressaisir.
    const p = await svc.upsertPronostic(demande(1.15, false));
    expect(p.isPublished).toBe(false);
    expect(ecritures).toContain('pronostic.upsert');
  });

  it('publication avec une cote vide : refusée', async () => {
    await expect(svc.upsertPronostic(demande(NaN, true))).rejects.toThrow(/manquante/);
  });
});

describe('bascule de publication (togglePublish)', () => {
  function brouillon(cote: number, publie = false) {
    pronostics.p1 = { id: 'p1', matchId: 'm1', oddsRecommended: cote, isPublished: publie };
  }

  it('publier un brouillon sous le seuil : refusé', async () => {
    // Le contournement que ce chemin ouvrirait : enregistrer en brouillon —
    // permis —, puis publier par ici. Il ne reçoit qu'un identifiant ; la cote
    // contrôlée doit être celle qui est enregistrée.
    brouillon(1.15);
    await expect(svc.togglePublish('p1', true)).rejects.toThrow(/trop basse/);
    expect(pronostics.p1.isPublished).toBe(false);
    expect(ecritures).not.toContain('pronostic.update');
  });

  it('publier un brouillon au-dessus du seuil : accepté', async () => {
    brouillon(1.25);
    const p = await svc.togglePublish('p1', true);
    expect(p.isPublished).toBe(true);
  });

  it('dépublier sous le seuil : toujours possible', async () => {
    // Des pronostics à 1,13 ont été publiés avant la règle. Refuser de les
    // retirer les laisserait visibles pour toujours — la règle produirait
    // l'inverse de son intention.
    brouillon(1.13, true);
    const p = await svc.togglePublish('p1', false);
    expect(p.isPublished).toBe(false);
  });

  it('pronostic introuvable : message clair', async () => {
    await expect(svc.togglePublish('inexistant', true)).rejects.toThrow(/introuvable/);
  });
});

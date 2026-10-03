/**
 * Un export CSV rend ce que l'écran montre, et un tableur le lit comme du
 * texte.
 *
 * Constat A16 de l'audit du 24 septembre 2026 :
 *
 *  - l'export des utilisateurs ne recevait que le filtre de plan : recherche,
 *    statut et dates étaient ignorés, et « Exporter les résultats filtrés »
 *    sortait toute la base ;
 *  - chaque valeur était entourée de guillemets sans doubler ceux qu'elle
 *    contenait, et une valeur commençant par `=` restait une formule. Le
 *    pseudo est choisi par l'utilisateur.
 */
const appels: Array<{ modele: string; where: any }> = [];

jest.mock('../lib/prisma', () => {
  const noter = (modele: string) => async ({ where }: any = {}) => {
    appels.push({ modele, where });
    return modele === 'user.count' || modele === 'transaction.count' ? 0 : [];
  };
  return {
    prisma: {
      user: { findMany: jest.fn(noter('user.findMany')), count: jest.fn(noter('user.count')) },
      transaction: {
        findMany: jest.fn(noter('transaction.findMany')),
        count:    jest.fn(noter('transaction.count')),
        groupBy:  jest.fn(async () => []),
      },
    },
  };
});

import { celluleCsv, ligneCsv } from '../utils/csv';
import { lirePagination } from '../utils/pagination';
import { UsersAdminService } from '../services/users_admin.service';
import { PaymentHistoryService } from '../services/payment_history.service';

describe('cellule CSV', () => {
  it('double les guillemets d\'une valeur', () => {
    expect(celluleCsv('Le "boss"')).toBe('"Le ""boss"""');
  });

  it.each(['=HYPERLINK("http://x";"Voir")', '+226 70 00 00 00', '-2+3', '@SUM(A1)'])(
    'neutralise une valeur interprétable comme formule : %s', (v) => {
      const cellule = celluleCsv(v);
      // Entre guillemets, la valeur commence par une apostrophe.
      expect(cellule.startsWith('"\'')).toBe(true);
    });

  it('laisse les nombres intacts, négatifs compris', () => {
    expect(celluleCsv(-1500)).toBe('-1500');
    expect(celluleCsv(0)).toBe('0');
  });

  it('aplatit les retours à la ligne et rend une cellule vide pour null', () => {
    expect(celluleCsv('a\r\nb\nc')).toBe('"a b c"');
    expect(celluleCsv(null)).toBe('""');
    expect(celluleCsv(undefined)).toBe('""');
  });

  it('assemble une ligne sans décaler les colonnes', () => {
    const ligne = ligneCsv(['x', 'Le "boss", encore', 3]);
    expect(ligne).toBe('"x","Le ""boss"", encore",3');
  });
});

describe('export des utilisateurs : les filtres de l\'écran', () => {
  const svc = new UsersAdminService();
  const filtres = {
    search: 'kone', plan: 'premium', status: 'suspended',
    dateFrom: '2026-09-01', dateTo: '2026-09-15',
  };

  it('le filtre de l\'export est celui de la liste', async () => {
    appels.length = 0;
    await svc.getUsers({ ...filtres, page: 1, perPage: 20 });
    const liste = appels.find((a) => a.modele === 'user.findMany')!.where;

    appels.length = 0;
    for await (const _ of svc.exportCsvRows(filtres)) { /* aucune ligne */ }
    const exporte = appels.find((a) => a.modele === 'user.findMany')!.where;

    expect(exporte).toEqual(liste);
    // Et ce filtre porte bien la recherche et le statut, pas seulement le plan.
    expect(exporte.OR).toBeDefined();
    expect(exporte.isActive).toBe(false);
    expect(exporte.createdAt).toBeDefined();
  });
});

describe('export de l\'historique : les filtres de l\'écran', () => {
  const svc = new PaymentHistoryService();

  it('recherche, méthode et montants passent dans l\'export', async () => {
    const filtres = {
      search: '7012', status: 'completed', method: 'orange_money',
      amountMin: 1000, amountMax: 5000,
    };
    appels.length = 0;
    await svc.getHistory({ ...filtres, page: 1, perPage: 20 });
    const liste = appels.find((a) => a.modele === 'transaction.findMany')!.where;

    appels.length = 0;
    await svc.exportCsv(filtres);
    const exporte = appels.find((a) => a.modele === 'transaction.findMany')!.where;

    expect(exporte).toEqual(liste);
    expect(exporte.paymentMethod).toBe('orange_money');
    expect(exporte.amount).toEqual({ gte: 1000, lte: 5000 });
  });
});

describe('pagination bornée', () => {
  it.each([
    [{}, { page: 1, perPage: 20 }],
    [{ page: '3', per_page: '50' }, { page: 3, perPage: 50 }],
    [{ page: '0', per_page: '5000000' }, { page: 1, perPage: 100 }],
    [{ page: '-4', per_page: '-1' }, { page: 1, perPage: 1 }],
    [{ page: 'abc', per_page: 'xyz' }, { page: 1, perPage: 20 }],
  ])('%j → %j', (query, attendu) => {
    expect(lirePagination(query)).toEqual(attendu);
  });
});

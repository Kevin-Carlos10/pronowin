/**
 * Rythme adaptatif de la synchronisation des scores (18 octobre 2026) :
 * 15 s pour un match suivi en direct, 60 s pour le reste du direct, 2 min
 * sans direct.
 */
import { prisma } from '../lib/prisma';
import { delaiSynchronisation } from '../taches';

afterEach(() => jest.restoreAllMocks());

function base(suivis: number, enDirect: number) {
  return jest.spyOn(prisma.match, 'count').mockImplementation((async (args: any) =>
    args?.where?.OR ? suivis : enDirect) as any);
}

it('un match suivi en direct (pronostic publié ou favori) : 15 s', async () => {
  const count = base(1, 30);
  expect(await delaiSynchronisation()).toBe(15_000);
  expect(count.mock.calls[0][0]).toEqual({ where: {
    status: 'LIVE', OR: [{ hasPublishedPronostic: true }, { favoritedBy: { some: {} } }] } });
});

it('du direct que personne ne suit : 60 s', async () => {
  base(0, 30);
  expect(await delaiSynchronisation()).toBe(60_000);
});

it('aucun direct : 2 min', async () => {
  base(0, 0);
  expect(await delaiSynchronisation()).toBe(120_000);
});

it('base injoignable : 60 s, sans emballer le quota', async () => {
  jest.spyOn(prisma.match, 'count').mockRejectedValue(new Error('base'));
  expect(await delaiSynchronisation()).toBe(60_000);
});

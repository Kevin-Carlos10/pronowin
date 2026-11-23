/**
 * Plusieurs pronostics par match (23 novembre 2026) : un principal par
 * match, les autres s'y ajoutent ; un pronostic se retire avant le coup
 * d'envoi, jamais après.
 */
import { prisma } from '../lib/prisma';
import { PronosticsService } from '../services/pronostics.service';
import { NotificationService } from '../services/notification.service';
import { exigenceDe } from '../utils/permissions_admin';

const svc = new PronosticsService();
const demain = new Date(Date.now() + 86_400_000);

afterEach(() => jest.restoreAllMocks());

function transactionSurPrisma() {
  jest.spyOn(prisma, '$transaction').mockImplementation((async (fn: any) => fn(prisma)) as any);
  jest.spyOn(prisma, '$queryRaw').mockResolvedValue([] as any);
  jest.spyOn(prisma.match, 'update').mockResolvedValue({} as any);
  jest.spyOn(prisma.pronostic, 'count').mockResolvedValue(1);
}

const demande = (extra: Record<string, unknown> = {}) => ({
  matchId: 'm1', analystId: 'a1', predictionType: 'over_2_5', predictionLabel: 'Plus de 2,5 buts',
  oddsHome: 0, oddsDraw: 0, oddsAway: 0, oddsRecommended: 1.8, confidenceScore: 3,
  isPremium: true, publish: false, ...extra,
});

describe('ajouter un pronostic à un match', () => {
  beforeEach(() => {
    transactionSurPrisma();
    jest.spyOn(prisma.match, 'findUnique').mockResolvedValue({ id: 'm1', status: 'SCHEDULED', matchDate: demain } as any);
    jest.spyOn(prisma.pronostic, 'create').mockImplementation((async ({ data }: any) => ({ id: 'nouveau', ...data })) as any);
  });

  it('un match qui a déjà son principal : le nouveau s\'y ajoute, sans le remplacer', async () => {
    jest.spyOn(prisma.pronostic, 'findUnique').mockResolvedValue({ id: 'p1', matchId: 'm1' } as any);
    await svc.upsertPronostic({ ...demande(), nouveau: true });
    expect((prisma.pronostic.create as jest.Mock).mock.calls[0][0].data.principalMatchId).toBeNull();
  });

  it('le premier pronostic d\'un match en devient le principal', async () => {
    jest.spyOn(prisma.pronostic, 'findUnique').mockResolvedValue(null);
    await svc.upsertPronostic({ ...demande(), nouveau: true });
    expect((prisma.pronostic.create as jest.Mock).mock.calls[0][0].data.principalMatchId).toBe('m1');
  });

  it('modifier un pronostic désigné ; celui d\'un autre match est refusé', async () => {
    jest.spyOn(prisma.pronostic, 'findUnique').mockResolvedValue(
      { id: 'p2', matchId: 'm1', publicationRecordedAt: null } as any);
    const maj = jest.spyOn(prisma.pronostic, 'update').mockResolvedValue({ id: 'p2', match: {} } as any);
    await svc.upsertPronostic({ ...demande(), pronosticId: 'p2' });
    expect(maj.mock.calls[0][0].where).toEqual({ id: 'p2' });

    (prisma.pronostic.findUnique as jest.Mock).mockResolvedValue({ id: 'p9', matchId: 'autre' });
    await expect(svc.upsertPronostic({ ...demande(), pronosticId: 'p9' })).rejects.toMatchObject({ statut: 409 });
  });
});

describe('retirer un pronostic', () => {
  let supprime: jest.SpyInstance, promu: jest.SpyInstance;
  beforeEach(() => {
    transactionSurPrisma();
    jest.spyOn(prisma.bankrollBet, 'findMany').mockResolvedValue([]);
    supprime = jest.spyOn(prisma.pronostic, 'delete').mockResolvedValue({} as any);
    jest.spyOn(prisma.pronostic, 'findFirst').mockResolvedValue({ id: 'p2' } as any);
    promu = jest.spyOn(prisma.pronostic, 'update').mockResolvedValue({} as any);
    jest.spyOn(NotificationService.prototype, 'sendToUser').mockResolvedValue({ success: true } as any);
  });

  const prono = (statut: string, publie = true, principal = true) => ({
    id: 'p1', matchId: 'm1', principalMatchId: principal ? 'm1' : null, result: null,
    publicationRecordedAt: publie ? new Date() : null,
    match: { id: 'm1', status: statut, matchDate: statut === 'SCHEDULED' ? demain : new Date(), homeTeam: 'A', awayTeam: 'B' },
  });

  it('avant le coup d\'envoi : retiré, et le suivant devient le principal', async () => {
    jest.spyOn(prisma.pronostic, 'findUnique').mockResolvedValue(prono('SCHEDULED') as any);
    expect(await svc.supprimerPronostic('p1', 'admin')).toEqual({ supprime: 'p1', mises_rendues: 0 });
    expect(supprime).toHaveBeenCalledWith({ where: { id: 'p1' } });
    expect(promu).toHaveBeenCalledWith({ where: { id: 'p2' }, data: { principalMatchId: 'm1' } });
  });

  it('match commencé ou joué : refusé, rien n\'est retiré — le bilan reste entier', async () => {
    for (const statut of ['LIVE', 'FINISHED']) {
      (jest.spyOn(prisma.pronostic, 'findUnique') as jest.SpyInstance).mockResolvedValue(prono(statut) as any);
      await expect(svc.supprimerPronostic('p1', 'admin')).rejects.toMatchObject({ statut: 409 });
    }
    expect(supprime).not.toHaveBeenCalled();
  });

  it('un brouillon jamais publié se retire quand on veut', async () => {
    jest.spyOn(prisma.pronostic, 'findUnique').mockResolvedValue(prono('FINISHED', false, false) as any);
    await svc.supprimerPronostic('p1', 'admin');
    expect(supprime).toHaveBeenCalled();
    expect(promu).not.toHaveBeenCalled();
  });

  it('réservé à l\'administrateur principal', () => {
    expect(exigenceDe('DELETE', '/pronostics/admin/pronostic/p1')).toEqual({ acces: 'principal' });
  });
});

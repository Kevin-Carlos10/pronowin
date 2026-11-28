/**
 * Les chiffres du mur Premium et de la vitrine (24 novembre 2026) : des
 * comptes, pas un taux — et un compte trop petit ne s'annonce pas.
 */
import { prisma } from '../lib/prisma';
import {
  calculerChiffresVip, chiffresAnnoncables, SEUIL_COMPETITIONS, SEUIL_VIP_PUBLIES,
} from '../services/chiffres_vip';

afterEach(() => jest.restoreAllMocks());

describe('les seuils d\'annonce', () => {
  it('au seuil, annoncés ; dessous, nuls', () => {
    expect(chiffresAnnoncables({ vipPublies: SEUIL_VIP_PUBLIES, competitions: SEUIL_COMPETITIONS, vipAujourdhui: 1 }))
      .toEqual({ periode_jours: 30, vip_publies: 10, competitions: 3, vip_aujourdhui: 1 });
    expect(chiffresAnnoncables({ vipPublies: 9, competitions: 2, vipAujourdhui: 0 }))
      .toEqual({ periode_jours: 30, vip_publies: null, competitions: null, vip_aujourdhui: null });
  });

  it('aucun taux, ni gagnés ni perdus, dans la réponse', () => {
    const r = chiffresAnnoncables({ vipPublies: 40, competitions: 8, vipAujourdhui: 3 });
    expect(Object.keys(r).sort()).toEqual(['competitions', 'periode_jours', 'vip_aujourdhui', 'vip_publies']);
  });
});

describe('le calcul', () => {
  it('VIP publiés sur trente jours (retirés exclus), ligues distinctes, VIP du jour UTC', async () => {
    const comptes = jest.spyOn(prisma.pronostic, 'count')
      .mockResolvedValueOnce(42)   // VIP publiés
      .mockResolvedValueOnce(3);   // VIP du jour
    const lignes = jest.spyOn(prisma.pronostic, 'findMany').mockResolvedValue([
      { match: { league: 'Premier League' } }, { match: { league: 'Ligue 1' } },
      { match: { league: 'Premier League' } }, { match: { league: 'Serie A' } },
      { match: { league: 'LaLiga' } },
    ] as any);

    const maintenant = new Date(Date.UTC(2026, 10, 24, 15, 30));
    const r = await calculerChiffresVip(maintenant);
    expect(r).toEqual({ periode_jours: 30, vip_publies: 42, competitions: 4, vip_aujourdhui: 3 });

    const depuis = new Date(Date.UTC(2026, 9, 25, 15, 30));
    expect((comptes.mock.calls[0][0] as any).where)
      .toEqual({ isPublished: true, publicationRecordedAt: { gte: depuis }, isPremium: true });
    expect((lignes.mock.calls[0][0] as any).where).toEqual({ isPublished: true, publicationRecordedAt: { gte: depuis } });
    expect((comptes.mock.calls[1][0] as any).where.match.matchDate)
      .toEqual({ gte: new Date(Date.UTC(2026, 10, 24)), lt: new Date(Date.UTC(2026, 10, 25)) });
  });
});

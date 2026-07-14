// Mock Prisma et SMS avant tout import du service
jest.mock('@prisma/client', () => {
  const mockOtpUpdateMany = jest.fn().mockResolvedValue({});
  const mockOtpCreate     = jest.fn().mockResolvedValue({ id: 'otp-1' });
  const mockOtpFindFirst  = jest.fn();
  const mockOtpUpdate     = jest.fn().mockResolvedValue({});
  const mockUserFindUnique = jest.fn();
  const mockUserCreate     = jest.fn();
  const mockUserUpdate     = jest.fn().mockResolvedValue({});
  const mockRefreshCreate  = jest.fn().mockResolvedValue({});
  const mockRefreshFindUnique = jest.fn();
  const mockRefreshUpdate  = jest.fn().mockResolvedValue({});
  const mockRefreshDelete  = jest.fn().mockResolvedValue({});
  const mockRefreshDeleteMany = jest.fn().mockResolvedValue({});

  const PrismaClient = jest.fn().mockImplementation(() => ({
    otpCode:      { updateMany: mockOtpUpdateMany, create: mockOtpCreate, findFirst: mockOtpFindFirst, update: mockOtpUpdate },
    user:         { findUnique: mockUserFindUnique, create: mockUserCreate, update: mockUserUpdate },
    refreshToken: { create: mockRefreshCreate, findUnique: mockRefreshFindUnique, update: mockRefreshUpdate, delete: mockRefreshDelete, deleteMany: mockRefreshDeleteMany },
  }));

  return { PrismaClient, _mocks: { mockOtpFindFirst, mockUserFindUnique, mockUserCreate, mockRefreshFindUnique } };
});

jest.mock('../services/sms.service', () => ({
  sendSmsOtp: jest.fn().mockResolvedValue(undefined),
}));

import { AuthService } from '../services/auth.service';
import { PrismaClient } from '@prisma/client';

// Récupérer les mocks après import
const prismaInstance   = new (PrismaClient as jest.MockedClass<typeof PrismaClient>)();
const { _mocks }       = require('@prisma/client');

// Variables d'env minimales pour JWT
process.env.JWT_SECRET         = 'test-secret-access';
process.env.JWT_REFRESH_SECRET = 'test-secret-refresh';
process.env.JWT_EXPIRES_IN     = '15m';
process.env.JWT_REFRESH_EXPIRES_IN = '30d';

describe('AuthService', () => {
  let service: AuthService;

  beforeEach(() => {
    service = new AuthService();
    jest.clearAllMocks();
  });

  // ─── verifyOtp ────────────────────────────────────────────────────────────

  describe('verifyOtp', () => {
    it('lève une erreur si l\'OTP est introuvable', async () => {
      _mocks.mockOtpFindFirst.mockResolvedValueOnce(null);

      await expect(service.verifyOtp('+22670000000', '999999'))
        .rejects.toThrow('Code OTP invalide ou expiré.');
    });

    it('crée un nouvel utilisateur si le numéro est inconnu', async () => {
      _mocks.mockOtpFindFirst.mockResolvedValueOnce({ id: 'otp-1', phoneNumber: '+22670000000', code: '123456', used: false, expiresAt: new Date(Date.now() + 60000) });
      _mocks.mockUserFindUnique.mockResolvedValueOnce(null); // pas d'utilisateur existant
      _mocks.mockUserCreate.mockResolvedValueOnce({ id: 'user-1', phoneNumber: '+22670000000', pseudo: 'Parieur_TEST', referralCode: 'ABCDEF', countryCode: 'BF' });

      const result = await service.verifyOtp('+22670000000', '123456');

      expect(_mocks.mockUserCreate).toHaveBeenCalledTimes(1);
      expect(result).toHaveProperty('access_token');
      expect(result).toHaveProperty('refresh_token');
    });

    it('connecte un utilisateur existant sans le recréer', async () => {
      const existingUser = { id: 'user-existing', phoneNumber: '+22670000000', pseudo: 'Parieur_A', referralCode: 'XYZ123' };
      _mocks.mockOtpFindFirst.mockResolvedValueOnce({ id: 'otp-1', used: false, expiresAt: new Date(Date.now() + 60000) });
      _mocks.mockUserFindUnique.mockResolvedValueOnce(existingUser);

      const result = await service.verifyOtp('+22670000000', '123456');

      expect(_mocks.mockUserCreate).not.toHaveBeenCalled();
      expect(result.user).toMatchObject({ id: 'user-existing' });
    });

    it('détecte le code pays Burkina Faso (+226)', async () => {
      _mocks.mockOtpFindFirst.mockResolvedValueOnce({ id: 'otp-1', used: false, expiresAt: new Date(Date.now() + 60000) });
      _mocks.mockUserFindUnique.mockResolvedValueOnce(null);
      _mocks.mockUserCreate.mockImplementationOnce(({ data }: any) => Promise.resolve({ id: 'u1', ...data }));

      await service.verifyOtp('+22670000000', '123456');

      const createCall = _mocks.mockUserCreate.mock.calls[0][0];
      expect(createCall.data.countryCode).toBe('BF');
    });

    it('détecte le code pays Côte d\'Ivoire (+225)', async () => {
      _mocks.mockOtpFindFirst.mockResolvedValueOnce({ id: 'otp-2', used: false, expiresAt: new Date(Date.now() + 60000) });
      _mocks.mockUserFindUnique.mockResolvedValueOnce(null);
      _mocks.mockUserCreate.mockImplementationOnce(({ data }: any) => Promise.resolve({ id: 'u2', ...data }));

      await service.verifyOtp('+22507000000', '123456');

      const createCall = _mocks.mockUserCreate.mock.calls[0][0];
      expect(createCall.data.countryCode).toBe('CI');
    });
  });

  // ─── refreshToken ─────────────────────────────────────────────────────────

  describe('refreshToken', () => {
    it('lève une erreur si le token est introuvable', async () => {
      _mocks.mockRefreshFindUnique.mockResolvedValueOnce(null);

      await expect(service.refreshToken('invalid-token'))
        .rejects.toThrow('Token de rafraîchissement invalide.');
    });

    it('lève une erreur et révoque toutes les sessions si le token est déjà utilisé', async () => {
      _mocks.mockRefreshFindUnique.mockResolvedValueOnce({ id: 'rt-1', userId: 'user-1', used: true, expiresAt: new Date(Date.now() + 60000), token: 'old-token' });

      const prisma = (service as any); // accès pour vérifier deleteMany
      await expect(service.refreshToken('old-token'))
        .rejects.toThrow('Session compromise détectée.');
    });

    it('lève une erreur si le token est expiré', async () => {
      _mocks.mockRefreshFindUnique.mockResolvedValueOnce({ id: 'rt-2', userId: 'user-1', used: false, expiresAt: new Date(Date.now() - 1000), token: 'expired-token' });

      await expect(service.refreshToken('expired-token'))
        .rejects.toThrow('Session expirée.');
    });

    it('retourne de nouveaux tokens si le refresh token est valide', async () => {
      _mocks.mockRefreshFindUnique.mockResolvedValueOnce({ id: 'rt-3', userId: 'user-1', used: false, expiresAt: new Date(Date.now() + 86400000), token: 'valid-token' });

      const result = await service.refreshToken('valid-token');

      expect(result).toHaveProperty('access_token');
      expect(result).toHaveProperty('refresh_token');
      expect(typeof result.access_token).toBe('string');
    });
  });
});

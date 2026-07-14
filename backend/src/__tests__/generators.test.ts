import { generateOtp, generateReferralCode } from '../utils/generators';

describe('generateOtp', () => {
  it('produit une chaîne de 6 chiffres', () => {
    const otp = generateOtp();
    expect(otp).toMatch(/^\d{6}$/);
  });

  it('reste dans la plage 100000–999999', () => {
    for (let i = 0; i < 100; i++) {
      const n = parseInt(generateOtp(), 10);
      expect(n).toBeGreaterThanOrEqual(100000);
      expect(n).toBeLessThanOrEqual(999999);
    }
  });

  it('génère des valeurs différentes (pas constante)', () => {
    const set = new Set(Array.from({ length: 20 }, generateOtp));
    expect(set.size).toBeGreaterThan(1);
  });
});

describe('generateReferralCode', () => {
  it('produit 6 caractères hexadécimaux majuscules', () => {
    const code = generateReferralCode();
    expect(code).toMatch(/^[0-9A-F]{6}$/);
  });

  it('génère des codes uniques', () => {
    const codes = new Set(Array.from({ length: 50 }, generateReferralCode));
    expect(codes.size).toBeGreaterThan(1);
  });
});

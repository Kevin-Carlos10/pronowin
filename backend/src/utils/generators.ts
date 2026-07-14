import crypto from 'crypto';

/** Génère un OTP numérique à 6 chiffres */
export function generateOtp(): string {
  return Math.floor(100000 + Math.random() * 900000).toString();
}

/** Génère un code de parrainage unique à 6 caractères */
export function generateReferralCode(): string {
  return crypto.randomBytes(3).toString('hex').toUpperCase();
}

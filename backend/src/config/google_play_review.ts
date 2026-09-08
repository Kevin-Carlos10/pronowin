import { timingSafeEqual } from 'crypto';

/**
 * Google Play review access.
 *
 * The review account is configured only through the production environment.
 * It lets reviewers complete the OTP flow without sharing an inbox or using
 * an administrator account. Without complete configuration, it does not
 * exist and normal OTP authentication remains unchanged.
 */
export interface GooglePlayReviewConfig {
  email: string;
  otp: string;
}

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const OTP_RE = /^\d{6}$/;

export function normaliseEmail(email: string): string {
  return email.trim().toLowerCase();
}

export function getGooglePlayReviewConfig(): GooglePlayReviewConfig | null {
  if (process.env.GOOGLE_PLAY_REVIEW_ENABLED !== 'true') return null;

  const email = normaliseEmail(process.env.GOOGLE_PLAY_REVIEW_EMAIL ?? '');
  const otp = (process.env.GOOGLE_PLAY_REVIEW_OTP ?? '').trim();

  // Incomplete configuration fails closed. A malformed variable can never
  // turn the review account into an authentication bypass.
  if (!EMAIL_RE.test(email) || !OTP_RE.test(otp)) return null;

  return { email, otp };
}

export function compareReviewOtp(candidate: string, expected: string): boolean {
  const actual = Buffer.from(candidate, 'utf8');
  const reference = Buffer.from(expected, 'utf8');

  return actual.length === reference.length && timingSafeEqual(actual, reference);
}

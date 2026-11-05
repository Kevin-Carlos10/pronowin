import { timingSafeEqual } from 'crypto';

/**
 * Store review access (App Store Connect and Google Play).
 *
 * The review account is configured only through the production environment.
 * It lets reviewers complete the OTP flow without sharing an inbox or using
 * an administrator account. Without complete configuration, it does not
 * exist and normal OTP authentication remains unchanged.
 */
export interface StoreReviewConfig {
  email: string;
  otp: string;
}

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const OTP_RE = /^\d{6}$/;

export function normaliseEmail(email: string): string {
  return email.trim().toLowerCase();
}

export function getStoreReviewConfig(): StoreReviewConfig | null {
  // STORE_REVIEW_* is platform-neutral. The Google variables are kept as a
  // backward-compatible fallback for the already configured Play review.
  const enabled = process.env.STORE_REVIEW_ENABLED ?? process.env.GOOGLE_PLAY_REVIEW_ENABLED;
  if (enabled !== 'true') return null;

  const email = normaliseEmail(
    process.env.STORE_REVIEW_EMAIL ?? process.env.GOOGLE_PLAY_REVIEW_EMAIL ?? '',
  );
  const otp = (
    process.env.STORE_REVIEW_OTP ?? process.env.GOOGLE_PLAY_REVIEW_OTP ?? ''
  ).trim();

  // Incomplete configuration fails closed. A malformed variable can never
  // turn the review account into an authentication bypass.
  if (!EMAIL_RE.test(email) || !OTP_RE.test(otp)) return null;

  return { email, otp };
}

/** @deprecated Use getStoreReviewConfig for new App Store and Play setups. */
export const getGooglePlayReviewConfig = getStoreReviewConfig;

export function compareReviewOtp(candidate: string, expected: string): boolean {
  const actual = Buffer.from(candidate, 'utf8');
  const reference = Buffer.from(expected, 'utf8');

  return actual.length === reference.length && timingSafeEqual(actual, reference);
}

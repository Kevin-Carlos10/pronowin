/**
 * Creates or resets the non-personal account used for Google Play review.
 * Credentials stay in .env; this script never prints them. It creates no
 * payment, administrator, withdrawal right, or personal data.
 */
import 'dotenv/config';
import { PrismaClient } from '@prisma/client';
import { getGooglePlayReviewConfig } from '../src/config/google_play_review';
import { generateReferralCode } from '../src/utils/generators';

const prisma = new PrismaClient();

async function main() {
  const review = getGooglePlayReviewConfig();
  if (!review) {
    throw new Error(
      'Review configuration is absent or invalid. Set GOOGLE_PLAY_REVIEW_ENABLED=true, ' +
      'GOOGLE_PLAY_REVIEW_EMAIL, and a six-digit GOOGLE_PLAY_REVIEW_OTP.',
    );
  }

  // A long period prevents the Play review from failing due to expiry. This
  // account has no payment history and its access can be removed after review.
  const expiresAt = new Date();
  expiresAt.setFullYear(expiresAt.getFullYear() + 2);
  const now = new Date();

  const user = await prisma.user.upsert({
    where: { email: review.email },
    update: {
      pseudo:                'Google Play Review',
      emailVerified:         true,
      acceptedTermsAt:       now,
      isActive:              true,
      deletedAt:             null,
      subscriptionPlan:      'premium',
      subscriptionExpiresAt: expiresAt,
    },
    create: {
      email:                 review.email,
      pseudo:                'Google Play Review',
      referralCode:          generateReferralCode(),
      emailVerified:         true,
      acceptedTermsAt:       now,
      isActive:              true,
      subscriptionPlan:      'premium',
      subscriptionExpiresAt: expiresAt,
    },
    select: {
      id: true,
      email: true,
      pseudo: true,
      subscriptionPlan: true,
      subscriptionExpiresAt: true,
    },
  });

  console.log(`Review account ready: ${user.email} (${user.subscriptionPlan}).`);
}

main()
  .catch((error) => {
    console.error(error instanceof Error ? error.message : error);
    process.exitCode = 1;
  })
  .finally(() => prisma.$disconnect());

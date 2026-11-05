/**
 * Creates or resets the non-personal account used for App Store and Play review.
 * Credentials stay in .env; this script never prints them. It creates no
 * payment, administrator, withdrawal right, or personal data.
 */
import 'dotenv/config';
import { PrismaClient } from '@prisma/client';
import { getStoreReviewConfig } from '../src/config/google_play_review';
import { generateReferralCode } from '../src/utils/generators';

const prisma = new PrismaClient();

async function main() {
  const review = getStoreReviewConfig();
  if (!review) {
    throw new Error(
      'Review configuration is absent or invalid. Set STORE_REVIEW_ENABLED=true, ' +
      'STORE_REVIEW_EMAIL, and a six-digit STORE_REVIEW_OTP.',
    );
  }

  // A long period prevents the Play review from failing due to expiry. This
  // account has no payment history and its access can be removed after review.
  const expiresAt = new Date();
  expiresAt.setFullYear(expiresAt.getFullYear() + 2);
  // `--gratuit` : compte sans Premium, pour l'examen Apple. Le relecteur du
  // 2 novembre 2026 a touché « Get Premium » : il teste l'achat intégré avec
  // son compte sandbox, ce qu'un compte déjà Premium l'empêcherait de faire.
  const gratuit = process.argv.includes('--gratuit');
  const formule = gratuit
    ? { subscriptionPlan: 'free' as const, subscriptionExpiresAt: null }
    : { subscriptionPlan: 'premium' as const, subscriptionExpiresAt: expiresAt };
  const now = new Date();
  // Un profil complet (prénom, nom, date de naissance, téléphone) : sans lui,
  // l'app ouvre « Compléter le profil » avant l'écran Premium. Apple a refusé
  // la 1.0.23 le 2 novembre 2026 en demandant « a fully set up demo account ».
  // Le numéro n'est attribué à personne (+226 suivi de huit zéros).
  const profil = {
    firstName:   'App',
    lastName:    'Review',
    birthDate:   new Date('1990-01-01T00:00:00Z'),
    phoneNumber: '+22600000000',
    countryCode: 'BF',
  };

  const user = await prisma.user.upsert({
    where: { email: review.email },
    update: {
      pseudo:                'Store Review',
      ...profil,
      emailVerified:         true,
      acceptedTermsAt:       now,
      isActive:              true,
      deletedAt:             null,
      ...formule,
    },
    create: {
      email:                 review.email,
      pseudo:                'Store Review',
      ...profil,
      referralCode:          generateReferralCode(),
      emailVerified:         true,
      acceptedTermsAt:       now,
      isActive:              true,
      ...formule,
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

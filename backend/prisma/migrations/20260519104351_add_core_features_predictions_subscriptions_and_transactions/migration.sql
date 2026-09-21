/*
  Warnings:

  - The values [failed] on the enum `TransactionStatus` will be removed. If these variants are still used in the database, this will fail.
  - You are about to drop the column `provider` on the `transactions` table. All the data in the column will be lost.
  - You are about to drop the column `provider_transaction_id` on the `transactions` table. All the data in the column will be lost.
  - You are about to drop the column `password_hash` on the `users` table. All the data in the column will be lost.

*/
-- CreateEnum
CREATE TYPE "MatchStatus" AS ENUM ('SCHEDULED', 'LIVE', 'FINISHED', 'POSTPONED', 'SUSPENDED');

-- CreateEnum
CREATE TYPE "PredictionType" AS ENUM ('win1', 'draw', 'win2', 'btts', 'over25', 'under25', 'over35', 'under35');

-- CreateEnum
CREATE TYPE "SubscriptionProofType" AS ENUM ('payment_screenshot', 'xbet_account_screenshot');

-- CreateEnum
CREATE TYPE "ProofStatus" AS ENUM ('pending', 'approved', 'rejected');

-- CreateEnum
CREATE TYPE "AdminRole" AS ENUM ('super_admin', 'analyst');

-- AlterEnum
BEGIN;
CREATE TYPE "TransactionStatus_new" AS ENUM ('pending', 'processing', 'completed', 'rejected');
ALTER TABLE "transactions" ALTER COLUMN "status" DROP DEFAULT;
ALTER TABLE "transactions" ALTER COLUMN "status" TYPE "TransactionStatus_new" USING ("status"::text::"TransactionStatus_new");
ALTER TYPE "TransactionStatus" RENAME TO "TransactionStatus_old";
ALTER TYPE "TransactionStatus_new" RENAME TO "TransactionStatus";
DROP TYPE "TransactionStatus_old";
ALTER TABLE "transactions" ALTER COLUMN "status" SET DEFAULT 'pending';
COMMIT;

-- AlterTable
ALTER TABLE "transactions" DROP COLUMN "provider",
DROP COLUMN "provider_transaction_id",
ADD COLUMN     "admin_note" TEXT,
ADD COLUMN     "processed_at" TIMESTAMP(3),
ADD COLUMN     "processed_by" TEXT,
ADD COLUMN     "sender_phone" TEXT,
ADD COLUMN     "xbet_id" TEXT;

-- AlterTable
ALTER TABLE "users" DROP COLUMN "password_hash",
ADD COLUMN     "fcm_token" TEXT,
ADD COLUMN     "xbet_id" TEXT;

-- CreateTable
CREATE TABLE "admins" (
    "id" TEXT NOT NULL,
    "email" TEXT NOT NULL,
    "password_hash" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "role" "AdminRole" NOT NULL DEFAULT 'analyst',
    "is_active" BOOLEAN NOT NULL DEFAULT true,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "last_login_at" TIMESTAMP(3),

    CONSTRAINT "admins_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "matches" (
    "id" TEXT NOT NULL,
    "external_id" INTEGER NOT NULL,
    "league" TEXT NOT NULL,
    "league_code" TEXT NOT NULL,
    "league_logo" TEXT,
    "home_team" TEXT NOT NULL,
    "home_team_full" TEXT,
    "home_team_logo" TEXT,
    "away_team" TEXT NOT NULL,
    "away_team_full" TEXT,
    "away_team_logo" TEXT,
    "match_date" TIMESTAMP(3) NOT NULL,
    "status" "MatchStatus" NOT NULL DEFAULT 'SCHEDULED',
    "home_score" INTEGER,
    "away_score" INTEGER,
    "home_form_points" INTEGER NOT NULL DEFAULT 0,
    "away_form_points" INTEGER NOT NULL DEFAULT 0,
    "fetched_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "matches_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "pronostics" (
    "id" TEXT NOT NULL,
    "match_id" TEXT NOT NULL,
    "analyst_id" TEXT NOT NULL,
    "prediction_type" "PredictionType" NOT NULL,
    "prediction_label" TEXT NOT NULL,
    "odds_home" DOUBLE PRECISION NOT NULL DEFAULT 0,
    "odds_draw" DOUBLE PRECISION NOT NULL DEFAULT 0,
    "odds_away" DOUBLE PRECISION NOT NULL DEFAULT 0,
    "odds_recommended" DOUBLE PRECISION NOT NULL,
    "confidence_score" INTEGER NOT NULL,
    "analyst_note" TEXT,
    "is_premium" BOOLEAN NOT NULL DEFAULT false,
    "is_published" BOOLEAN NOT NULL DEFAULT false,
    "result" TEXT,
    "published_at" TIMESTAMP(3),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "pronostics_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "subscription_proofs" (
    "id" TEXT NOT NULL,
    "user_id" TEXT NOT NULL,
    "subscription_id" TEXT,
    "type" "SubscriptionProofType" NOT NULL,
    "screenshot_url" TEXT NOT NULL,
    "xbet_id" TEXT,
    "amount" DOUBLE PRECISION,
    "sender_phone" TEXT,
    "status" "ProofStatus" NOT NULL DEFAULT 'pending',
    "admin_note" TEXT,
    "reviewed_by" TEXT,
    "reviewed_at" TIMESTAMP(3),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "subscription_proofs_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "admins_email_key" ON "admins"("email");

-- CreateIndex
CREATE UNIQUE INDEX "matches_external_id_key" ON "matches"("external_id");

-- CreateIndex
CREATE UNIQUE INDEX "pronostics_match_id_key" ON "pronostics"("match_id");

-- CreateIndex
CREATE UNIQUE INDEX "subscription_proofs_subscription_id_key" ON "subscription_proofs"("subscription_id");

-- AddForeignKey
ALTER TABLE "pronostics" ADD CONSTRAINT "pronostics_match_id_fkey" FOREIGN KEY ("match_id") REFERENCES "matches"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "pronostics" ADD CONSTRAINT "pronostics_analyst_id_fkey" FOREIGN KEY ("analyst_id") REFERENCES "admins"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "subscription_proofs" ADD CONSTRAINT "subscription_proofs_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "subscription_proofs" ADD CONSTRAINT "subscription_proofs_subscription_id_fkey" FOREIGN KEY ("subscription_id") REFERENCES "subscriptions"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- CreateEnum
CREATE TYPE "MatchSource" AS ENUM ('FOOTBALL_DATA', 'API_FOOTBALL');

-- DropIndex
DROP INDEX "matches_external_id_key";

-- AlterTable
ALTER TABLE "matches" ADD COLUMN     "source" "MatchSource" NOT NULL DEFAULT 'FOOTBALL_DATA';

-- AlterTable
ALTER TABLE "pronostics" ADD COLUMN     "is_daily_free" BOOLEAN NOT NULL DEFAULT false;

-- AlterTable
ALTER TABLE "tutorials" ADD COLUMN     "article_content" TEXT;

-- AlterTable
ALTER TABLE "user_bankrolls" ADD COLUMN     "last_reset_at" TIMESTAMP(3);

-- AlterTable
ALTER TABLE "users" ADD COLUMN     "deleted_at" TIMESTAMP(3),
ADD COLUMN     "email_verified" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "password_hash" TEXT,
ADD COLUMN     "phone_verified" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "streak_days" INTEGER NOT NULL DEFAULT 0,
ADD COLUMN     "streak_last_date" TIMESTAMP(3),
ADD COLUMN     "terms_version" INTEGER NOT NULL DEFAULT 1,
ADD COLUMN     "xp_total" INTEGER NOT NULL DEFAULT 0,
ALTER COLUMN "phone_number" DROP NOT NULL;

-- CreateTable
CREATE TABLE "tutorial_progress" (
    "id" TEXT NOT NULL,
    "user_id" TEXT NOT NULL,
    "tutorial_id" TEXT NOT NULL,
    "watched_seconds" INTEGER NOT NULL DEFAULT 0,
    "is_completed" BOOLEAN NOT NULL DEFAULT false,
    "completed_at" TIMESTAMP(3),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "tutorial_progress_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "comments" (
    "id" TEXT NOT NULL,
    "pronostic_id" TEXT NOT NULL,
    "user_id" TEXT NOT NULL,
    "content" TEXT NOT NULL,
    "is_expert" BOOLEAN NOT NULL DEFAULT false,
    "parent_id" TEXT,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "comments_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "pronostic_votes" (
    "id" TEXT NOT NULL,
    "pronostic_id" TEXT NOT NULL,
    "user_id" TEXT NOT NULL,
    "type" TEXT NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "pronostic_votes_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "tutorial_progress_user_id_tutorial_id_key" ON "tutorial_progress"("user_id", "tutorial_id");

-- CreateIndex
CREATE UNIQUE INDEX "pronostic_votes_pronostic_id_user_id_key" ON "pronostic_votes"("pronostic_id", "user_id");

-- CreateIndex
CREATE INDEX "matches_match_date_idx" ON "matches"("match_date");

-- CreateIndex
CREATE INDEX "matches_status_idx" ON "matches"("status");

-- CreateIndex
CREATE UNIQUE INDEX "matches_external_id_source_key" ON "matches"("external_id", "source");

-- CreateIndex
CREATE INDEX "transactions_status_idx" ON "transactions"("status");

-- CreateIndex
CREATE INDEX "transactions_user_id_created_at_idx" ON "transactions"("user_id", "created_at" DESC);

-- CreateIndex
CREATE INDEX "users_created_at_idx" ON "users"("created_at");

-- AddForeignKey
ALTER TABLE "tutorial_progress" ADD CONSTRAINT "tutorial_progress_tutorial_id_fkey" FOREIGN KEY ("tutorial_id") REFERENCES "tutorials"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "tutorial_progress" ADD CONSTRAINT "tutorial_progress_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "comments" ADD CONSTRAINT "comments_pronostic_id_fkey" FOREIGN KEY ("pronostic_id") REFERENCES "pronostics"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "comments" ADD CONSTRAINT "comments_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "comments" ADD CONSTRAINT "comments_parent_id_fkey" FOREIGN KEY ("parent_id") REFERENCES "comments"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "pronostic_votes" ADD CONSTRAINT "pronostic_votes_pronostic_id_fkey" FOREIGN KEY ("pronostic_id") REFERENCES "pronostics"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "pronostic_votes" ADD CONSTRAINT "pronostic_votes_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;


-- AlterTable
ALTER TABLE "matches" ADD COLUMN     "status_priority" INTEGER NOT NULL DEFAULT 1;

-- CreateIndex
CREATE INDEX "matches_status_priority_idx" ON "matches"("status_priority");

-- Backfill : LIVE=0, SCHEDULED=1 (déjà la valeur par défaut), FINISHED=2, autre=3
UPDATE "matches" SET "status_priority" = 0 WHERE "status" = 'LIVE';
UPDATE "matches" SET "status_priority" = 2 WHERE "status" = 'FINISHED';
UPDATE "matches" SET "status_priority" = 3 WHERE "status" IN ('POSTPONED', 'SUSPENDED');

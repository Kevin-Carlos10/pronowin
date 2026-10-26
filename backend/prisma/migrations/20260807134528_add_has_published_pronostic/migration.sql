-- AlterTable
ALTER TABLE "matches" ADD COLUMN     "has_published_pronostic" BOOLEAN NOT NULL DEFAULT false;

-- CreateIndex
CREATE INDEX "matches_has_published_pronostic_idx" ON "matches"("has_published_pronostic");

-- Backfill : synchroniser le flag pour les pronostics déjà publiés
UPDATE "matches" m
SET "has_published_pronostic" = true
WHERE EXISTS (
  SELECT 1 FROM "pronostics" p
  WHERE p."match_id" = m.id AND p."is_published" = true
);

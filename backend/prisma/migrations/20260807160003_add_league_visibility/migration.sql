-- CreateTable
CREATE TABLE "league_visibility" (
    "league_code" TEXT NOT NULL,
    "league" TEXT NOT NULL,
    "is_visible" BOOLEAN NOT NULL DEFAULT false,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "league_visibility_pkey" PRIMARY KEY ("league_code")
);

-- CreateIndex
CREATE INDEX "league_visibility_is_visible_idx" ON "league_visibility"("is_visible");

-- Backfill : les grandes compétitions déjà suivies par défaut (LEAGUE_MAP
-- dans api_football.service.ts) restent visibles pour ne rien changer au
-- comportement actuel — tout le reste devra être activé manuellement par
-- l'admin via /admin/leagues.
INSERT INTO "league_visibility" ("league_code", "league", "is_visible", "updated_at") VALUES
  ('WC',       'Coupe du Monde',     true, now()),
  ('PL',       'Premier League',     true, now()),
  ('BL1',      'Bundesliga',         true, now()),
  ('SA',       'Serie A',            true, now()),
  ('PD',       'La Liga',            true, now()),
  ('FL1',      'Ligue 1',            true, now()),
  ('CL',       'Champions League',   true, now()),
  ('FRIENDLY', 'Matchs amicaux',     true, now());

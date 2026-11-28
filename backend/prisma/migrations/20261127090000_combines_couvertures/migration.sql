-- Couverture enregistrée, seconde alerte et coupons combinés (27 novembre 2026).

-- AlterTable
ALTER TABLE "bankroll_bets" ADD COLUMN     "couverture_alertes" INTEGER NOT NULL DEFAULT 0;

-- CreateTable
CREATE TABLE "bankroll_combines" (
    "id" TEXT NOT NULL,
    "bankroll_id" TEXT NOT NULL,
    "staked_amount" DOUBLE PRECISION NOT NULL,
    "suggested_amount" DOUBLE PRECISION NOT NULL,
    "odds_used" DOUBLE PRECISION NOT NULL,
    "potential_gain" DOUBLE PRECISION NOT NULL,
    "note_retenue" INTEGER NOT NULL,
    "result" TEXT,
    "retour" DOUBLE PRECISION,
    "profit" DOUBLE PRECISION,
    "settled_at" TIMESTAMP(3),
    "couverture_alertes" INTEGER NOT NULL DEFAULT 0,
    "couverture_notifiee_le" TIMESTAMP(3),
    "couverture" JSONB,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "bankroll_combines_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "bankroll_combine_selections" (
    "id" TEXT NOT NULL,
    "combine_id" TEXT NOT NULL,
    "ordre" INTEGER NOT NULL,
    "pronostic_id" TEXT,
    "libre_match" TEXT,
    "libre_selection" TEXT,
    "cote" DOUBLE PRECISION NOT NULL,
    "note" INTEGER NOT NULL,
    "result" TEXT,
    "annulee" BOOLEAN NOT NULL DEFAULT false,
    "settled_at" TIMESTAMP(3),

    CONSTRAINT "bankroll_combine_selections_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "bankroll_couvertures" (
    "id" TEXT NOT NULL,
    "bankroll_id" TEXT NOT NULL,
    "pari_id" TEXT,
    "combine_id" TEXT,
    "pronostic_id" TEXT NOT NULL,
    "selection_fr" TEXT NOT NULL,
    "selection_en" TEXT NOT NULL,
    "strategie" TEXT NOT NULL,
    "mise" DOUBLE PRECISION NOT NULL,
    "cote" DOUBLE PRECISION NOT NULL,
    "result" TEXT,
    "profit" DOUBLE PRECISION,
    "settled_at" TIMESTAMP(3),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "bankroll_couvertures_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "bankroll_combines_bankroll_id_created_at_idx" ON "bankroll_combines"("bankroll_id", "created_at");

-- CreateIndex
CREATE INDEX "bankroll_combines_result_idx" ON "bankroll_combines"("result");

-- CreateIndex
CREATE INDEX "bankroll_combine_selections_combine_id_idx" ON "bankroll_combine_selections"("combine_id");

-- CreateIndex
CREATE INDEX "bankroll_combine_selections_pronostic_id_idx" ON "bankroll_combine_selections"("pronostic_id");

-- CreateIndex
CREATE UNIQUE INDEX "bankroll_couvertures_pari_id_key" ON "bankroll_couvertures"("pari_id");

-- CreateIndex
CREATE UNIQUE INDEX "bankroll_couvertures_combine_id_key" ON "bankroll_couvertures"("combine_id");

-- CreateIndex
CREATE INDEX "bankroll_couvertures_pronostic_id_idx" ON "bankroll_couvertures"("pronostic_id");

-- CreateIndex
CREATE INDEX "bankroll_couvertures_bankroll_id_idx" ON "bankroll_couvertures"("bankroll_id");

-- AddForeignKey
ALTER TABLE "bankroll_combines" ADD CONSTRAINT "bankroll_combines_bankroll_id_fkey" FOREIGN KEY ("bankroll_id") REFERENCES "user_bankrolls"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "bankroll_combine_selections" ADD CONSTRAINT "bankroll_combine_selections_combine_id_fkey" FOREIGN KEY ("combine_id") REFERENCES "bankroll_combines"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "bankroll_combine_selections" ADD CONSTRAINT "bankroll_combine_selections_pronostic_id_fkey" FOREIGN KEY ("pronostic_id") REFERENCES "pronostics"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "bankroll_couvertures" ADD CONSTRAINT "bankroll_couvertures_bankroll_id_fkey" FOREIGN KEY ("bankroll_id") REFERENCES "user_bankrolls"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "bankroll_couvertures" ADD CONSTRAINT "bankroll_couvertures_pari_id_fkey" FOREIGN KEY ("pari_id") REFERENCES "bankroll_bets"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "bankroll_couvertures" ADD CONSTRAINT "bankroll_couvertures_combine_id_fkey" FOREIGN KEY ("combine_id") REFERENCES "bankroll_combines"("id") ON DELETE CASCADE ON UPDATE CASCADE;


-- Les mises déjà alertées comptent une alerte.
UPDATE "bankroll_bets" SET "couverture_alertes" = 1 WHERE "couverture_notifiee_le" IS NOT NULL;

-- Une couverture porte sur une mise simple ou sur un combiné, jamais les deux.
ALTER TABLE "bankroll_couvertures" ADD CONSTRAINT "bankroll_couvertures_une_cible"
  CHECK (("pari_id" IS NULL) <> ("combine_id" IS NULL));

-- Paiements Mobile Money par GeniusPay (13 octobre 2026) : une ligne par
-- tentative, référence GeniusPay unique, Premium accordé une seule fois.

-- CreateTable
CREATE TABLE "paiements_geniuspay" (
    "id" TEXT NOT NULL,
    "user_id" TEXT NOT NULL,
    "plan" TEXT NOT NULL,
    "montant" INTEGER NOT NULL,
    "reference" TEXT,
    "statut" TEXT NOT NULL DEFAULT 'pending',
    "environnement" TEXT NOT NULL,
    "checkout_url" TEXT,
    "moyen" TEXT,
    "frais" INTEGER,
    "montant_net" INTEGER,
    "premium_accorde_le" TIMESTAMP(3),
    "cree_le" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "maj_le" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "paiements_geniuspay_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "paiements_geniuspay_reference_key" ON "paiements_geniuspay"("reference");

-- CreateIndex
CREATE INDEX "paiements_geniuspay_user_id_cree_le_idx" ON "paiements_geniuspay"("user_id", "cree_le");

-- CreateIndex
CREATE INDEX "paiements_geniuspay_statut_cree_le_idx" ON "paiements_geniuspay"("statut", "cree_le");

-- AddForeignKey
ALTER TABLE "paiements_geniuspay" ADD CONSTRAINT "paiements_geniuspay_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;


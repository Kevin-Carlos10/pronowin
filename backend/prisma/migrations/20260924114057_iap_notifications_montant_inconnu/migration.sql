-- AlterTable
ALTER TABLE "subscriptions" ALTER COLUMN "amount_paid" DROP NOT NULL;

-- CreateTable
CREATE TABLE "iap_notifications" (
    "id" TEXT NOT NULL,
    "store" "IapStore" NOT NULL,
    "evenement_id" TEXT NOT NULL,
    "charge" JSONB NOT NULL,
    "statut" TEXT NOT NULL DEFAULT 'recue',
    "tentatives" INTEGER NOT NULL DEFAULT 0,
    "prochaine_tentative" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "derniere_erreur" TEXT,
    "recue_le" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "traitee_le" TIMESTAMP(3),

    CONSTRAINT "iap_notifications_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "iap_notifications_statut_prochaine_tentative_idx" ON "iap_notifications"("statut", "prochaine_tentative");

-- CreateIndex
CREATE UNIQUE INDEX "iap_notifications_store_evenement_id_key" ON "iap_notifications"("store", "evenement_id");

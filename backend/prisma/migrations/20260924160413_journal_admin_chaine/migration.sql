-- CreateTable
CREATE TABLE "journal_admin" (
    "id" SERIAL NOT NULL,
    "horodatage" TIMESTAMP(3) NOT NULL,
    "action" TEXT NOT NULL,
    "cible" TEXT NOT NULL DEFAULT '',
    "details" JSONB,
    "acteur_id" TEXT NOT NULL,
    "acteur_nom" TEXT NOT NULL,
    "acteur_role" TEXT NOT NULL,
    "ip" TEXT,
    "empreinte_precedente" TEXT NOT NULL,
    "empreinte" TEXT NOT NULL,

    CONSTRAINT "journal_admin_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "journal_admin_empreinte_key" ON "journal_admin"("empreinte");

-- CreateIndex
CREATE INDEX "journal_admin_horodatage_idx" ON "journal_admin"("horodatage");

-- CreateIndex
CREATE INDEX "journal_admin_acteur_id_horodatage_idx" ON "journal_admin"("acteur_id", "horodatage");

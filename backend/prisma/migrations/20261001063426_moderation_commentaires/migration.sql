-- AlterTable
ALTER TABLE "comments" ADD COLUMN     "masque" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "masque_le" TIMESTAMP(3);

-- CreateTable
CREATE TABLE "signalements_commentaires" (
    "id" TEXT NOT NULL,
    "comment_id" TEXT NOT NULL,
    "auteur_id" TEXT NOT NULL,
    "motif" TEXT NOT NULL,
    "detail" TEXT,
    "statut" TEXT NOT NULL DEFAULT 'en_attente',
    "cree_le" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "traite_le" TIMESTAMP(3),
    "traite_par" TEXT,

    CONSTRAINT "signalements_commentaires_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "blocages_utilisateurs" (
    "id" TEXT NOT NULL,
    "bloqueur_id" TEXT NOT NULL,
    "bloque_id" TEXT NOT NULL,
    "cree_le" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "blocages_utilisateurs_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "signalements_commentaires_statut_cree_le_idx" ON "signalements_commentaires"("statut", "cree_le");

-- CreateIndex
CREATE UNIQUE INDEX "signalements_commentaires_comment_id_auteur_id_key" ON "signalements_commentaires"("comment_id", "auteur_id");

-- CreateIndex
CREATE INDEX "blocages_utilisateurs_bloque_id_idx" ON "blocages_utilisateurs"("bloque_id");

-- CreateIndex
CREATE UNIQUE INDEX "blocages_utilisateurs_bloqueur_id_bloque_id_key" ON "blocages_utilisateurs"("bloqueur_id", "bloque_id");

-- AddForeignKey
ALTER TABLE "signalements_commentaires" ADD CONSTRAINT "signalements_commentaires_comment_id_fkey" FOREIGN KEY ("comment_id") REFERENCES "comments"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "signalements_commentaires" ADD CONSTRAINT "signalements_commentaires_auteur_id_fkey" FOREIGN KEY ("auteur_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "blocages_utilisateurs" ADD CONSTRAINT "blocages_utilisateurs_bloqueur_id_fkey" FOREIGN KEY ("bloqueur_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "blocages_utilisateurs" ADD CONSTRAINT "blocages_utilisateurs_bloque_id_fkey" FOREIGN KEY ("bloque_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;


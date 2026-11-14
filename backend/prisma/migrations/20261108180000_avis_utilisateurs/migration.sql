-- « Donne-nous ton avis » : messages des utilisateurs, capture facultative.
CREATE TABLE "avis_utilisateurs" (
    "id" TEXT NOT NULL,
    "user_id" TEXT,
    "email" TEXT,
    "message" TEXT NOT NULL,
    "capture_url" TEXT,
    "plateforme" TEXT,
    "version_app" TEXT,
    "traite" BOOLEAN NOT NULL DEFAULT false,
    "traite_le" TIMESTAMP(3),
    "cree_le" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "avis_utilisateurs_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "avis_utilisateurs_traite_cree_le_idx" ON "avis_utilisateurs"("traite", "cree_le");

ALTER TABLE "avis_utilisateurs" ADD CONSTRAINT "avis_utilisateurs_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

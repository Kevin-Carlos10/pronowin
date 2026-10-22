-- La version de l'application utilisée par chaque membre.
--
-- Le serveur l'ignorait : impossible de savoir combien de membres restaient
-- sur une version ancienne avant de relever la version minimale.
CREATE TABLE "versions_app_comptes" (
    "user_id" TEXT NOT NULL,
    "version" TEXT NOT NULL,
    "build" INTEGER,
    "plateforme" TEXT NOT NULL,
    "canal" TEXT,
    "vu_le" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "versions_app_comptes_pkey" PRIMARY KEY ("user_id")
);

CREATE INDEX "versions_app_comptes_version_idx" ON "versions_app_comptes"("version");

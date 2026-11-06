-- Consommation d'API-Football, par jour et par famille d'appel.
--
-- Le panneau ne voyait que le dernier quota restant relevé : ni ce qui
-- l'avait consommé, ni la tendance des jours précédents.
CREATE TABLE "consommation_football" (
    "jour" TEXT NOT NULL,
    "famille" TEXT NOT NULL,
    "appels" INTEGER NOT NULL DEFAULT 0,
    "echecs" INTEGER NOT NULL DEFAULT 0,

    CONSTRAINT "consommation_football_pkey" PRIMARY KEY ("jour","famille")
);

-- Le quota tel que le fournisseur le compte, relevé chaque jour.
CREATE TABLE "quota_football_jours" (
    "jour" TEXT NOT NULL,
    "limite" INTEGER NOT NULL,
    "restant_min" INTEGER NOT NULL,
    "releve_le" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "quota_football_jours_pkey" PRIMARY KEY ("jour")
);

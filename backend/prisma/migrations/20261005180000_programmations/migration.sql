-- Actions d'administration programmées : publier un pronostic, envoyer une
-- notification, à une heure choisie. Rien ne le permettait : un pronostic
-- prêt la veille devait être publié à la main le lendemain matin.
CREATE TABLE "programmations" (
    "id" TEXT NOT NULL,
    "type" TEXT NOT NULL,
    "pronostic_id" TEXT,
    "charge" JSONB,
    "prevue_le" TIMESTAMP(3) NOT NULL,
    "statut" TEXT NOT NULL DEFAULT 'prevue',
    "creee_par" TEXT,
    "creee_le" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "executee_le" TIMESTAMP(3),
    "compte_rendu" TEXT,

    CONSTRAINT "programmations_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "programmations_statut_prevue_le_idx" ON "programmations"("statut", "prevue_le");
CREATE INDEX "programmations_pronostic_id_idx" ON "programmations"("pronostic_id");

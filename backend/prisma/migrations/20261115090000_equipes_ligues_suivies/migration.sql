-- Les équipes et ligues suivies, connues du serveur pour leurs alertes
-- (15 novembre 2026).
CREATE TABLE "user_equipes_suivies" (
    "id" TEXT NOT NULL,
    "user_id" TEXT NOT NULL,
    "equipe_id" INTEGER NOT NULL,
    "nom" TEXT NOT NULL,
    "logo" TEXT,
    "competition" TEXT,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "user_equipes_suivies_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "user_ligues_suivies" (
    "id" TEXT NOT NULL,
    "user_id" TEXT NOT NULL,
    "ligue" TEXT NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "user_ligues_suivies_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "user_equipes_suivies_equipe_id_idx" ON "user_equipes_suivies"("equipe_id");

CREATE UNIQUE INDEX "user_equipes_suivies_user_id_equipe_id_key" ON "user_equipes_suivies"("user_id", "equipe_id");

CREATE INDEX "user_ligues_suivies_ligue_idx" ON "user_ligues_suivies"("ligue");

CREATE UNIQUE INDEX "user_ligues_suivies_user_id_ligue_key" ON "user_ligues_suivies"("user_id", "ligue");

ALTER TABLE "user_equipes_suivies" ADD CONSTRAINT "user_equipes_suivies_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "user_ligues_suivies" ADD CONSTRAINT "user_ligues_suivies_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

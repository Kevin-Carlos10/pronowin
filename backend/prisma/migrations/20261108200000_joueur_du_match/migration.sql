-- « Joueur du match » : le vote des fans, à partir de la 80e minute.
CREATE TABLE "votes_joueur_du_match" (
    "id" TEXT NOT NULL,
    "match_id" TEXT NOT NULL,
    "user_id" TEXT NOT NULL,
    "joueur_id" INTEGER NOT NULL,
    "joueur_nom" TEXT NOT NULL,
    "equipe" TEXT NOT NULL,
    "cree_le" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "modifie_le" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "votes_joueur_du_match_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "votes_joueur_du_match_match_id_user_id_key" ON "votes_joueur_du_match"("match_id", "user_id");

CREATE INDEX "votes_joueur_du_match_match_id_idx" ON "votes_joueur_du_match"("match_id");

ALTER TABLE "votes_joueur_du_match" ADD CONSTRAINT "votes_joueur_du_match_match_id_fkey" FOREIGN KEY ("match_id") REFERENCES "matches"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "votes_joueur_du_match" ADD CONSTRAINT "votes_joueur_du_match_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

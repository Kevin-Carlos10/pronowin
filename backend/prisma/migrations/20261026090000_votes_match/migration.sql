-- « Qui va gagner ? » : le vote des fans avant le match.
CREATE TABLE "votes_match" (
    "id" TEXT NOT NULL,
    "match_id" TEXT NOT NULL,
    "user_id" TEXT NOT NULL,
    "choix" TEXT NOT NULL,
    "cree_le" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "modifie_le" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "votes_match_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "votes_match_match_id_user_id_key" ON "votes_match"("match_id", "user_id");

CREATE INDEX "votes_match_match_id_idx" ON "votes_match"("match_id");

ALTER TABLE "votes_match" ADD CONSTRAINT "votes_match_match_id_fkey" FOREIGN KEY ("match_id") REFERENCES "matches"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "votes_match" ADD CONSTRAINT "votes_match_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

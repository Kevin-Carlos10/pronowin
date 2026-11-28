-- Résumés automatiques des matchs terminés (actualités de l'accueil).
CREATE TABLE "resumes_match" (
    "id" TEXT NOT NULL,
    "match_id" TEXT NOT NULL,
    "titre" TEXT NOT NULL,
    "titre_en" TEXT NOT NULL,
    "resume" TEXT NOT NULL,
    "resume_en" TEXT NOT NULL,
    "ligue" TEXT NOT NULL,
    "cree_le" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "resumes_match_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "resumes_match_match_id_key" ON "resumes_match"("match_id");

CREATE INDEX "resumes_match_cree_le_idx" ON "resumes_match"("cree_le");

ALTER TABLE "resumes_match" ADD CONSTRAINT "resumes_match_match_id_fkey" FOREIGN KEY ("match_id") REFERENCES "matches"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- Avant-matchs : un second genre d'article écrit seul sur un match. Un
-- résumé et un avant-match au plus par match.
ALTER TABLE "resumes_match" ADD COLUMN "genre" TEXT NOT NULL DEFAULT 'resume';
DROP INDEX "resumes_match_match_id_key";
CREATE UNIQUE INDEX "resumes_match_match_id_genre_key" ON "resumes_match"("match_id", "genre");

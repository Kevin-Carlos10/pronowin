-- Résumés de match : corrigés ou retirés du fil depuis le panneau.
ALTER TABLE "resumes_match" ADD COLUMN "masque" BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE "resumes_match" ADD COLUMN "modifie_le" TIMESTAMP(3);
ALTER TABLE "resumes_match" ADD COLUMN "modifie_par" TEXT;

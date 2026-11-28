-- Indice de confiance saisi en pourcentage par l'analyste.
--
-- Le niveau de 1 à 5 (confidence_score) reste, déduit du pourcentage : le
-- barème de mise et les applications déjà installées le lisent.
ALTER TABLE "pronostics" ADD COLUMN "confidence_pct" INTEGER;

-- Pronostics existants : le milieu de leur palier (1 → 10 … 5 → 90). Rien
-- n'est inventé : redéduire le niveau de ce pourcentage redonne le niveau
-- saisi à l'époque.
UPDATE "pronostics"
   SET "confidence_pct" = LEAST(GREATEST("confidence_score", 1), 5) * 20 - 10
 WHERE "confidence_pct" IS NULL;

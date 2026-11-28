-- Pays de la compétition, pour distinguer les homonymes dans le filtre admin.
-- Deux « Serie A » (Italie, Brésil) s'affichaient à l'identique.
-- Nullable : rempli au fil des synchronisations, sans reprise d'historique.
ALTER TABLE "matches" ADD COLUMN "league_country" TEXT;

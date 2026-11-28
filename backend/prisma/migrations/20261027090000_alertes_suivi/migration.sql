-- Les alertes choisies pour chaque match suivi : toutes par défaut, y compris
-- pour les suivis existants.
ALTER TABLE "user_favorite_matches" ADD COLUMN "alertes" TEXT[] DEFAULT ARRAY['coup_envoi', 'compositions', 'buts', 'cartons', 'mi_temps', 'fin_de_match', 'resume']::TEXT[];

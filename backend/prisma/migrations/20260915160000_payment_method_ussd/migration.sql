-- Modèle de code USSD par opérateur.
--
-- Nullable et sans valeur par défaut : une méthode sans modèle se comporte
-- exactement comme avant (le numéro seul). Rien à rétro-remplir.
ALTER TABLE "payment_methods" ADD COLUMN "ussd_template" TEXT;

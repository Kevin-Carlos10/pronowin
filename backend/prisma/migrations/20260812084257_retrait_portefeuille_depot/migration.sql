-- Retrait du portefeuille dépôt/retrait.
--
-- Plus aucun chemin applicatif ne peut créer un dépôt : l'écran mobile a été
-- supprimé, et avec lui la route `POST /payments/request` qui était le seul
-- moyen d'en produire. Le modèle Transaction ne sert plus qu'au versement des
-- gains de parrainage, toujours de type `withdrawal`.
--
-- La table était vide au moment de la migration (0 ligne, tous types et tous
-- statuts confondus) : aucune donnée n'est perdue. Postgres ne sachant pas
-- retirer une valeur d'un type énuméré, on recrée le type et on bascule la
-- colonne dessus.
BEGIN;

CREATE TYPE "TransactionType_new" AS ENUM ('withdrawal');

ALTER TABLE "transactions"
  ALTER COLUMN "type" TYPE "TransactionType_new"
  USING ("type"::text::"TransactionType_new");

ALTER TYPE "TransactionType" RENAME TO "TransactionType_old";
ALTER TYPE "TransactionType_new" RENAME TO "TransactionType";
DROP TYPE "TransactionType_old";

COMMIT;

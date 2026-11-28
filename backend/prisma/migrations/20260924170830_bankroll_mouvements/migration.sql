-- AlterTable
ALTER TABLE "bankroll_bets" ADD COLUMN     "mise_confirmee_le" TIMESTAMP(3);

-- CreateTable
CREATE TABLE "bankroll_mouvements" (
    "id" TEXT NOT NULL,
    "bankroll_id" TEXT NOT NULL,
    "type" TEXT NOT NULL,
    "montant" DOUBLE PRECISION NOT NULL,
    "solde_apres" DOUBLE PRECISION NOT NULL,
    "pari_id" TEXT,
    "motif" TEXT,
    "cree_le" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "bankroll_mouvements_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "bankroll_mouvements_bankroll_id_cree_le_idx" ON "bankroll_mouvements"("bankroll_id", "cree_le");

-- AddForeignKey
ALTER TABLE "bankroll_mouvements" ADD CONSTRAINT "bankroll_mouvements_bankroll_id_fkey" FOREIGN KEY ("bankroll_id") REFERENCES "user_bankrolls"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- Montants à l'unité de la devise (B1). Le franc CFA et le franc guinéen
-- n'ont pas de centimes : un gain potentiel de 2 134,82 FCFA ne se verse pas,
-- et des centimes fictifs accumulés en virgule flottante rendent le solde
-- inexact. Mêmes devises que `pasDeDevise` (mise_suggeree.ts).
--
-- Paris en attente : gain potentiel arrondi à l'unité inférieure, comme le
-- versement d'un bookmaker. Les paris réglés gardent leur historique.
UPDATE "bankroll_bets" AS b
SET "potential_gain" = FLOOR(b."potential_gain")
FROM "user_bankrolls" AS u
WHERE b."bankroll_id" = u."id"
  AND b."result" IS NULL
  AND UPPER(u."currency") IN ('XOF', 'XAF', 'GNF', 'JPY', 'KRW')
  AND b."potential_gain" <> FLOOR(b."potential_gain");

-- Soldes : à l'unité la plus proche, ou au centime pour les autres devises.
UPDATE "user_bankrolls"
SET "current_balance" = ROUND("current_balance")
WHERE UPPER("currency") IN ('XOF', 'XAF', 'GNF', 'JPY', 'KRW')
  AND "current_balance" <> ROUND("current_balance");

UPDATE "user_bankrolls"
SET "current_balance" = ROUND("current_balance"::numeric, 2)::double precision
WHERE UPPER("currency") NOT IN ('XOF', 'XAF', 'GNF', 'JPY', 'KRW');

-- Le journal commence ici : l'historique d'avant n'a pas été enregistré. La
-- ligne « reprise » pose le solde de départ, et la somme des mouvements d'une
-- bankroll vaut son solde à partir de maintenant.
INSERT INTO "bankroll_mouvements" ("id", "bankroll_id", "type", "montant", "solde_apres", "motif")
SELECT gen_random_uuid()::text, "id", 'reprise', "current_balance", "current_balance",
       'Solde repris à l''ouverture du journal'
FROM "user_bankrolls";

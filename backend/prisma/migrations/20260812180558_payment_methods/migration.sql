-- Numéros Mobile Money gérés depuis l'administration.
--
-- Remplace les variables MOBCASH_* du serveur ET la constante `_paymentPhone`
-- codée en dur dans l'app mobile, qui ne portaient déjà pas les mêmes valeurs.
CREATE TABLE "payment_methods" (
    "id"         TEXT NOT NULL,
    "key"        TEXT NOT NULL,
    "label"      TEXT NOT NULL,
    "phone"      TEXT NOT NULL,
    "is_active"  BOOLEAN NOT NULL DEFAULT true,
    "sort_order" INTEGER NOT NULL DEFAULT 0,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "payment_methods_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "payment_methods_key_key" ON "payment_methods"("key");
CREATE INDEX "payment_methods_is_active_sort_order_idx" ON "payment_methods"("is_active", "sort_order");

-- Amorçage avec le numéro réellement affiché aux utilisateurs aujourd'hui.
-- Sans cette ligne, l'écran de paiement n'afficherait plus aucun numéro entre
-- la migration et la première saisie en administration.
INSERT INTO "payment_methods" ("id", "key", "label", "phone", "sort_order", "updated_at")
VALUES (gen_random_uuid()::text, 'orange_money', 'Orange Money', '22645568158', 0, CURRENT_TIMESTAMP);

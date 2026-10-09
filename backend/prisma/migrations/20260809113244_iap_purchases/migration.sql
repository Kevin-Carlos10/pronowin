-- CreateEnum
CREATE TYPE "IapStore" AS ENUM ('apple', 'google');

-- CreateTable
CREATE TABLE "iap_purchases" (
    "id" TEXT NOT NULL,
    "user_id" TEXT NOT NULL,
    "store" "IapStore" NOT NULL,
    "product_id" TEXT NOT NULL,
    "transaction_id" TEXT NOT NULL,
    "original_transaction_id" TEXT NOT NULL,
    "expires_at" TIMESTAMP(3) NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'active',
    "environment" TEXT NOT NULL DEFAULT 'Production',
    "payload" JSONB,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "iap_purchases_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "iap_purchases_transaction_id_key" ON "iap_purchases"("transaction_id");

-- CreateIndex
CREATE INDEX "iap_purchases_user_id_expires_at_idx" ON "iap_purchases"("user_id", "expires_at" DESC);

-- CreateIndex
CREATE INDEX "iap_purchases_original_transaction_id_idx" ON "iap_purchases"("original_transaction_id");

-- AddForeignKey
ALTER TABLE "iap_purchases" ADD CONSTRAINT "iap_purchases_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

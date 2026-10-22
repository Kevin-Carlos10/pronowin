-- AlterEnum
ALTER TYPE "PredictionType" ADD VALUE 'other';

-- AlterTable
ALTER TABLE "pronostics" ADD COLUMN     "market_name" TEXT,
ADD COLUMN     "market_value" TEXT;

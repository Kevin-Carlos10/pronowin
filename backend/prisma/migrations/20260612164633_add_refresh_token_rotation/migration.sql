-- AlterTable
ALTER TABLE "refresh_tokens" ADD COLUMN     "used" BOOLEAN NOT NULL DEFAULT false;

-- Alerte de couverture (26 novembre 2026) : la cote obtenue chez le
-- bookmaker, et la trace de l'alerte envoyée (une seule par mise).
ALTER TABLE "bankroll_bets" ADD COLUMN "cote_bookmaker" DOUBLE PRECISION;
ALTER TABLE "bankroll_bets" ADD COLUMN "couverture_notifiee_le" TIMESTAMP(3);
ALTER TABLE "bankroll_bets" ADD COLUMN "couverture" JSONB;

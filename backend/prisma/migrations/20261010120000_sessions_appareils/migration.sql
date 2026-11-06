-- Colonnes facultatives pour préserver les sessions et les anciens clients.
ALTER TABLE "refresh_tokens"
  ADD COLUMN "session_id" TEXT,
  ADD COLUMN "started_at" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP,
  ADD COLUMN "last_seen_at" TIMESTAMP(3),
  ADD COLUMN "platform" TEXT;
UPDATE "refresh_tokens" SET "session_id" = "id", "started_at" = "created_at";
CREATE INDEX "refresh_tokens_user_id_used_expires_at_idx" ON "refresh_tokens"("user_id", "used", "expires_at");
CREATE INDEX "refresh_tokens_user_id_session_id_idx" ON "refresh_tokens"("user_id", "session_id");

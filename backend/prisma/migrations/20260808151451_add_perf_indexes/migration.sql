-- CreateIndex
CREATE INDEX "bankroll_bets_result_created_at_idx" ON "bankroll_bets"("result", "created_at");

-- CreateIndex
CREATE INDEX "comments_pronostic_id_created_at_idx" ON "comments"("pronostic_id", "created_at");

-- CreateIndex
CREATE INDEX "comments_user_id_idx" ON "comments"("user_id");

-- CreateIndex
CREATE INDEX "referrals_referred_id_idx" ON "referrals"("referred_id");

-- CreateIndex
CREATE INDEX "subscription_proofs_status_created_at_idx" ON "subscription_proofs"("status", "created_at");

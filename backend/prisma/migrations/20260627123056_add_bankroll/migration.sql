-- CreateTable
CREATE TABLE "user_bankrolls" (
    "id" TEXT NOT NULL,
    "user_id" TEXT NOT NULL,
    "total_budget" DOUBLE PRECISION NOT NULL,
    "current_balance" DOUBLE PRECISION NOT NULL,
    "currency" TEXT NOT NULL DEFAULT 'XOF',
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "user_bankrolls_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "bankroll_bets" (
    "id" TEXT NOT NULL,
    "bankroll_id" TEXT NOT NULL,
    "pronostic_id" TEXT NOT NULL,
    "staked_amount" DOUBLE PRECISION NOT NULL,
    "suggested_amount" DOUBLE PRECISION NOT NULL,
    "odds_used" DOUBLE PRECISION NOT NULL,
    "potential_gain" DOUBLE PRECISION NOT NULL,
    "result" TEXT,
    "profit" DOUBLE PRECISION,
    "settled_at" TIMESTAMP(3),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "bankroll_bets_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "user_bankrolls_user_id_key" ON "user_bankrolls"("user_id");

-- CreateIndex
CREATE INDEX "bankroll_bets_pronostic_id_idx" ON "bankroll_bets"("pronostic_id");

-- CreateIndex
CREATE UNIQUE INDEX "bankroll_bets_bankroll_id_pronostic_id_key" ON "bankroll_bets"("bankroll_id", "pronostic_id");

-- AddForeignKey
ALTER TABLE "user_bankrolls" ADD CONSTRAINT "user_bankrolls_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "bankroll_bets" ADD CONSTRAINT "bankroll_bets_bankroll_id_fkey" FOREIGN KEY ("bankroll_id") REFERENCES "user_bankrolls"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "bankroll_bets" ADD CONSTRAINT "bankroll_bets_pronostic_id_fkey" FOREIGN KEY ("pronostic_id") REFERENCES "pronostics"("id") ON DELETE CASCADE ON UPDATE CASCADE;

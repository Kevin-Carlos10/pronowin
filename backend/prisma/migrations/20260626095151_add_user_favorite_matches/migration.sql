-- CreateTable
CREATE TABLE "user_favorite_matches" (
    "id" TEXT NOT NULL,
    "user_id" TEXT NOT NULL,
    "match_id" TEXT NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "user_favorite_matches_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "user_favorite_matches_match_id_idx" ON "user_favorite_matches"("match_id");

-- CreateIndex
CREATE UNIQUE INDEX "user_favorite_matches_user_id_match_id_key" ON "user_favorite_matches"("user_id", "match_id");

-- AddForeignKey
ALTER TABLE "user_favorite_matches" ADD CONSTRAINT "user_favorite_matches_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "user_favorite_matches" ADD CONSTRAINT "user_favorite_matches_match_id_fkey" FOREIGN KEY ("match_id") REFERENCES "matches"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- CreateTable
CREATE TABLE "appareils_notification" (
    "id" TEXT NOT NULL,
    "user_id" TEXT NOT NULL,
    "jeton" TEXT NOT NULL,
    "plateforme" TEXT NOT NULL DEFAULT 'android',
    "cree_le" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "vu_le" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "appareils_notification_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "appareils_notification_jeton_key" ON "appareils_notification"("jeton");

-- CreateIndex
CREATE INDEX "appareils_notification_user_id_idx" ON "appareils_notification"("user_id");

-- AddForeignKey
ALTER TABLE "appareils_notification" ADD CONSTRAINT "appareils_notification_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- Reprise des jetons de `users.fcm_token`, pour que personne ne cesse de
-- recevoir ses notifications au déploiement. Un même jeton sur plusieurs
-- comptes — un téléphone passé de l'un à l'autre — va au compte vu le plus
-- récemment : c'est lui qui est connecté sur l'appareil. Les comptes
-- supprimés n'en reprennent aucun.
INSERT INTO "appareils_notification" ("id", "user_id", "jeton", "vu_le")
SELECT DISTINCT ON ("fcm_token")
       gen_random_uuid()::text, "id", "fcm_token",
       COALESCE("last_seen_at", "last_login_at", "updated_at")
FROM "users"
WHERE "fcm_token" IS NOT NULL AND "fcm_token" <> '' AND "deleted_at" IS NULL
ORDER BY "fcm_token", COALESCE("last_seen_at", "last_login_at", "updated_at") DESC, "id";

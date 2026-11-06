-- Réglages modifiables depuis le panneau d'administration.
--
-- Première utilisation : version et URL de l'APK du canal direct, jusqu'ici
-- figées dans le .env du backend et donc modifiables uniquement par
-- redéploiement. Les variables d'environnement restent le repli : une clé
-- absente de cette table ne change rien au comportement actuel.
CREATE TABLE "app_settings" (
    "key"        TEXT NOT NULL,
    "value"      TEXT NOT NULL,
    "updated_at" TIMESTAMP(3) NOT NULL,
    "updated_by" TEXT,

    CONSTRAINT "app_settings_pkey" PRIMARY KEY ("key")
);

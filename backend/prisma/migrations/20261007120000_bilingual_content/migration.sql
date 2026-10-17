-- Nullable translations: original French content remains the fallback.
ALTER TABLE "pronostics" ADD COLUMN "prediction_label_en" TEXT, ADD COLUMN "analyst_note_en" TEXT;
ALTER TABLE "tutorials" ADD COLUMN "title_en" TEXT, ADD COLUMN "description_en" TEXT, ADD COLUMN "article_content_en" TEXT;
ALTER TABLE "notifications" ADD COLUMN "title_en" TEXT, ADD COLUMN "body_en" TEXT;
ALTER TABLE "appareils_notification" ADD COLUMN "language" TEXT NOT NULL DEFAULT 'fr';

-- Plusieurs pronostics par match (23 novembre 2026).
--
-- `match_id` n'est plus unique : un match peut avoir plusieurs pronostics.
-- Le pronostic principal porte l'id de son match dans `principal_match_id`
-- (unique, donc un seul par match) ; les autres, null. Les pronostics
-- existants deviennent les principaux de leur match.
DROP INDEX "pronostics_match_id_key";

ALTER TABLE "pronostics" ADD COLUMN "principal_match_id" TEXT;

-- Ni colonne figée ni colonne de contenu : le verrou de publication laisse
-- passer cette reprise, et ne la journalise pas.
UPDATE "pronostics" SET "principal_match_id" = "match_id";

CREATE UNIQUE INDEX "pronostics_principal_match_id_key" ON "pronostics"("principal_match_id");

CREATE INDEX "pronostics_match_id_idx" ON "pronostics"("match_id");

ALTER TABLE "pronostics" ADD CONSTRAINT "pronostics_principal_match_id_fkey" FOREIGN KEY ("principal_match_id") REFERENCES "matches"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- Le retrait d'un pronostic publié AVANT le coup d'envoi (publié par erreur,
-- mauvais match) : personne ne l'a encore vu se jouer, il peut partir. La
-- suppression est journalisée (« suppression »), comme toute publication.
-- Après le coup d'envoi, rien ne change : un pronostic publié reste dans
-- l'historique, et son résultat dans le bilan.
CREATE OR REPLACE FUNCTION garder_publication_pronostic() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE cle TEXT; etat_match TEXT;
BEGIN
 IF TG_OP = 'DELETE' THEN
   IF OLD.publication_recorded_at IS NOT NULL THEN
     IF NOT match_pas_commence(OLD.match_id) THEN
       RAISE EXCEPTION 'Un pronostic publié doit rester dans l historique.' USING ERRCODE='23514';
     END IF;
     INSERT INTO pronostic_publication_events(pronostic_id,action,actor,before_state,after_state)
     VALUES (OLD.id,'suppression',nullif(current_setting('pronowin.actor',true),''),
       to_jsonb(OLD)-'publication_snapshot',to_jsonb(OLD)-'publication_snapshot');
   END IF;
   RETURN OLD;
 END IF;
 IF TG_OP = 'UPDATE' AND OLD.publication_recorded_at IS NOT NULL THEN
   IF OLD.result IS NOT NULL AND NEW.result IS NULL THEN
     RAISE EXCEPTION 'Un résultat publié ne peut pas être retiré du bilan ; corrigez son verdict.' USING ERRCODE='23514';
   END IF;
   FOREACH cle IN ARRAY ARRAY[
     'match_id','analyst_id','published_at','publication_recorded_at','publication_snapshot'
   ] LOOP
     IF (to_jsonb(NEW)->cle) IS DISTINCT FROM (to_jsonb(OLD)->cle) THEN
       RAISE EXCEPTION 'Publication figée : % ne peut plus être modifié.', cle USING ERRCODE='23514';
     END IF;
   END LOOP;
   IF NOT match_pas_commence(OLD.match_id) THEN
     FOREACH cle IN ARRAY ARRAY[
       'prediction_type','prediction_label','prediction_label_en',
       'market_name','market_value','odds_home','odds_draw','odds_away','odds_recommended',
       'confidence_score','confidence_pct','analyst_note','analyst_note_en','is_premium'
     ] LOOP
       IF (to_jsonb(NEW)->cle) IS DISTINCT FROM (to_jsonb(OLD)->cle) THEN
         RAISE EXCEPTION 'Le match a commencé : % ne peut plus être modifié.', cle USING ERRCODE='23514';
       END IF;
     END LOOP;
   END IF;
 ELSIF NEW.is_published THEN
   SELECT status::text INTO etat_match FROM matches WHERE id = NEW.match_id;
   IF etat_match IN ('FINISHED','CANCELLED') THEN
     RAISE EXCEPTION 'Impossible de publier après la fin ou l annulation du match.' USING ERRCODE='23514';
   END IF;
   NEW.published_at := CURRENT_TIMESTAMP;
   NEW.publication_recorded_at := CURRENT_TIMESTAMP;
   NEW.publication_snapshot := jsonb_build_object(
     'source','first_publication', 'match_status', etat_match,
     'recorded_at', CURRENT_TIMESTAMP,
     'pronostic', to_jsonb(NEW) - 'publication_snapshot');
 ELSE
   NEW.publication_recorded_at := NULL;
   NEW.publication_snapshot := NULL;
   NEW.published_at := NULL;
 END IF;
 RETURN NEW;
END $$;

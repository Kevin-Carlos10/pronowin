-- Un pronostic publié reste modifiable jusqu'au coup d'envoi (demande du
-- 12 octobre 2026) : sélection, cotes, confiance, analyse et Premium. Chaque
-- modification est journalisée (« modification ») ; dès que le match a
-- commencé, tout est figé comme avant. Le match, l'analyste et la trace de
-- première publication ne changent jamais.
--
-- « Pas commencé » suit la règle des mises de bankroll (verrou_pari.ts) :
-- match programmé et coup d'envoi encore à venir. Un match reporté attend sa
-- nouvelle date.
CREATE FUNCTION match_pas_commence(id_match TEXT) RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT EXISTS (SELECT 1 FROM matches m WHERE m.id = id_match
    AND m.status::text = 'SCHEDULED' AND m.match_date > CURRENT_TIMESTAMP)
$$;

CREATE OR REPLACE FUNCTION garder_publication_pronostic() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE cle TEXT; etat_match TEXT;
BEGIN
 IF TG_OP = 'DELETE' THEN
   IF OLD.publication_recorded_at IS NOT NULL THEN
     RAISE EXCEPTION 'Un pronostic publié doit rester dans l historique.' USING ERRCODE='23514';
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
   -- Ces champs sont gérés par la base, pas par un client.
   NEW.publication_recorded_at := NULL;
   NEW.publication_snapshot := NULL;
   NEW.published_at := NULL;
 END IF;
 RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION journaliser_publication_pronostic() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE avant JSONB; evenement TEXT;
BEGIN
 IF NEW.publication_recorded_at IS NULL THEN RETURN NEW; END IF;
 IF TG_OP = 'INSERT' THEN
   evenement := 'publication';
 ELSE
   avant := to_jsonb(OLD) - 'publication_snapshot';
   IF OLD.publication_recorded_at IS NULL THEN evenement := 'publication';
   ELSIF OLD.result IS DISTINCT FROM NEW.result THEN evenement := 'resultat';
   ELSIF OLD.is_published IS DISTINCT FROM NEW.is_published THEN
     evenement := CASE WHEN NEW.is_published THEN 'reaffichage' ELSE 'retrait' END;
   ELSIF EXISTS (SELECT 1 FROM unnest(ARRAY[
       'prediction_type','prediction_label','prediction_label_en',
       'market_name','market_value','odds_home','odds_draw','odds_away','odds_recommended',
       'confidence_score','confidence_pct','analyst_note','analyst_note_en','is_premium'
     ]) AS c(cle) WHERE (to_jsonb(NEW)->c.cle) IS DISTINCT FROM (to_jsonb(OLD)->c.cle)) THEN
     evenement := 'modification';
   ELSE RETURN NEW;
   END IF;
 END IF;
 INSERT INTO pronostic_publication_events(pronostic_id,action,actor,before_state,after_state)
 VALUES (NEW.id,evenement,nullif(current_setting('pronowin.actor',true),''),
   avant,to_jsonb(NEW)-'publication_snapshot');
 RETURN NEW;
END $$;


ALTER TABLE "pronostics" ADD COLUMN "publication_recorded_at" TIMESTAMP(3),
 ADD COLUMN "publication_snapshot" JSONB;

-- Reprise explicite de l'état connu, sans inventer un historique disparu.
UPDATE pronostics p SET publication_recorded_at = CURRENT_TIMESTAMP,
 publication_snapshot = jsonb_build_object(
   'source', 'legacy_current_state', 'recorded_at', CURRENT_TIMESTAMP,
   'pronostic', to_jsonb(p) - 'publication_snapshot' - 'publication_recorded_at')
WHERE is_published OR published_at IS NOT NULL;

CREATE INDEX pronostics_publication_recorded_idx ON pronostics(publication_recorded_at);
CREATE TABLE pronostic_publication_events (
 id BIGSERIAL PRIMARY KEY,
 pronostic_id TEXT NOT NULL,
 action TEXT NOT NULL,
 actor TEXT,
 before_state JSONB,
 after_state JSONB NOT NULL,
 created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX pronostic_publication_events_prono_idx ON pronostic_publication_events(pronostic_id, created_at);

CREATE FUNCTION garder_publication_pronostic() RETURNS trigger LANGUAGE plpgsql AS $$
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
     'match_id','analyst_id','prediction_type','prediction_label','prediction_label_en',
     'market_name','market_value','odds_home','odds_draw','odds_away','odds_recommended',
     'confidence_score','confidence_pct','analyst_note','analyst_note_en','is_premium',
     'published_at','publication_recorded_at','publication_snapshot'
   ] LOOP
     IF (to_jsonb(NEW)->cle) IS DISTINCT FROM (to_jsonb(OLD)->cle) THEN
       RAISE EXCEPTION 'Publication figée : % ne peut plus être modifié.', cle USING ERRCODE='23514';
     END IF;
   END LOOP;
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
CREATE TRIGGER pronostics_publication_guard BEFORE INSERT OR UPDATE OR DELETE ON pronostics
 FOR EACH ROW EXECUTE FUNCTION garder_publication_pronostic();

CREATE FUNCTION journaliser_publication_pronostic() RETURNS trigger LANGUAGE plpgsql AS $$
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
   ELSE RETURN NEW;
   END IF;
 END IF;
 INSERT INTO pronostic_publication_events(pronostic_id,action,actor,before_state,after_state)
 VALUES (NEW.id,evenement,nullif(current_setting('pronowin.actor',true),''),
   avant,to_jsonb(NEW)-'publication_snapshot');
 RETURN NEW;
END $$;
CREATE TRIGGER pronostics_publication_audit AFTER INSERT OR UPDATE ON pronostics
 FOR EACH ROW EXECUTE FUNCTION journaliser_publication_pronostic();

CREATE FUNCTION refuser_mutation_journal_publication() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 RAISE EXCEPTION 'Le journal de publication est append-only.' USING ERRCODE='23514';
END $$;
CREATE TRIGGER journal_publication_immuable BEFORE UPDATE OR DELETE ON pronostic_publication_events
 FOR EACH ROW EXECUTE FUNCTION refuser_mutation_journal_publication();

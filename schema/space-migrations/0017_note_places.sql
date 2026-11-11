-- A note keeps no place: each note's place moves into location history as one point of its device at the note's time.
-- openspec/changes/note-places-in-history

-- The place columns stay, empty and never read: a new table cascades away every note's files, and DROP COLUMN refuses
-- columns the place CHECK names.

-- The moved points send no webhook message: each webhook already got the place inside its note.
DROP TRIGGER relay_outbox_location;

-- A point already there for that device and time stays as it was. A note with no accuracy gives 0, as the phone sends
-- a point whose accuracy it does not know.
INSERT INTO relay_locations (device_id, at, lat, lon, accuracy, place, created_at)
  SELECT device_id, recorded_at, lat, lon, COALESCE(accuracy, 0), place,
    CAST((julianday('now') - 2440587.5) * 86400000 AS INTEGER)
  FROM relay_notes WHERE lat IS NOT NULL AND lon IS NOT NULL
  ON CONFLICT (device_id, at) DO NOTHING;

-- As 0014_nights makes it.
CREATE TRIGGER relay_outbox_location AFTER INSERT ON relay_locations
BEGIN
  INSERT INTO relay_outbox (kind, ref, at, logged_at) VALUES ('location', CAST(new.id AS TEXT), new.at, new.created_at);
END;

-- A note's place is no longer part of the note: a change to it is no note change. Made again before the columns are
-- emptied, so no phone pulls every note again.
DROP TRIGGER relay_note_changes_changed;
CREATE TRIGGER relay_note_changes_changed AFTER UPDATE OF text, edited_at, audio_key ON relay_notes
BEGIN
  DELETE FROM relay_note_changes WHERE note_id = new.id;
  INSERT INTO relay_note_changes (note_id) VALUES (new.id);
END;

UPDATE relay_notes SET lat = NULL, lon = NULL, accuracy = NULL, place = NULL, place_from = NULL
  WHERE lat IS NOT NULL OR lon IS NOT NULL OR accuracy IS NOT NULL OR place IS NOT NULL OR place_from IS NOT NULL;

-- The Pebble app no longer sends to Relay Everything, and no ring note takes a place later from location history: drop
-- its signing secrets, which now guard nothing, and the trigger that logged `note.updated` when a ring note got its
-- place. A `note.updated` row already in the outbox still sends. openspec/changes/remove-pebble-sending
DROP TABLE IF EXISTS relay_device_secrets;
DROP TRIGGER IF EXISTS relay_outbox_note_updated;

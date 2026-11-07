-- Removes Relay Everything's shared tables from before spaces: each person's data is in their own space, and the move
-- is gone. openspec/changes/drop-old-relay-tables. Children before parents, so the foreign-key check finds no orphan.
DROP TABLE IF EXISTS relay_webhook_attempts;
DROP TABLE IF EXISTS relay_webhooks;
DROP TABLE IF EXISTS relay_outbox;
DROP TABLE IF EXISTS relay_chat_saves;
DROP TABLE IF EXISTS relay_chat_messages;
DROP TABLE IF EXISTS relay_chats;
DROP TABLE IF EXISTS relay_locations;
DROP TABLE IF EXISTS relay_health;
DROP TABLE IF EXISTS relay_notes;
DROP TABLE IF EXISTS relay_devices;
DROP TABLE IF EXISTS relay_move_tickets;

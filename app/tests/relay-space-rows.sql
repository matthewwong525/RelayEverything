-- Made-up rows for one person's space, which worker/relay-mcp/tools.test.ts reads. No real person, key or address.
-- Relay: a made-up phone and iPad key with no real token behind either, one turned-off phone, and a day in
-- Toronto (Wednesday 4 November 2026): ring and typed notes, health samples, and the location history that placed them.
INSERT INTO relay_devices (id, name, token_client_id, token_id, created_at, revoked_at) VALUES
  ('d0000000-0000-4000-8000-000000000001', 'Android phone', 'seed-phone.access', 'seed-token-phone', 1793700000000, NULL),
  ('d0000000-0000-4000-8000-000000000002', 'iPad', 'seed-ipad.access', 'seed-token-ipad', 1793700000000, NULL),
  ('d0000000-0000-4000-8000-000000000003', 'Old phone', 'seed-old.access', 'seed-token-old', 1793000000000, 1793600000000);
INSERT INTO relay_locations (device_id, at, lat, lon, accuracy, place, created_at) VALUES
  ('d0000000-0000-4000-8000-000000000001', 1793797200000, 43.6629, -79.3957, 15, 'Harbord St', 1793833200000),
  ('d0000000-0000-4000-8000-000000000001', 1793811600000, 43.6487, -79.3817, 12, 'King St W', 1793833200000),
  ('d0000000-0000-4000-8000-000000000001', 1793829600000, 43.6544, -79.4006, 20, 'Kensington Ave', 1793833200000),
  ('d0000000-0000-4000-8000-000000000001', 1793831400000, 43.6544, -79.4006, 18, 'Kensington Ave', 1793833200000);
INSERT INTO relay_notes
  (id, device_id, source, delivery_id, client_id, text, audio_key, recorded_at, lat, lon, accuracy, place, place_from, created_at)
VALUES
  ('a0000000-0000-4000-8000-000000000001', 'd0000000-0000-4000-8000-000000000002', 'ring', 'seed-delivery-0001', NULL,
   'Call the PCB fab about the second batch.', NULL, 1793797260000, 43.6629, -79.3957, 15, 'Harbord St', 'history', 1793797262000),
  ('a0000000-0000-4000-8000-000000000002', 'd0000000-0000-4000-8000-000000000001', 'typed', NULL, 'seed-note-0001',
   'Lunch idea: test the ring on the streetcar.', NULL, 1793811700000, 43.6487, -79.3817, 12, 'King St W', 'phone', 1793811705000),
  ('a0000000-0000-4000-8000-000000000003', 'd0000000-0000-4000-8000-000000000002', 'ring', 'seed-delivery-0002', NULL,
   'Buy milk and batteries.', NULL, 1793829500000, NULL, NULL, NULL, NULL, NULL, 1793829502000);
INSERT INTO relay_health (device_id, type, start_at, end_at, value, unit, source, created_at) VALUES
  ('d0000000-0000-4000-8000-000000000001', 'sleep', 1793768400000, 1793795400000, 450, 'min', 'com.google.android.apps.fitness', 1793833200000),
  ('d0000000-0000-4000-8000-000000000001', 'steps', 1793797200000, 1793811600000, 5210, 'count', 'com.google.android.apps.fitness', 1793833200000),
  ('d0000000-0000-4000-8000-000000000001', 'steps', 1793811600000, 1793833200000, 3480, 'count', 'com.google.android.apps.fitness', 1793833200000),
  ('d0000000-0000-4000-8000-000000000001', 'heart_rate', 1793800800000, 1793800800000, 68, 'bpm', 'com.google.android.apps.fitness', 1793833200000),
  ('d0000000-0000-4000-8000-000000000001', 'heart_rate', 1793815200000, 1793815200000, 121, 'bpm', 'com.google.android.apps.fitness', 1793833200000),
  ('d0000000-0000-4000-8000-000000000001', 'workout', 1793815200000, 1793817600000, 40, 'min', 'com.google.android.apps.fitness', 1793833200000);

-- Relay chats: a made-up Claude Code chat key and two chats from Wednesday 4 November 2026, one with the AI's summary.
INSERT INTO relay_devices (id, name, token_client_id, token_id, created_at, revoked_at, reaches) VALUES
  ('d0000000-0000-4000-8000-000000000004', 'Laptop', 'seed-laptop.access', 'seed-token-laptop', 1793700000000, NULL, 'chats');
INSERT INTO relay_chats (id, device_id, session_id, app, project, title, started_at, last_at, message_count, created_at) VALUES
  ('c0000000-0000-4000-8000-000000000001', 'd0000000-0000-4000-8000-000000000004', 'seed-session-0001', 'claude-code', 'relay-ring',
   'How thick should the stiffener be?', 1793800800000, 1793801400000, 4, 1793800810000),
  ('c0000000-0000-4000-8000-000000000002', 'd0000000-0000-4000-8000-000000000004', 'seed-session-0002', 'claude-code', 'relay-ring',
   'Fix the webhook signature', 1793815200000, 1793816100000, 3, 1793815210000);
INSERT INTO relay_chat_messages (chat_id, seq, role, text, at) VALUES
  ('c0000000-0000-4000-8000-000000000001', 0, 'you', 'How thick should the stiffener be?', 1793800800000),
  ('c0000000-0000-4000-8000-000000000001', 1, 'step', 'Read pcb/relay.kicad_pcb', 1793800860000),
  ('c0000000-0000-4000-8000-000000000001', 2, 'ai', '0.2 mm steel is enough for a ring this size. Glue it under the battery.', 1793801100000),
  ('c0000000-0000-4000-8000-000000000001', 3, 'you', 'Save the plan for the stiffener to Relay', 1793801400000),
  ('c0000000-0000-4000-8000-000000000002', 0, 'you', 'Fix the webhook signature', 1793815200000),
  ('c0000000-0000-4000-8000-000000000002', 1, 'step', 'Ran: npm test', 1793815800000),
  ('c0000000-0000-4000-8000-000000000002', 2, 'ai', 'The signature now uses the raw body. The tests pass.', 1793816100000);
INSERT INTO relay_chat_saves (id, chat_id, title, text, created_at) VALUES
  ('e0000000-0000-4000-8000-000000000001', 'c0000000-0000-4000-8000-000000000001', 'Stiffener plan',
   'Use a 0.2 mm steel stiffener under the battery, glued, not soldered.', 1793801460000);
-- More health from the phone that day: two weights, of which the evening's is the latest, and one blood pressure reading.
INSERT INTO relay_health (device_id, type, start_at, end_at, value, unit, source, created_at) VALUES
  ('d0000000-0000-4000-8000-000000000001', 'weight', 1793793600000, 1793793600000, 71.8, 'kg', 'com.google.android.apps.fitness', 1793833200000),
  ('d0000000-0000-4000-8000-000000000001', 'weight', 1793840400000, 1793840400000, 71.4, 'kg', 'com.google.android.apps.fitness', 1793840460000),
  ('d0000000-0000-4000-8000-000000000001', 'blood_pressure_systolic', 1793799000000, 1793799000000, 118, 'mmHg', 'com.google.android.apps.fitness', 1793833200000),
  ('d0000000-0000-4000-8000-000000000001', 'blood_pressure_diastolic', 1793799000000, 1793799000000, 76, 'mmHg', 'com.google.android.apps.fitness', 1793833200000);

-- The phone's calendar: a board meeting and a lunch that day, one meeting removed on the phone, and one the next day.
INSERT INTO relay_calendar_events (device_id, event_key, calendar, title, start_at, end_at, all_day, location, notes, url, people,
  removed_at, updated_at, created_at) VALUES
  ('d0000000-0000-4000-8000-000000000001', 'work:board-1:1793804400000', 'Work', 'Board meeting', 1793804400000, 1793808000000, 0,
   'Office, room 2', 'Bring the ring samples.', NULL, '[{"name":"Sam Lee","email":"sam@example.com","organizer":true},{"name":"Ana"}]',
   NULL, 1793700000000, 1793700000000),
  ('d0000000-0000-4000-8000-000000000001', 'home:lunch-1:1793811600000', 'Home', 'Lunch with Sam', 1793811600000, 1793815200000, 0,
   'King St W', NULL, NULL, '[{"name":"Sam Lee"}]', NULL, 1793700000000, 1793700000000),
  ('d0000000-0000-4000-8000-000000000001', 'work:sync-1:1793818800000', 'Work', 'Cancelled sync', 1793818800000, 1793820600000, 0,
   NULL, NULL, NULL, '[]', 1793750000000, 1793750000000, 1793700000000),
  ('d0000000-0000-4000-8000-000000000001', 'work:review-1:1793887200000', 'Work', 'Design review with Sam', 1793887200000, 1793890800000, 0,
   NULL, NULL, 'https://meet.example.com/review', '[]', NULL, 1793700000000, 1793700000000);

-- Relay webhooks: one made-up address at example.com, paused so a preview never sends to it, with notes sent and the
-- health batch waiting. The rows above filled relay_outbox through its triggers: locations 1-3, notes 4-6, health 7-16,
-- calendar 17-20.
INSERT INTO relay_webhooks (id, name, url, secret, kinds, active, sent_seq, last_status, last_sent_at, created_at) VALUES
  ('e0000000-0000-4000-8000-000000000001', 'Example database', 'https://example.com/relay',
   'whsec_c2VlZC1vbmx5LW5vdC1hLXJlYWwtc2VjcmV0LTAwMDA=', '["notes","health"]', 0, 6, 200, 1793829510000, 1793790000000);
INSERT INTO relay_webhook_attempts (webhook_id, at, first_seq, last_seq, type, status, ms, error) VALUES
  ('e0000000-0000-4000-8000-000000000001', 1793790060000, NULL, NULL, 'webhook.test', 200, 182, NULL),
  ('e0000000-0000-4000-8000-000000000001', 1793797270000, 4, 4, 'note.created', 503, 2140, NULL),
  ('e0000000-0000-4000-8000-000000000001', 1793797300000, 4, 4, 'note.created', 200, 164, NULL),
  ('e0000000-0000-4000-8000-000000000001', 1793811710000, 5, 5, 'note.created', 200, 171, NULL),
  ('e0000000-0000-4000-8000-000000000001', 1793829510000, 6, 6, 'note.created', 200, 158, NULL);
-- Relay photos: three made-up photos from the phone that day, two with their place and one with none. tools.test.ts
-- seals a made-up JPEG under each name; the space's own folder is the test person's.
INSERT INTO relay_photos (id, device_id, client_id, taken_at, lat, lon, width, height, bytes, file_key, created_at) VALUES
  ('f0000000-0000-4000-8000-000000000001', 'd0000000-0000-4000-8000-000000000001', 'seed-photo-0001', 1793811900000, 43.6487, -79.3817,
   1600, 1200, 31, 'people/aaaaaaaa-0000-4000-8000-00000000000a/photos/f0000000-0000-4000-8000-000000000001', 1793812000000),
  ('f0000000-0000-4000-8000-000000000002', 'd0000000-0000-4000-8000-000000000001', 'seed-photo-0002', 1793820000000, NULL, NULL,
   1200, 1600, 31, 'people/aaaaaaaa-0000-4000-8000-00000000000a/photos/f0000000-0000-4000-8000-000000000002', 1793820100000),
  ('f0000000-0000-4000-8000-000000000003', 'd0000000-0000-4000-8000-000000000001', 'seed-photo-0003', 1793830000000, 43.6544, -79.4006,
   1600, 900, 31, 'people/aaaaaaaa-0000-4000-8000-00000000000a/photos/f0000000-0000-4000-8000-000000000003', 1793830100000);

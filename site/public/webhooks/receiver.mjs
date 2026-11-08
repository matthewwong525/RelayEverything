// An example Relay Everything webhook receiver: it checks each signature, saves each message in a SQLite file and keeps
// a type it does not know in other_messages. Node 22.13 or later, no packages. Copy it and change it to fit your use.
//
//   RELAY_WEBHOOK_SECRET=whsec_... PORT=8787 DATABASE=relay.sqlite node receiver.mjs
import { createHmac, timingSafeEqual } from 'node:crypto';
import { createServer } from 'node:http';
import { DatabaseSync } from 'node:sqlite';

const secret = Buffer.from((process.env.RELAY_WEBHOOK_SECRET ?? '').replace(/^whsec_/, ''), 'base64');
const db = new DatabaseSync(process.env.DATABASE ?? 'relay.sqlite');
db.exec(`
  CREATE TABLE IF NOT EXISTS notes (id TEXT PRIMARY KEY, source TEXT, text TEXT, recorded_at TEXT, created_at TEXT,
    device_id TEXT, device_name TEXT, lat REAL, lon REAL, place TEXT, audio BLOB);
  CREATE TABLE IF NOT EXISTS health_samples (id INTEGER, device_id TEXT, type TEXT, start TEXT, "end" TEXT,
    value REAL, unit TEXT, source TEXT, PRIMARY KEY (device_id, id));
  CREATE TABLE IF NOT EXISTS location_points (id INTEGER, device_id TEXT, at TEXT, lat REAL, lon REAL,
    accuracy REAL, place TEXT, PRIMARY KEY (device_id, id));
  CREATE TABLE IF NOT EXISTS files (id TEXT PRIMARY KEY, note_id TEXT, name TEXT, content_type TEXT, size INTEGER,
    bytes BLOB);
  CREATE TABLE IF NOT EXISTS calendar_events (id INTEGER PRIMARY KEY, device_id TEXT, key TEXT, status TEXT, calendar TEXT,
    title TEXT, start TEXT, "end" TEXT, all_day INTEGER, location TEXT, notes TEXT, url TEXT, people TEXT);
  CREATE TABLE IF NOT EXISTS photos (id TEXT PRIMARY KEY, device_id TEXT, device_name TEXT, taken_at TEXT, lat REAL,
    lon REAL, width INTEGER, height INTEGER, content_type TEXT, size INTEGER, bytes BLOB);
  CREATE TABLE IF NOT EXISTS other_messages (webhook_id TEXT PRIMARY KEY, type TEXT, body TEXT, received_at TEXT);`);

/** True when the body is signed with this secret and sent in the last 5 minutes. */
function signed(headers, body) {
  const [id, timestamp] = [headers['webhook-id'], headers['webhook-timestamp']];
  if (!id || Math.abs(Date.now() / 1000 - Number(timestamp)) > 300) return false;
  const expected = createHmac('sha256', secret).update(`${id}.${timestamp}.${body}`).digest();
  return String(headers['webhook-signature'] ?? '').split(' ').some(part => {
    const given = Buffer.from(part.replace(/^v1,/, ''), 'base64');
    return part.startsWith('v1,') && given.length === expected.length && timingSafeEqual(given, expected);
  });
}

// Upserts: a retry can send a message again, and the same id updates the same row.
const note = db.prepare(`INSERT INTO notes VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT (id) DO UPDATE SET text = excluded.text,
  lat = excluded.lat, lon = excluded.lon, place = excluded.place, audio = coalesce(excluded.audio, notes.audio)`);
const sample = db.prepare('INSERT OR REPLACE INTO health_samples VALUES (?, ?, ?, ?, ?, ?, ?, ?)');
const point = db.prepare('INSERT OR REPLACE INTO location_points VALUES (?, ?, ?, ?, ?, ?, ?)');
// A note lists its files, then each file's bytes come in their own note.file: a file that never comes stays listed.
const listed = db.prepare('INSERT INTO files VALUES (?, ?, ?, ?, ?, NULL) ON CONFLICT (id) DO NOTHING');
const file = db.prepare(`INSERT INTO files VALUES (?, ?, ?, ?, ?, ?) ON CONFLICT (id) DO UPDATE SET note_id = excluded.note_id,
  name = excluded.name, content_type = excluded.content_type, size = excluded.size, bytes = excluded.bytes`);
const event = db.prepare('INSERT OR REPLACE INTO calendar_events VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)');
const photo = db.prepare('INSERT OR REPLACE INTO photos VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)');
// The same webhook-id again is a retry: it keeps the first row.
const other = db.prepare('INSERT OR IGNORE INTO other_messages VALUES (?, ?, ?, ?)');

function saveNote({ note: { id, source, text, recorded_at, created_at, device, place, audio, attachments = [] } }) {
  note.run(id, source, text, recorded_at, created_at, device.id, device.name, place?.lat ?? null, place?.lon ?? null,
    place?.name ?? null, audio ? Buffer.from(audio.base64, 'base64') : null);
  attachments.forEach(f => listed.run(f.id, id, f.name, f.content_type, f.size));
}

// One way to save each type this receiver knows. A note.updated holds a changed note's latest words.
const handlers = {
  'note.created': saveNote,
  'note.updated': saveNote,
  'note.file': ({ note_id, file: f }) => file.run(f.id, note_id, f.name, f.content_type, f.size, Buffer.from(f.base64, 'base64')),
  'health.samples': ({ samples }) => samples.forEach(s => sample.run(s.id, s.device.id, s.type, s.start, s.end, s.value, s.unit, s.source)),
  'location.points': ({ points }) => points.forEach(p => point.run(p.id, p.device.id, p.at, p.lat, p.lon, p.accuracy, p.place)),
  'calendar.events': ({ events }) => events.forEach(e => event.run(e.id, e.device.id, e.key, e.status, e.calendar, e.title, e.start,
    e.end, Number(e.all_day), e.location, e.notes, e.url, JSON.stringify(e.people))),
  'photo.created': ({ photo: p }) => photo.run(p.id, p.device.id, p.device.name, p.taken_at, p.place?.lat ?? null, p.place?.lon ?? null,
    p.width, p.height, p.content_type, p.size, Buffer.from(p.base64, 'base64')),
  'webhook.test': () => {},
};

function save(id, body) {
  const { type, data } = JSON.parse(body);
  if (Object.hasOwn(handlers, type)) handlers[type](data);
  else other.run(id, type, body, new Date().toISOString());
}

const server = createServer(async (request, response) => {
  const chunks = [];
  for await (const chunk of request) chunks.push(chunk);
  const body = Buffer.concat(chunks).toString('utf8');
  if (request.method !== 'POST' || !signed(request.headers, body)) return response.writeHead(401).end();
  save(request.headers['webhook-id'], body);
  response.writeHead(204).end();
});
server.listen(Number(process.env.PORT ?? 8787), () => console.log(`Relay Everything receiver on http://localhost:${server.address().port}`));

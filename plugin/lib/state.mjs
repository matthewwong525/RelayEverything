// The hooks' files in the shared state folder (lib/config.mjs): the sessions they know, the projects with saving off,
// one lock per send, one-time notices, and a short log that holds only session ids, counts and statuses.
import { appendFileSync, mkdirSync, openSync, closeSync, readFileSync, renameSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

export const SESSION = /^[A-Za-z0-9_-]{8,128}$/;
const LOG_LINES = 200;
const STALE_LOCK = 5 * 60_000;
// A change to sessions.json or off.json takes milliseconds; a lock older than this was left by a hook that died.
const STALE_FILE_LOCK = 10_000;
// The longest a change waits for a file's lock: past STALE_FILE_LOCK, so a dead hook's lock goes first.
const FILE_LOCK_WAIT = 15_000;
const pause = ms => Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
const FORGET = 30 * 24 * 60 * 60_000;

/** The hooks' files in `dir`; `fileLockWait` is for tests. With `make` false, it makes no folder, only to read. */
export function state(dir, now = Date.now, { fileLockWait = FILE_LOCK_WAIT, make = true } = {}) {
  if (make) mkdirSync(join(dir, 'locks'), { recursive: true, mode: 0o700 });
  const file = name => join(dir, name);
  const read = (name, empty) => {
    try {
      return JSON.parse(readFileSync(file(name), 'utf8'));
    } catch {
      return empty;
    }
  };
  // A write goes to a new file first, so a hook that stops halfway leaves the old file whole.
  const write = (name, value) => {
    const next = file(`${name}.${process.pid}.tmp`);
    writeFileSync(next, JSON.stringify(value, null, 1), { mode: 0o600 });
    renameSync(next, file(name));
  };
  // Read, change and write one file while holding its lock, so two chats' hooks never lose each other's change.
  // Only a lock another hook holds is worth a wait: a folder that can't be written fails at once, not at a timeout.
  const locked = (name, change) => {
    const path = file(`${name}.lock`);
    for (const until = Date.now() + fileLockWait; ;) {
      try {
        closeSync(openSync(path, 'wx'));
        break;
      } catch (error) {
        if (error.code !== 'EEXIST') throw error;
        if (Date.now() >= until) throw new Error(`Another hook held ${name} for too long.`);
        try {
          if (Date.now() - statSync(path).mtimeMs > STALE_FILE_LOCK) rmSync(path, { force: true });
        } catch {
          // Let go between the two calls: take it on the next try.
        }
        pause(5);
      }
    }
    try {
      return change();
    } finally {
      rmSync(path, { force: true });
    }
  };
  return {
    sessions: () => read('sessions.json', {}),
    /** Changes one session; `change` is the fields to set, or a function from the session as it is now to them. */
    update(id, change) {
      return locked('sessions.json', () => {
        const kept = Object.entries(read('sessions.json', {})).filter(([, item]) => now() - (item.seen ?? 0) < FORGET);
        const all = Object.fromEntries(kept);
        all[id] = { ...all[id], ...(typeof change === 'function' ? change(all[id] ?? {}) : change) };
        write('sessions.json', all);
        return all[id];
      });
    },
    isOff: root => read('off.json', []).includes(root),
    setOff(root, off) {
      locked('off.json', () => {
        const others = read('off.json', []).filter(item => item !== root);
        write('off.json', off ? [...others, root] : others);
      });
    },
    /** True once `name` was marked: a notice that shows only once. */
    marked: name => read('marks.json', []).includes(name),
    mark(name) {
      locked('marks.json', () => {
        const marks = read('marks.json', []);
        if (!marks.includes(name)) write('marks.json', [...marks, name]);
      });
    },
    /** Takes the session's lock, or answers null while another send holds it; call the answer to let go. */
    lock(id) {
      const path = file(join('locks', `${id}.lock`));
      try {
        if (Date.now() - statSync(path).mtimeMs > STALE_LOCK) rmSync(path, { force: true });
      } catch {
        // No lock yet.
      }
      try {
        closeSync(openSync(path, 'wx'));
      } catch (error) {
        if (error.code === 'EEXIST') return null;
        throw error;
      }
      return () => rmSync(path, { force: true });
    },
    log(line) {
      appendFileSync(file('send.log'), `${new Date(now()).toISOString()} ${line}\n`, { mode: 0o600 });
      const lines = readFileSync(file('send.log'), 'utf8').split('\n').filter(Boolean);
      if (lines.length > LOG_LINES) writeFileSync(file('send.log'), `${lines.slice(-LOG_LINES).join('\n')}\n`);
    },
  };
}

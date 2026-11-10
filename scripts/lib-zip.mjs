// A small zip writer and reader for the Relay Everything page's release file, so CI and a self-hosted install need
// no zip tool. It reads the zips it writes: deflate only, with no zip64, so each file and the zip stay under 4 GB.
import { crc32, deflateRawSync, inflateRawSync } from 'node:zlib';

const LOCAL = 0x04034b50;
const CENTRAL = 0x02014b50;
const END = 0x06054b50;
// Names are UTF-8, and every file is dated 1980-01-01, so the same files make the same zip.
const UTF8 = 0x0800;
const DATE = (1 << 5) | 1;

/** One zip of `[name, data]` pairs, each name a relative path with forward slashes. */
export function zip(entries) {
  const parts = [];
  const directory = [];
  let offset = 0;
  for (const [name, data] of entries) {
    const path = Buffer.from(name);
    const packed = deflateRawSync(data);
    const local = Buffer.alloc(30);
    local.writeUInt32LE(LOCAL, 0);
    local.writeUInt16LE(20, 4);
    local.writeUInt16LE(UTF8, 6);
    local.writeUInt16LE(8, 8);
    local.writeUInt16LE(DATE, 12);
    local.writeUInt32LE(crc32(data), 14);
    local.writeUInt32LE(packed.length, 18);
    local.writeUInt32LE(data.length, 22);
    local.writeUInt16LE(path.length, 26);
    const central = Buffer.alloc(46);
    central.writeUInt32LE(CENTRAL, 0);
    central.writeUInt16LE(20, 4);
    central.writeUInt16LE(20, 6);
    local.copy(central, 8, 6, 30);
    central.writeUInt32LE(offset, 42);
    parts.push(local, path, packed);
    directory.push(central, path);
    offset += local.length + path.length + packed.length;
  }
  const listing = Buffer.concat(directory);
  const end = Buffer.alloc(22);
  end.writeUInt32LE(END, 0);
  end.writeUInt16LE(entries.length, 8);
  end.writeUInt16LE(entries.length, 10);
  end.writeUInt32LE(listing.length, 12);
  end.writeUInt32LE(offset, 16);
  return Buffer.concat([...parts, listing, end]);
}

/** The files in a zip, as `[name, data]` pairs. Throws on a name that leaves the folder it is
 *  unpacked into, on a kind of compression other than deflate, and on a file whose checksum is wrong. */
export function unzip(data) {
  const end = data.lastIndexOf(Buffer.from([0x50, 0x4b, 0x05, 0x06]));
  if (end < 0) throw new Error('not a zip file');
  const files = [];
  let at = data.readUInt32LE(end + 16);
  for (let count = data.readUInt16LE(end + 10); count > 0; count -= 1) {
    if (data.readUInt32LE(at) !== CENTRAL) throw new Error('a broken zip file');
    const method = data.readUInt16LE(at + 10);
    const sum = data.readUInt32LE(at + 16);
    const size = data.readUInt32LE(at + 20);
    const nameLength = data.readUInt16LE(at + 28);
    const name = data.toString('utf8', at + 46, at + 46 + nameLength);
    const local = data.readUInt32LE(at + 42);
    at += 46 + nameLength + data.readUInt16LE(at + 30) + data.readUInt16LE(at + 32);
    if (/^[/\\]|\\|(^|\/)\.\.(\/|$)/.test(name)) throw new Error(`the zip names a file outside its folder: ${name}`);
    if (method !== 8) throw new Error(`${name} uses a compression this reader does not know`);
    const start = local + 30 + data.readUInt16LE(local + 26) + data.readUInt16LE(local + 28);
    const packed = data.subarray(start, start + size);
    const file = inflateRawSync(packed);
    if (crc32(file) !== sum) throw new Error(`${name} is damaged in the zip`);
    files.push([name, file]);
  }
  return files;
}

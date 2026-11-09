// Run with: node --test mobile/device-check/*.test.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { crashSummary, crashText, readIps } from './crash.mjs';

// A Runner crash from run 42537544439, cut down to the parts crash.mjs reads: the voice note's Metal crash.
const SAMPLE = readFileSync(new URL('./crash.sample.ips', import.meta.url), 'utf8');

test('the summary gives the exception, the signal, the termination and the first 8 frames', () => {
  const lines = crashSummary(readIps(SAMPLE)).split('\n');
  assert.equal(lines[0], 'The app crashed: EXC_BREAKPOINT (SIGTRAP)');
  assert.equal(lines[1], 'Ended by: SIGNAL Trace/BPT trap: 5');
  assert.equal(lines[2], 'Crashed thread (DartWorker):');
  assert.deepEqual(lines.slice(3), [
    '  0 libxpc.dylib  _xpc_api_misuse',
    '  1 libxpc.dylib  _xpc_shmem_create_with_prot.cold.1',
    '  2 libxpc.dylib  _xpc_shmem_create_with_prot',
    '  3 MTLSimDriver  -[MTLSimDevice newBufferWithLength:options:pointer:copyBytes:deallocator:]',
    '  4 Runner.debug.dylib  ggml_metal_buffer_set_tensor',
    '  5 Runner.debug.dylib  whisper_init_with_params_no_state',
    '  6 Runner.debug.dylib  whisper_init_from_file_with_params_no_state',
    '  7 Runner.debug.dylib  whisper_init_from_file_with_params',
  ]);
});

test('a frame with no symbol or image name gives its offset', () => {
  const body = { faultingThread: 0, threads: [{ frames: [{ imageOffset: 255, imageIndex: 0 }] }], usedImages: [{}] };
  assert.match(crashSummary({ body }), /0 \?\?\? {2}0xff$/);
});

test('the oldest report comes first, the rest are counted, and an unreadable one is still a crash', () => {
  const text = crashText([
    { name: 'Runner-2026-11-09-002231.ips', text: SAMPLE },
    { name: 'Runner-2026-11-09-002109.ips', text: 'not json' },
  ]);
  assert.match(text, /^The app crashed: crashes\/Runner-2026-11-09-002109\.ips \(the report can't be read\)\./);
  assert.match(text, /\n1 more crash report in crashes\/\.$/);
  assert.equal(crashText([]), '');
});

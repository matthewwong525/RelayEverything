// Loaded before the copy's chat start, in its own variables and folder: memory's daily tidy stays off, because Relay
// Everything's daily build is the one daily job. The start's capture still runs. A failure leaves the start as it is.
import { readDaily, setDaily } from '../memory/scripts/lib/daily.mjs';
import { repoContext } from '../memory/scripts/lib/store.mjs';

try {
  const ctx = repoContext(process.cwd());
  if (!readDaily(ctx).off) setDaily(ctx, { off: true });
} catch { /* outside git memory does not run */ }

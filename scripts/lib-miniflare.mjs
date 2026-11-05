// Miniflare for the scripts' tests, from the app's own packages: the scripts folder installs none.
import { createRequire } from 'node:module';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { repoRoot } from './lib-wrangler-config.mjs';

/** A Miniflare factory that takes one Worker's options in the classic shape; run `npm ci` in app/ first. */
export async function miniflare() {
  const path = createRequire(join(repoRoot, 'app', 'package.json')).resolve('miniflare');
  const module = await import(pathToFileURL(path).href);
  const { Miniflare, convertV4MiniflareOptions: convert } = module.Miniflare ? module : module.default;
  // cf: false: no download of request.cf data, and no cache folder left at the repository root.
  return options => new Miniflare(convert ? convert({ cf: false, ...options }) : { cf: false, ...options });
}

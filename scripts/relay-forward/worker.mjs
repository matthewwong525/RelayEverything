// The old relay-ring address for 30 days after the move: it passes each request on to the new site, which checks the
// device's key again. openspec/changes/relay-everything-cloudflare-rename/design.md#the-30-day-forwarder

/** The old Access app's own sign-in, which the new site refuses: the new address's Access signs its own. */
const DROPPED = new Set(['cf-access-jwt-assertion', 'cf-access-authenticated-user-email', 'cookie', 'host']);
// Cloudflare's own request headers, set again on the new request; the device's service-token pair goes on.
const KEPT_CF = new Set(['cf-access-client-id', 'cf-access-client-secret']);

/** The request's headers for the new address. */
export function forwardHeaders(headers) {
  const out = new Headers();
  for (const [name, value] of headers) {
    if (DROPPED.has(name) || (name.startsWith('cf-') && !KEPT_CF.has(name))) continue;
    out.append(name, value);
  }
  return out;
}

/** A browser opening a page. A send never gets a redirect: the phone's and the Pebble's clients don't follow one. */
const pageLoad = request => request.method === 'GET' && !request.headers.has('upgrade') && (request.headers.get('accept') ?? '').includes('text/html');

export default {
  async fetch(request, env) {
    if (env.MODE === 'hold') {
      return new Response('Relay Everything is moving; try again in a minute.\n', {
        status: 503, headers: { 'Retry-After': '60', 'Content-Type': 'text/plain; charset=utf-8', 'Cache-Control': 'no-store' },
      });
    }
    const url = new URL(request.url);
    const target = new URL(`${url.pathname}${url.search}`, env.TARGET);
    if (pageLoad(request)) return Response.redirect(target.href, 308);
    const hasBody = !['GET', 'HEAD'].includes(request.method);
    return fetch(target.href, { method: request.method, headers: forwardHeaders(request.headers), body: hasBody ? request.body : null, redirect: 'manual' });
  },
};

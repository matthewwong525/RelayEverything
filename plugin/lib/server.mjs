// Calls to the computer's own Relay Everything server, with its key: the chat routes on the server, and the web API
// at the key's `api` address.
const WAIT = 30_000;

async function call(url, key, { method = 'GET', body, fetcher = fetch, wait = WAIT }) {
  const response = await fetcher(url, {
    method,
    headers: { ...(body === undefined ? {} : { 'content-type': 'application/json' }), Authorization: `Bearer ${key}` },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    signal: AbortSignal.timeout(wait),
  });
  const json = await response.json().catch(() => null);
  return { status: response.status, json };
}

/** Posts JSON to one chat route of the computer's server, and answers the status and the JSON body. */
export const post = (computer, route, body, fetcher = fetch) =>
  call(`${computer.server}/apps/relay/api/${route}`, computer.key, { method: 'POST', body, fetcher });

/** Calls one web API route, such as `/notes`, with a query of text fields or a JSON body. */
export function api(computer, path, { query = {}, body, fetcher = fetch, wait = WAIT } = {}) {
  const search = new URLSearchParams(Object.entries(query).filter(([, value]) => value !== undefined)).toString();
  return call(`${computer.api}${path}${search ? `?${search}` : ''}`, computer.key, { method: body === undefined ? 'GET' : 'POST', body, fetcher, wait });
}

/** The chat ids that facts name in their sources, such as `relay:chat/7f3a#120`, in the facts' order. */
export const chatIds = facts => [...new Set((facts ?? []).flatMap(fact => fact?.sources ?? [])
  .map(source => /^relay:chat\/([^#\s]+)/.exec(String(source))?.[1]).filter(Boolean))];

/** The server's own words for a refusal: the web API sends `{ error, error_description }`, the app's routes
 *  `{ error: { code, message } }`. Null when it sent neither. */
export function reason(json) {
  const why = json?.error_description ?? json?.error?.message;
  return typeof why === 'string' && why ? why : null;
}

// The connect code that *Add a device* on the Relay Everything page shows: the only place a server address comes from.
const SERVER = /^https:\/\/[^/\s?#@]+$/;
const KEY = /^rek_[A-Za-z0-9_-]{43}$/;

/** `{ server, key }` from a connect code, or null for anything else. */
export function parseCode(text) {
  let code;
  try {
    code = JSON.parse(String(text ?? '').trim());
  } catch {
    return null;
  }
  if (code?.relay !== 1 || !SERVER.test(code.server ?? '') || !KEY.test(code.key ?? '')) return null;
  return { server: code.server, key: code.key };
}

/** The connect code as the plugin gets it: from a hook's option, or from the save tool's own setting. */
export const codeFrom = env => parseCode(env.CLAUDE_PLUGIN_OPTION_CONNECT_CODE || env.RELAY_CONNECT_CODE);

/** Posts JSON to one route of the code's own server, with its key, and answers the status and the JSON body. */
export async function post(code, route, body, fetcher = fetch) {
  const response = await fetcher(`${code.server}/apps/relay/api/${route}`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', Authorization: `Bearer ${code.key}` },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(30_000),
  });
  const json = await response.json().catch(() => null);
  return { status: response.status, json };
}

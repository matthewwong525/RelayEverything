// The connect code that `relay-device-key.mjs create --for claude-code` prints: the only place a server address comes from.
const SERVER = /^https:\/\/[^/\s?#@]+$/;
const PART = /^[^\s]{1,512}$/;

/** `{ server, clientId, clientSecret }` from a connect code, or null for anything else. */
export function parseCode(text) {
  let code;
  try {
    code = JSON.parse(String(text ?? '').trim());
  } catch {
    return null;
  }
  if (code?.relay !== 1 || !SERVER.test(code.server ?? '') || !PART.test(code.clientId ?? '') || !PART.test(code.clientSecret ?? '')) {
    return null;
  }
  return { server: code.server, clientId: code.clientId, clientSecret: code.clientSecret };
}

/** The connect code as the plugin gets it: from a hook's option, or from the save tool's own setting. */
export const codeFrom = env => parseCode(env.CLAUDE_PLUGIN_OPTION_CONNECT_CODE || env.RELAY_CONNECT_CODE);

/** Posts JSON to one route of the code's own server, with its key, and answers the status and the JSON body. */
export async function post(code, route, body, fetcher = fetch) {
  const response = await fetcher(`${code.server}/apps/relay/api/${route}`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', 'CF-Access-Client-Id': code.clientId, 'CF-Access-Client-Secret': code.clientSecret },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(30_000),
  });
  const json = await response.json().catch(() => null);
  return { status: response.status, json };
}

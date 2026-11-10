// A static mini app's page (app.json "static": true) is the files in public/apps/<name>/, as built. An address in it
// that names no file gets the page's index.html, so a link into the page opens it. wiki/stack/mini-apps.md
const IN_APP = /^\/apps\/([^/]+)\/(.*)$/;

/** The answer for a static app's address, or null when the address is in none of `names`. */
export function staticPage(request: Request, assets: Fetcher, names: readonly string[]): Promise<Response> | null {
  const url = new URL(request.url);
  const [, name = "", rest = ""] = IN_APP.exec(url.pathname) ?? [];
  if (!names.includes(name)) return null;
  if (rest === "" || /\.[^/]*$/.test(rest)) return assets.fetch(request);
  return assets.fetch(new Request(new URL(`/apps/${name}/${url.search}`, url), request));
}

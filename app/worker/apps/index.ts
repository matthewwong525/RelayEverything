// Every mini app's server side: /apps/<name>/api/<route> goes to the handler `apps/<name>/api.ts` lists for
// "<METHOD> <route>". Vite finds each api.ts at build time, so a new app needs no edit here. wiki/stack/mini-apps.md
import { dispatch, keyUses, registrations, type Route } from "../api/contract.ts";
import type { AccessIdentity } from "../access.ts";
import type { KeyId } from "../keys.ts";
import { hasScreen } from "../employee-access/catalogue.ts";
import { knowledgeReader, type KnowledgeReader } from "../employee-access/knowledge-reader.ts";
import type { PolicyEnv, RouteAccess } from "../employee-access/policy.ts";

// The memory store and the sign-in list key: a mini app is handed neither.
type MemoryBindings = "MEMORY_DB" | "MEMORY_BUCKET" | "WONG_ACCESS_LOGIN_MANAGEMENT";

/** Everything the Worker has but the memory store: the database, settings, and the route's saved keys. @public */
export type AppEnv = Omit<Env, MemoryBindings> & PolicyEnv;

/** What a handler knows about its call. `identity` is null only on an open workspace. Only the Knowledge app's
 *  routes get `knowledge`, its read-only reader, and none of them the binding behind it. @public */
export type AppCall = { url: URL; route: string; identity: AccessIdentity | null; knowledge?: KnowledgeReader | null };

/** One route's handler, in an app's api.ts. A bare handler may list its own saved keys, like an action. @public */
export type AppHandler = ((request: Request, env: AppEnv, call: AppCall) => Response | Promise<Response>) & { keys?: readonly KeyId[] };

/** An address the app API answers: /apps/<name>/api, then a route. */
export const APP_API = /^\/apps\/([^/]+)\/api(?:\/(.*))?$/;

/** A queue consumer an app's api.ts lists in `queues`, keyed by the queue's name without `-staging`. @public */
export type AppConsumer = (batch: MessageBatch, env: AppEnv) => Promise<void>;

// Each app's routes, keyed "METHOD route", and the saved keys its api.ts exports as `keys`, for routes that list none.
// Maps, not objects, so a route or an app named `constructor` can't reach a property every object inherits.
type AppModule = { routes: Map<string, Route>; keys?: readonly string[]; queues?: Map<string, AppConsumer>;
  scheduled?: (env: AppEnv) => Promise<void> };
const apps = new Map(
  Object.entries(import.meta.glob<AppModule>("./*/api.ts", { eager: true })).map(
    ([path, module]) => [path.split("/")[1], module],
  ),
);

/** A folder with no screen is no app: each route belongs to the saved keys it lists, and the caller's level decides.
 *  Throws when the Worker loads, naming the file and both fixes, where a route lists none: nothing would guard it. */
export function keysAlone(name: string, { routes, keys = [] }: AppModule): ReadonlyMap<string, RouteAccess> {
  for (const [key, route] of routes) {
    if (!(route.keys ?? keys).length) {
      throw new Error(`app/worker/apps/${name}/api.ts: "${key}" has no screen and lists no saved key, so nothing guards it. ` +
        `Give the folder a screen at app/src/apps/${name}/app.json, or list the saved key the route uses.`);
    }
  }
  return new Map([...routes.keys()].map(key => [key, { keys }]));
}

// The mapping of each folder with no screen. A folder with one is an app: its routes ask for the app.
const alone = new Map([...apps].filter(([name]) => !hasScreen(name)).map(([name, module]) => [name, keysAlone(name, module)]));

export const appActions = [...apps].flatMap(([name, { routes, keys }]) => registrations(routes, name, alone.get(name), keys));
export const appKeyUse = [...apps].flatMap(([name, { routes, keys }]) => keyUses(routes, name, alone.get(name), keys));

/** The Worker's bindings without the memory store's and the sign-in list key. */
function appEnvOf(env: Env & PolicyEnv): AppEnv {
  // Typed so the copy compiles before setup binds a memory store, too.
  const appEnv: AppEnv & Partial<Record<MemoryBindings, unknown>> = { ...env };
  delete appEnv.MEMORY_DB;
  delete appEnv.MEMORY_BUCKET;
  delete appEnv.WONG_ACCESS_LOGIN_MANAGEMENT;
  return appEnv;
}

/** Answer an app API call. The handler's env copy lacks the memory store's bindings and holds only its route's saved
 *  keys; the `disallow_importable_env` flag stops it importing the rest. That stops mistakes, not determined code. */
export function handleApp(request: Request, env: Env & PolicyEnv, identity: AccessIdentity | null): Response | Promise<Response> {
  const url = new URL(request.url);
  const [, name = "", route = ""] = APP_API.exec(url.pathname) ?? [];
  const app = apps.get(name);
  const handler = app?.routes.get(`${request.method} ${route}`);
  if (!handler) return Response.json({ error: "Not found" }, { status: 404 });

  const appEnv = appEnvOf(env);
  const call: AppCall = name === "knowledge" ? { url, route, identity, knowledge: knowledgeReader(env) } : { url, route, identity };
  return dispatch(handler, request, appEnv, call,
    alone.get(name)?.get(`${request.method} ${route}`) ?? { apps: [name], keys: app!.keys });
}

/** Hand a queue's batch to the app that lists it, with the same env as a route. A queue no app lists is acked, so its
 *  messages don't come back. The staging Worker's queues end in `-staging`; the local ones in `-local`. */
export async function handleAppQueue(batch: MessageBatch, env: Env & PolicyEnv) {
  const name = batch.queue.replace(/-(?:staging|local)$/, "");
  const consumer = [...apps.values()].map(app => app.queues?.get(name)).find(Boolean);
  if (!consumer) {
    console.error(`No app lists the queue ${batch.queue}; its messages are dropped.`);
    batch.ackAll();
    return;
  }
  await consumer(batch, appEnvOf(env));
}

/** Run each app's `scheduled` export, on the Worker's schedule. One app's failure doesn't stop the next. */
export async function handleAppSchedule(env: Env & PolicyEnv) {
  for (const [name, app] of apps) {
    try {
      await app.scheduled?.(appEnvOf(env));
    } catch (error) {
      console.error(`The ${name} app's schedule failed`, error);
    }
  }
}

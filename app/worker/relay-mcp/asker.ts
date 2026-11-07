// The connector's door into a person's space: a grant the OAuth provider checked, or an API key caller.ts checked,
// becomes that space and what the caller may do there. space-access.test.ts lists this file. wiki/relay-spaces.md
import { spaceOf, vouch, type Caller, type SpaceEnv } from "../apps/relay/space.ts";
import type { Asker } from "./answers.ts";
import type { GrantProps, McpEnv } from "./env.ts";

type Bindings = Pick<McpEnv, "SPACES" | "RELAY_WEBHOOKS" | "RELAY_GOOGLE_CLIENT_ID" | "RELAY_GOOGLE_SIGN_IN_SECRET">;

// The connector reads no recording, so it binds no file store.
const open = (env: Bindings, caller: Caller) => spaceOf({ SPACES: env.SPACES } as SpaceEnv, caller);

/** A grant's person, its device if its consent page said it adds notes, and Google if that page named it. Null for
 *  a grant from before spaces, which names no person: its app must connect again. */
export function grantAsker(env: Bindings, props: GrantProps | undefined): Asker | null {
  if (!props?.personId) return null;
  const { adds, deviceId, name } = props;
  return { space: open(env, vouch("grant", props.personId)), env, google: props.google === true,
    adder: adds && deviceId && name ? { deviceId, name, kind: "app" } : null };
}

/** An API key's person, from the caller caller.ts vouched for: it adds as its own device, and reaches Google. */
export const keyAsker = (env: Bindings, caller: Caller & { device: { id: string } }): Asker =>
  ({ space: open(env, caller), env, google: true, adder: { deviceId: caller.device.id, name: "", kind: "api" } });

export const APP_DEVICE_OFF = "UPDATE relay_devices SET revoked_at = coalesce(revoked_at, ?) WHERE id = ? AND reaches = 'app'";

/** Turns off a disconnected app's device row, so its notes show it off; a row it never made stays absent. */
export async function appDeviceOff(env: Bindings, personId: string, deviceId: string) {
  await open(env, vouch("grant", personId)).db.prepare(APP_DEVICE_OFF).bind(Date.now(), deviceId).run();
}

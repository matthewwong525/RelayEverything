// The connector's door into a person's space: a grant the OAuth provider checked, or an API key caller.ts checked,
// becomes that space and what the caller may do there. space-access.test.ts lists this file. wiki/relay-spaces.md
import { spaceOf, vouch, type Caller, type SpaceEnv } from "../apps/relay/space.ts";
import type { Asker } from "./answers.ts";
import type { GrantProps, McpEnv } from "./env.ts";

/** The spaces, the file store and the webhooks' queue. */
export type Bindings = SpaceEnv & Pick<McpEnv, "RELAY_WEBHOOKS">;

// The file store is there for read_photo, which opens one photo by its row: no answer reads a recording.
const open = (env: Bindings, caller: Caller) => spaceOf(env, caller);

/** A grant's person and, for an app whose consent page said it can add notes, its device. Null for a grant from
 *  before spaces, which names no person: its app must connect again. */
export function grantAsker(env: Bindings, props: GrantProps | undefined): Asker | null {
  if (!props?.personId) return null;
  const { adds, deviceId, name } = props;
  return { space: open(env, vouch("grant", props.personId)), env,
    adder: adds && deviceId && name ? { deviceId, name, kind: "app" } : null };
}

/** An API key's person, from the caller caller.ts vouched for: it adds as its own device. */
export const keyAsker = (env: Bindings, caller: Caller & { device: { id: string } }): Asker =>
  ({ space: open(env, caller), env, adder: { deviceId: caller.device.id, name: "", kind: "api" } });

export const APP_DEVICE_OFF = "UPDATE relay_devices SET revoked_at = coalesce(revoked_at, ?) WHERE id = ? AND reaches = 'app'";

/** Turns off a disconnected app's device row, so its notes show it off; a row it never made stays absent. */
export async function appDeviceOff(env: Bindings, personId: string, deviceId: string) {
  await open(env, vouch("grant", personId)).db.prepare(APP_DEVICE_OFF).bind(Date.now(), deviceId).run();
}

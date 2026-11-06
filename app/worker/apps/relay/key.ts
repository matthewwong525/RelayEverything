// GET key: a device checks its own key. It answers the key's device name and nothing else, so a send-only key can
// check itself without reading any data.
import { z } from "zod";
import { defineAction, type ActionCall } from "../../api/contract.ts";
import { asDevice } from "./caller.ts";

export const key = defineAction({
  operationId: "relay.key", summary: "Check a device key",
  description: "Check the calling device key: answers the name it was made with, and no data.",
  input: z.strictObject({}), output: z.strictObject({ device: z.string().describe("The key's device name.") }),
  encoding: "none", effect: "read", agentAvailable: false, requiresIdentity: false, errors: {}, examples: [],
  handler: asDevice<ActionCall>("Only a Relay Everything device key can check itself.", async ({ space, device }) => {
    const row = await space.db.prepare("SELECT name FROM relay_devices WHERE id = ?").bind(device.id).first<{ name: string }>();
    return Response.json({ device: row?.name ?? "" });
  }),
});

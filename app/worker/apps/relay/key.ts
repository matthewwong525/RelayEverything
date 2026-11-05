// GET key: a device checks its own key. It answers the key's device name and nothing else, so a send-only key can
// check itself without reading any data.
import { z } from "zod";
import { defineAction } from "../../api/contract.ts";
import { deviceOf } from "./device.ts";
import { refused } from "./store.ts";

export const key = defineAction({
  operationId: "relay.key", summary: "Check a device key",
  description: "Check the calling device key: answers the name it was made with, and no data.",
  input: z.strictObject({}), output: z.strictObject({ device: z.string().describe("The key's device name.") }),
  encoding: "none", effect: "read", agentAvailable: false, errors: {}, examples: [],
  async handler(_request, env, { identity }) {
    const device = await deviceOf(env, identity);
    return device ? Response.json({ device: device.name }) : refused(403, "Only a Relay device key can check itself.");
  },
});

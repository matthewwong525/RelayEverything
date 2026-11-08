import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { stripJsonc } from "../../scripts/lib-wrangler-config.mjs";

// A space's 15-minute catch-up sends a wake-up on its queue; only a Worker that binds SPACES can open the space.
// So in each environment, some Worker of the same environment consumes that queue and binds SPACES.

type Block = {
  queues?: { producers?: { queue: string }[]; consumers?: { queue: string }[] };
  durable_objects?: { bindings?: { name: string }[] };
};
type Config = Block & { env?: Record<string, Block> };

const read = (name: string): Config => JSON.parse(stripJsonc(readFileSync(new URL(`../${name}`, import.meta.url), "utf8")));
const CONSUMERS = ["wrangler.jsonc", "wrangler.relay.jsonc"];

// An environment inherits no binding, so each block names its own queues and objects.
const block = (config: Config, env: string | null): Block | undefined => (env ? config.env?.[env] : config);

/** One line per spaces environment whose queue no SPACES-binding Worker of that environment consumes. */
function unpaired(spaces: Config, consumers: Record<string, Config>): string[] {
  return [null, ...Object.keys(spaces.env ?? {})].flatMap(env => {
    const queues = (block(spaces, env)?.queues?.producers ?? []).map(producer => producer.queue);
    return queues.filter(queue => !Object.values(consumers).some(config => {
      const other = block(config, env);
      return other?.queues?.consumers?.some(consumer => consumer.queue === queue)
        && other.durable_objects?.bindings?.some(binding => binding.name === "SPACES");
    })).map(queue => `${env ?? "production"}: ${queue} has no consumer that binds SPACES`);
  });
}

const consumers = () => Object.fromEntries(CONSUMERS.map(name => [name, read(name)]));

describe("the spaces Worker's catch-up queue", () => {
  it("reaches a Worker that binds SPACES in every environment", () => {
    expect(unpaired(read("wrangler.spaces.jsonc"), consumers())).toEqual([]);
  });

  it("names the environment and queue when staging points at the company app's staging queue", () => {
    const spaces = read("wrangler.spaces.jsonc");
    spaces.env!.staging.queues = { producers: [{ queue: "relay-everything-webhooks-staging" }] };
    expect(unpaired(spaces, consumers())).toEqual(["staging: relay-everything-webhooks-staging has no consumer that binds SPACES"]);
  });

  it("fails when no Worker consumes the queue", () => {
    const spaces: Config = { queues: { producers: [{ queue: "nobody-reads-this" }] } };
    expect(unpaired(spaces, consumers())).toEqual(["production: nobody-reads-this has no consumer that binds SPACES"]);
  });
});

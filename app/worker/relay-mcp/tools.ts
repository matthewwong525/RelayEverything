// The connector's tools over one person's notes, health, places, points, calendar, chats and photos: fourteen that
// only read, and one that adds a typed note. Answers come from answers.ts, as the web API's do; inputs, from inputs.ts.
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { WebStandardStreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/webStandardStreamableHttp.js";
import { answer, Picture, Refusal, type Asker } from "./answers.ts";
import { grantAsker, type Bindings } from "./asker.ts";
import type { GrantProps } from "./env.ts";
import { TOOLS, type ToolName } from "./inputs.ts";
import { ZONE } from "./time.ts";

type Answer = { content: ({ type: "text"; text: string } | { type: "image"; data: string; mimeType: string })[]; isError?: boolean };

/** Runs a tool, and answers a refusal as a tool error the AI can read and correct. */
const tool = (name: ToolName, asker: Asker) => async (input: object): Promise<Answer> => {
  try {
    const answered = await answer(name, asker, input as never);
    if (answered instanceof Picture) {
      return { content: [{ type: "image", data: answered.data, mimeType: answered.mimeType }, { type: "text", text: answered.text }] };
    }
    return { content: [{ type: "text", text: JSON.stringify(answered) }] };
  } catch (error) {
    if (!(error instanceof Refusal)) throw error;
    return { content: [{ type: "text", text: error.message }], isError: true };
  }
};

const readOnly = { readOnlyHint: true, destructiveHint: false, openWorldHint: false };
const adds = { readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false };

/** A fresh server per request: the connector keeps no session between calls. */
function relayServer(asker: Asker): McpServer {
  const server = new McpServer({ name: "relay", title: "Relay Everything", version: "1.1.0" }, {
    instructions: "Relay Everything holds one person's notes from their phone, with health, sleep, workouts, places and calendar, the " +
      "Claude Code chats they saved, and the photos their phone sent. points gives the route of a stay or trip that places lists. " +
      "Every tool but add_note only reads; add_note adds a typed note " +
      `when the person asks you to save one, and nothing changes or deletes. Days and times are ${ZONE} unless you pass a timezone.`,
  });
  for (const [name, { title, description, input }] of Object.entries(TOOLS) as [ToolName, (typeof TOOLS)[ToolName]][]) {
    server.registerTool(name, { title, description, inputSchema: input, annotations: name === "add_note" ? adds : readOnly }, tool(name, asker));
  }
  return server;
}

/** The connector's /mcp: Streamable HTTP, answered as JSON, with no session. Each token reaches only its grant's
 *  person's space; a grant from before spaces names no person, so its app must connect again. */
export const mcpHandler = {
  async fetch(request: Request, env: Bindings, ctx: Pick<ExecutionContext, "props">): Promise<Response> {
    const asker = grantAsker(env, ctx.props as GrantProps | undefined);
    if (!asker) return Response.json({ error: "invalid_token", error_description: "Connect this AI app again." }, { status: 401 });
    const transport = new WebStandardStreamableHTTPServerTransport({ enableJsonResponse: true });
    await relayServer(asker).connect(transport);
    return transport.handleRequest(request);
  },
};

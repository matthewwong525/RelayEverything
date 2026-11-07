// The connector's tools over one person's notes, health, places and chats: eight that only read, and one that adds a
// typed note, from answers.ts and inputs.ts as the web API's are. The Google tools are google-tools.ts.
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { WebStandardStreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/webStandardStreamableHttp.js";
import { answer, Refusal, type Asker } from "./answers.ts";
import { grantAsker } from "./asker.ts";
import type { GrantProps } from "./env.ts";
import { GOOGLE_TOOLS } from "./google-tools.ts";
import { TOOLS, type ToolName } from "./inputs.ts";
import { ZONE } from "./time.ts";

type Answer = { content: { type: "text"; text: string }[]; isError?: boolean };

/** Runs a tool, and answers a refusal as a tool error the AI can read and correct. */
const tool = (ask: (input: never) => Promise<unknown>) => async (input: object): Promise<Answer> => {
  try {
    return { content: [{ type: "text", text: JSON.stringify(await ask(input as never)) }] };
  } catch (error) {
    if (!(error instanceof Refusal)) throw error;
    return { content: [{ type: "text", text: error.message }], isError: true };
  }
};

const readOnly = { readOnlyHint: true, destructiveHint: false, openWorldHint: false };
const adds = { readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false };

/** A fresh server per request: the connector keeps no session between calls. */
function relayServer(asker: Asker): McpServer {
  const server = new McpServer({ name: "relay", title: "Relay Everything", version: "1.2.0" }, {
    instructions: "Relay Everything holds one person's notes from a smart ring and their phone, with health and places, and the Claude Code chats " +
      "they saved. Those tools only read, but add_note adds a typed note when the person asks you to save one. If the person connected " +
      "Google, the email, calendar, Drive and contacts tools reach their own Google: send an email or delete an event only when they ask, " +
      `and nothing deletes an email or a file for ever. Days and times are ${ZONE} unless you pass a timezone.`,
  });
  for (const [name, { title, description, input }] of Object.entries(TOOLS) as [ToolName, (typeof TOOLS)[ToolName]][]) {
    server.registerTool(name, { title, description, inputSchema: input, annotations: name === "add_note" ? adds : readOnly },
      tool(input => answer(name, asker, input)));
  }
  for (const [name, { title, description, input, hints, ask }] of Object.entries(GOOGLE_TOOLS)) {
    server.registerTool(name, { title, description, inputSchema: input, annotations: hints }, tool(input => ask(asker, input)));
  }
  return server;
}

/** The connector's /mcp: Streamable HTTP, answered as JSON, with no session. Each token reaches only its grant's
 *  person's space; a grant from before spaces names no person, so its app must connect again. */
export const mcpHandler = {
  async fetch(request: Request, env: Parameters<typeof grantAsker>[0], ctx: Pick<ExecutionContext, "props">): Promise<Response> {
    const asker = grantAsker(env, ctx.props as GrantProps | undefined);
    if (!asker) return Response.json({ error: "invalid_token", error_description: "Connect this AI app again." }, { status: 401 });
    const transport = new WebStandardStreamableHTTPServerTransport({ enableJsonResponse: true });
    await relayServer(asker).connect(transport);
    return transport.handleRequest(request);
  },
};

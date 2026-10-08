import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import { APPROVAL_TIMEOUT_MS, type FigmaBackend } from "./runtime.js";

export function createServer(backend: FigmaBackend): Server {
  const server = new Server(
    { name: "figma-copilot-bridge", version: "0.1.0" },
    { capabilities: { tools: {} } },
  );
  server.setRequestHandler(ListToolsRequestSchema, async () => ({
    tools: await backend.listTools(),
  }));
  server.setRequestHandler(CallToolRequestSchema, async (request, extra) => {
    try {
      return await backend.callTool(request.params.name, request.params.arguments ?? {}, async (approval) => {
        if (!server.getClientCapabilities()?.elicitation) {
          throw new Error(`Figma ${approval.name} requires explicit confirmation, but this MCP client does not support form elicitation.`);
        }
        const result = await server.elicitInput({
          mode: "form",
          message: `Figma: ${approval.name}\n\n${approval.reason}\n\nArguments:\n${JSON.stringify(approval.arguments, null, 2)}`,
          requestedSchema: {
            type: "object",
            properties: {
              approved: { type: "boolean", title: "Allow this Figma operation once?", default: false },
            },
            required: ["approved"],
          },
          _meta: { "figma-copilot/requestId": extra.requestId },
        }, { timeout: APPROVAL_TIMEOUT_MS, signal: extra.signal, relatedRequestId: extra.requestId });
        return result.action === "accept" && result.content?.approved === true;
      });
    } catch (error) {
      return {
        isError: true,
        content: [{ type: "text", text: error instanceof Error ? error.message : String(error) }],
      };
    }
  });
  return server;
}

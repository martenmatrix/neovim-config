import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import type { FigmaBackend } from "./runtime.js";

export function createServer(backend: FigmaBackend): Server {
  const server = new Server(
    { name: "figma-copilot-bridge", version: "0.1.0" },
    { capabilities: { tools: {} } },
  );
  server.setRequestHandler(ListToolsRequestSchema, async () => ({
    tools: await backend.listTools(),
  }));
  server.setRequestHandler(CallToolRequestSchema, async (request) => {
    try {
      return await backend.callTool(request.params.name, request.params.arguments ?? {});
    } catch (error) {
      return {
        isError: true,
        content: [{ type: "text", text: error instanceof Error ? error.message : String(error) }],
      };
    }
  });
  return server;
}

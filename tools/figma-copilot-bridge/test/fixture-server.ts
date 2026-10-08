import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { createServer } from "../src/server.js";

if (process.argv.includes("--invalid-json")) {
  process.stdout.write("invalid json\n");
  process.stdin.resume();
} else {
  const server = createServer({
    listTools: async () => [
      { name: "whoami", description: "Read identity", inputSchema: { type: "object", properties: {} } },
      { name: "get_metadata", description: "Read metadata", inputSchema: { type: "object", properties: {} } },
      { name: "get_screenshot", description: "Read image", inputSchema: { type: "object", properties: {} } },
    ],
    callTool: async (name, args) => {
      if (args.nodeId === "crash") process.exit(12);
      if (args.nodeId === "hang") return new Promise(() => {});
      if (name === "get_screenshot") {
        return { content: [{ type: "image", data: "aW1hZ2U=", mimeType: "image/png" }] };
      }
      if (name === "get_metadata" && args.nodeId === "long") {
        return { content: [{ type: "text", text: "x".repeat(131072) }] };
      }
      if (name !== "whoami" && name !== "get_metadata") {
        throw new Error("Tool not allowed");
      }
      return { content: [{ type: "text", text: JSON.stringify(args) }] };
    },
    close: async () => {},
  });
  await server.connect(new StdioServerTransport());
  process.stdin.once("end", () => { void server.close(); });
}

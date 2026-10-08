import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { createServer } from "../src/server.js";
import { confirmFigmaCall, isAutoApprovedReadTool } from "../src/runtime.js";

if (process.argv.includes("--invalid-json")) {
  process.stdout.write("invalid json\n");
  process.stdin.resume();
} else {
  const executions: { name: string; arguments: Record<string, unknown> }[] = [];
  const names = ["whoami", "get_metadata", "get_screenshot", "get_libraries", "create_new_file", "future_tool"];
  const server = createServer({
    listTools: async () => names.map((name) => ({
      name, description: `Fixture ${name}`, inputSchema: { type: "object", properties: {} },
      ...(isAutoApprovedReadTool(name) ? { annotations: { readOnlyHint: true } } : {}),
    })),
    callTool: async (name, args, confirm) => {
      if (!names.includes(name)) throw new Error("Tool not available");
      if (!isAutoApprovedReadTool(name)) {
        await confirmFigmaCall({ name, arguments: args, reason: "Fixture requires approval." }, confirm);
        executions.push({ name, arguments: args });
      }
      if (name === "whoami" && args.inspect) {
        return { content: [{ type: "text", text: JSON.stringify(executions) }] };
      }
      if (args.nodeId === "crash") process.exit(12);
      if (args.nodeId === "hang") return new Promise(() => {});
      if (name === "get_screenshot") {
        return { content: [{ type: "image", data: "aW1hZ2U=", mimeType: "image/png" }] };
      }
      if (name === "get_metadata" && args.nodeId === "long") {
        return { content: [{ type: "text", text: "x".repeat(131072) }] };
      }
      return { content: [{ type: "text", text: JSON.stringify(args) }] };
    },
    close: async () => {},
  });
  await server.connect(new StdioServerTransport());
  process.stdin.once("end", () => { void server.close(); });
}

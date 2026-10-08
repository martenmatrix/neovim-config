import assert from "node:assert/strict";
import test from "node:test";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { InMemoryTransport } from "@modelcontextprotocol/sdk/inMemory.js";
import { createServer } from "../src/server.js";
import type { FigmaBackend } from "../src/runtime.js";

test("MCP clients discover schemas, receive image blocks, and see explicit tool failures", async (t) => {
  const backend: FigmaBackend = {
    listTools: async () => [{
      name: "get_screenshot", description: "Read a frame",
      inputSchema: { type: "object", properties: { nodeId: { type: "string" } }, required: ["nodeId"] },
    }],
    callTool: async (name) => {
      if (name !== "get_screenshot") throw new Error("Tool not allowed");
      return { content: [{ type: "image", data: "aW1hZ2U=", mimeType: "image/png" }] };
    },
    close: async () => {},
  };
  const server = createServer(backend);
  const client = new Client({ name: "test", version: "1" });
  const [serverTransport, clientTransport] = InMemoryTransport.createLinkedPair();
  await server.connect(serverTransport);
  await client.connect(clientTransport);
  t.after(async () => { await client.close(); await server.close(); });
  const { tools } = await client.listTools();
  assert.deepEqual(tools[0]?.inputSchema.required, ["nodeId"]);
  const image = await client.callTool({ name: "get_screenshot", arguments: { nodeId: "1:2" } });
  assert.deepEqual(image.content, [{ type: "image", data: "aW1hZ2U=", mimeType: "image/png" }]);
  const denied = await client.callTool({ name: "create_new_file", arguments: {} });
  assert.equal(denied.isError, true);
  assert.deepEqual(denied.content, [{ type: "text", text: "Tool not allowed" }]);
  backend.listTools = async () => { throw new Error("Figma authentication required"); };
  await assert.rejects(client.listTools(), /authentication required/);
});

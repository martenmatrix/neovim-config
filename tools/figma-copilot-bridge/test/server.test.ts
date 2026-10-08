import assert from "node:assert/strict";
import test from "node:test";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { InMemoryTransport } from "@modelcontextprotocol/sdk/inMemory.js";
import { ElicitRequestSchema } from "@modelcontextprotocol/sdk/types.js";
import { createServer } from "../src/server.js";
import { confirmFigmaCall, type FigmaBackend } from "../src/runtime.js";

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

test("form elicitation approves exactly one operation and preserves explicit rejection and cancellation", async (t) => {
  const calls: unknown[] = [];
  const approvals: string[] = [];
  let action: "accept" | "decline" | "cancel" = "accept";
  const server = createServer({
    listTools: async () => [{
      name: "future_tool", inputSchema: { type: "object", properties: {} },
    }],
    callTool: async (name, args, confirm) => {
      await confirmFigmaCall({ name, arguments: args, reason: "Unknown operation." }, confirm);
      calls.push(args);
      return { content: [{ type: "text", text: "Executed once" }] };
    },
    close: async () => {},
  });
  const client = new Client({ name: "approval-test", version: "1" }, { capabilities: { elicitation: { form: {} } } });
  client.setRequestHandler(ElicitRequestSchema, async (request) => {
    assert.equal(request.params.mode, "form");
    approvals.push(request.params.message);
    return action === "accept" ? { action, content: { approved: true } } : { action };
  });
  const [serverTransport, clientTransport] = InMemoryTransport.createLinkedPair();
  await server.connect(serverTransport);
  await client.connect(clientTransport);
  t.after(async () => { await client.close(); await server.close(); });
  const args = { nested: { id: "fixture" } };
  assert.notEqual((await client.callTool({ name: "future_tool", arguments: args })).isError, true);
  for (action of ["decline", "cancel"] as const) {
    assert.equal((await client.callTool({ name: "future_tool", arguments: args })).isError, true);
  }
  assert.deepEqual(calls, [args]);
  assert.equal(approvals.length, 3);
  assert(approvals.every((message) => message.includes('"id": "fixture"')));
});

test("clients without form elicitation cannot grant write permission through tool arguments", async (t) => {
  let calls = 0;
  const server = createServer({
    listTools: async () => [{ name: "create_new_file", inputSchema: { type: "object", properties: {} } }],
    callTool: async (name, args, confirm) => {
      await confirmFigmaCall({ name, arguments: args, reason: "Write operation." }, confirm);
      calls++;
      return { content: [] };
    },
    close: async () => {},
  });
  const client = new Client({ name: "unattended", version: "1" });
  const [serverTransport, clientTransport] = InMemoryTransport.createLinkedPair();
  await server.connect(serverTransport);
  await client.connect(clientTransport);
  t.after(async () => { await client.close(); await server.close(); });
  const result = await client.callTool({ name: "create_new_file", arguments: { approved: true } });
  assert.equal(result.isError, true);
  assert(JSON.stringify(result.content).includes("does not support form elicitation"));
  assert.equal(calls, 0);
});

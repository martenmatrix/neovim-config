import assert from "node:assert/strict";
import { fileURLToPath } from "node:url";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";
import { READ_TOOLS } from "./runtime.js";

const client = new Client({ name: "figma-bridge-check", version: "0.1.0" });
const transport = new StdioClientTransport({
  command: process.execPath,
  args: [fileURLToPath(new URL("./index.js", import.meta.url))],
  stderr: "inherit",
});

try {
  await client.connect(transport);
  const { tools } = await client.listTools({}, { timeout: 75_000 });
  assert(tools.length > 0, "Figma discovery returned no tools");
  assert(tools.every((tool) => READ_TOOLS.some((name) => name === tool.name)));
  const identity = await client.callTool({ name: "whoami", arguments: {} }, undefined, { timeout: 75_000 });
  assert(!identity.isError, "Live Figma whoami failed");
  assert(Array.isArray(identity.content) && identity.content.length > 0);
  const denied = await client.callTool({ name: "create_new_file", arguments: {} });
  assert.equal(denied.isError, true, "Write tools must be rejected");
  console.log(`Live Figma check passed: ${tools.length} read-only tools, authenticated whoami, write rejection.`);
} finally {
  await client.close();
}

import assert from "node:assert/strict";
import { fileURLToPath } from "node:url";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";
import { isAutoApprovedReadTool, TOOL_TIMEOUT_MS } from "./runtime.js";

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
  assert(tools.some((tool) => tool.name === "create_new_file"), "Write tools must be discoverable");
  assert(tools.some((tool) => tool.name === "get_libraries"), "Additional read tools must be discoverable");
  const identity = await client.callTool({ name: "whoami", arguments: {} }, undefined, { timeout: 75_000 });
  assert(!identity.isError, "Live Figma whoami failed");
  assert(Array.isArray(identity.content) && identity.content.length > 0);
  const guarded = tools.find((tool) => !isAutoApprovedReadTool(tool.name) && !tool.inputSchema.required?.length);
  assert(guarded, "No protected tool with empty valid arguments is available for the denial check");
  const denied = await client.callTool({ name: guarded.name, arguments: {} }, undefined, { timeout: TOOL_TIMEOUT_MS + 15_000 });
  assert.equal(denied.isError, true, "Unclassified tools must require confirmation");
  assert(JSON.stringify(denied.content).includes("confirmation"), "Denial must come from the approval gate");
  console.log(`Live Figma check passed: ${tools.length} tools, verified upstream coverage, authenticated whoami, confirmation enforcement.`);
} finally {
  await client.close();
}

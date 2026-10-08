import assert from "node:assert/strict";
import { mkdtemp, readFile, readdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import type { SessionConfig } from "@github/copilot-sdk";
import {
  approveReadOnlyFigma,
  FigmaRuntime,
  READ_TOOLS,
  toMcpResult,
  type RuntimeClient,
} from "../src/runtime.js";

type Session = Awaited<ReturnType<RuntimeClient["createSession"]>>;
type Result = Awaited<ReturnType<Session["rpc"]["tools"]["execute"]>>;

async function fixture(t: test.TestContext) {
  const home = await mkdtemp(join(tmpdir(), "figma-bridge-test-"));
  const configText = JSON.stringify({
    mcpServers: { figma: { type: "http", url: "https://mcp.figma.com/mcp" }, "other-server": { command: "unused" } },
  });
  await writeFile(join(home, "mcp-config.json"), configText);
  let sessionConfig: SessionConfig | undefined;
  let cwd: string | undefined;
  let stops = 0;
  let forceStops = 0;
  const deleted: string[] = [];
  const calls: unknown[] = [];
  let result: Result = { resultType: "success", textResultForLlm: "design context" };
  const session: Session = {
    sessionId: "owned-test-session",
    rpc: {
      tools: {
        initializeAndValidate: async () => ({}),
        getCurrentMetadata: async () => ({
          tools: [
            ...READ_TOOLS.map((name) => ({
              name: `figma-${name}`,
              mcpServerName: "figma",
              mcpToolName: name,
              description: `Read ${name}`,
              input_schema: name === "get_metadata"
                ? { type: "object", properties: { nodeId: { type: "string" } }, required: ["nodeId"], additionalProperties: false }
                : { type: "object", properties: {} },
            })),
            { name: "figma-create_new_file", mcpServerName: "figma", mcpToolName: "create_new_file", description: "Write" },
            { name: "other-whoami", mcpServerName: "other-server", mcpToolName: "whoami", description: "Foreign" },
          ],
        }),
        execute: async (args) => { calls.push(args); return result; },
      },
      mcp: {
        listConfigured: async () => ({ servers: [
          { name: "figma", enabled: true, live: { status: "connected" } },
          { name: "other-server", enabled: false },
        ] }),
      },
    },
  };
  const client: RuntimeClient = {
    start: async () => {},
    createSession: async (config) => { sessionConfig = config; return session; },
    deleteSession: async (id) => { deleted.push(id); },
    stop: async () => { stops++; return []; },
    forceStop: async () => { forceStops++; },
  };
  const runtime = new FigmaRuntime({
    copilotHome: home,
    clientFactory: (options) => { cwd = options.workingDirectory; return client; },
    timeoutMs: 1000,
    pollMs: 1,
  });
  t.after(async () => {
    await runtime.close();
    await rm(home, { recursive: true });
  });
  return {
    home, runtime, client, session, calls, deleted, configText,
    get config() { return sessionConfig; },
    get cwd() { return cwd; },
    get stops() { return stops; },
    get forceStops() { return forceStops; },
    set result(value: Result) { result = value; },
  };
}

test("discovers original schemas once, disables other servers, and never modifies global config", async (t) => {
  const f = await fixture(t);
  let discovery = 0;
  f.session.rpc.tools.initializeAndValidate = async () => { discovery++; return {}; };
  const [tools, again] = await Promise.all([f.runtime.listTools(), f.runtime.listTools()]);
  assert.deepEqual(tools, again);
  assert.deepEqual(tools.map((tool) => tool.name), [...READ_TOOLS]);
  assert.equal(discovery, 2);
  assert.deepEqual(tools.find((tool) => tool.name === "get_metadata")?.inputSchema.required, ["nodeId"]);
  assert(tools.every((tool) => tool.annotations?.readOnlyHint));
  assert.deepEqual(f.config?.disabledMcpServers, ["other-server", "github-mcp-server", "githubiq"]);
  assert.deepEqual(f.config?.availableTools, ["mcp:*"]);
  assert.equal(f.config?.enableConfigDiscovery, false);
  assert.equal(f.config?.enableSessionStore, false);
  assert.equal(f.config?.remoteSession, "off");
  assert.deepEqual(f.config?.largeOutput, { enabled: false });
  assert.deepEqual(f.config?.mcpServers?.figma?.tools, [...READ_TOOLS]);
  assert.equal(await readFile(join(f.home, "mcp-config.json"), "utf8"), f.configText);
  const cwd = f.cwd;
  assert(cwd?.startsWith(join(tmpdir(), "figma-copilot-bridge-")));
  assert(cwd);
  assert.deepEqual(await readdir(cwd), []);
  await f.runtime.close();
  assert.deepEqual(f.deleted, ["owned-test-session"]);
  assert.equal(f.stops, 1);
  await assert.rejects(readdir(cwd), { code: "ENOENT" });
  await f.runtime.close();
  assert.equal(f.stops, 1);
});

test("waits for asynchronous connection and invokes the canonical runtime name without a model turn", async (t) => {
  const f = await fixture(t);
  let observations = 0;
  f.session.rpc.mcp.listConfigured = async () => ({
    servers: [{ name: "figma", enabled: true, live: { status: ++observations < 3 ? "pending" : "connected" } }],
  });
  const result = await f.runtime.callTool("get_metadata", { nodeId: "1:2" });
  assert.equal(observations, 3);
  assert.equal(result.isError, false);
  assert.deepEqual(f.calls, [{ name: "figma-get_metadata", arguments: { nodeId: "1:2" } }]);
});

test("rejects write tools, foreign names, invalid schemas, and non-JSON arguments before invocation", async (t) => {
  const f = await fixture(t);
  for (const name of ["create_new_file", "figma-whoami", "other-whoami", "shell"]) {
    await assert.rejects(f.runtime.callTool(name, {}), /not allowed/);
  }
  await assert.rejects(f.runtime.callTool("get_metadata", {}), /Invalid get_metadata arguments/);
  await assert.rejects(f.runtime.callTool("get_metadata", { nodeId: 2 }), /Invalid get_metadata arguments/);
  await assert.rejects(f.runtime.callTool("whoami", { unsupported: undefined }), /expected JSON/);
  assert.deepEqual(f.calls, []);
});

test("fails closed if a non-Figma server unexpectedly remains enabled", async (t) => {
  const f = await fixture(t);
  f.session.rpc.mcp.listConfigured = async () => ({
    servers: [{ name: "other-server", enabled: true }, { name: "figma", enabled: true, live: { status: "connected" } }],
  });
  await assert.rejects(f.runtime.listTools(), /Isolation check failed/);
  assert.deepEqual(f.calls, []);
});

for (const status of ["needs-auth", "failed", "stopped", "disabled"] as const) {
  test(`surfaces ${status} instead of returning empty successful discovery`, async (t) => {
    const f = await fixture(t);
    f.session.rpc.mcp.listConfigured = async () => ({
      servers: [{ name: "figma", enabled: true, live: { status } }],
    });
    await assert.rejects(f.runtime.listTools(), status === "needs-auth" ? /Authenticate figma.*\/mcp/ : /connection failed/);
    assert.deepEqual(f.calls, []);
  });
}

test("bounds startup and stops its owned runtime on timeout", async (t) => {
  const f = await fixture(t);
  const runtime = new FigmaRuntime({ copilotHome: f.home, clientFactory: () => f.client, timeoutMs: 20, pollMs: 1 });
  f.session.rpc.mcp.listConfigured = async () => ({
    servers: [{ name: "figma", enabled: true, live: { status: "pending" } }],
  });
  await assert.rejects(runtime.listTools(), /timed out/);
  assert.equal(f.forceStops, 1);
  await runtime.close();
  assert.equal(f.stops, 1);
});

test("rejects malformed global configuration without launching a runtime", async (t) => {
  const f = await fixture(t);
  await writeFile(join(f.home, "mcp-config.json"), '{"mcpServers":[]}');
  await assert.rejects(f.runtime.listTools(), /mcpServers configuration must be an object/);
  assert.equal(f.config, undefined);
});

test("shutdown during startup stops the owned runtime and removes its temporary directory", async (t) => {
  const f = await fixture(t);
  let releaseStart: (() => void) | undefined;
  const started = new Promise<void>((resolve) => {
    f.client.start = () => new Promise<void>((release) => {
      releaseStart = release;
      resolve();
    });
  });
  const discovery = assert.rejects(f.runtime.listTools(), /closed/);
  await started;
  const closing = f.runtime.close();
  assert(releaseStart);
  releaseStart();
  await closing;
  await discovery;
  assert.equal(f.stops, 1);
  assert(f.cwd);
  await assert.rejects(readdir(f.cwd), { code: "ENOENT" });
  assert.deepEqual(f.deleted, []);
});

test("shutdown failures remain explicit while runtime stop and directory cleanup still run", async (t) => {
  const f = await fixture(t);
  const runtime = new FigmaRuntime({ copilotHome: f.home, clientFactory: () => f.client });
  await runtime.listTools();
  f.client.deleteSession = async () => { throw new Error("Session deletion failed"); };
  await assert.rejects(runtime.close(), (error: unknown) =>
    error instanceof AggregateError && error.errors[0]?.message === "Session deletion failed");
  assert.equal(f.stops, 1);
});

test("permission handler respects server, allowlist, read-only annotations, and managed approvals", async () => {
  const permission = {
    kind: "mcp" as const, serverName: "figma", toolName: "get_metadata", toolTitle: "Metadata", readOnly: true,
  };
  assert.deepEqual(await approveReadOnlyFigma(permission, { sessionId: "test" }), { kind: "approve-once" });
  for (const changes of [
    { serverName: "other" },
    { toolName: "create_new_file" },
    { readOnly: false },
    { managedApprovalRequired: true },
  ]) {
    assert.equal((await approveReadOnlyFigma({ ...permission, ...changes }, { sessionId: "test" })).kind, "reject");
  }
});

test("preserves text, image data, structured content, and information-flow metadata", () => {
  const result = toMcpResult({
    resultType: "success", textResultForLlm: "Frame",
    binaryResultsForLlm: [{ type: "image", data: "aW1hZ2U=", mimeType: "image/png" }],
    structuredContent: { width: 320 },
    mcpMeta: { label: "design" },
  });
  assert.deepEqual(result.content, [
    { type: "text", text: "Frame" },
    { type: "image", data: "aW1hZ2U=", mimeType: "image/png" },
  ]);
  assert.deepEqual(result.structuredContent, { width: 320 });
  assert.deepEqual(result._meta, { label: "design" });
});

test("uses canonical content blocks without duplicating their text or images", () => {
  assert.deepEqual(toMcpResult({
    resultType: "success", textResultForLlm: "duplicate",
    contents: [{ type: "text", text: "original" }, { type: "image", data: "aW1hZ2U=", mimeType: "image/png" }],
    binaryResultsForLlm: [{ type: "image", data: "aW1hZ2U=", mimeType: "image/png" }],
  }).content, [{ type: "text", text: "original" }, { type: "image", data: "aW1hZ2U=", mimeType: "image/png" }]);
});

test("keeps captions and makes structured-only results visible to text-only MCP integrations", () => {
  assert.deepEqual(toMcpResult({
    resultType: "success", textResultForLlm: "Frame caption",
    contents: [{ type: "image", data: "aW1hZ2U=", mimeType: "image/png" }],
  }).content, [
    { type: "text", text: "Frame caption" },
    { type: "image", data: "aW1hZ2U=", mimeType: "image/png" },
  ]);
  const result = toMcpResult({ resultType: "success", textResultForLlm: "", structuredContent: { width: 320 } });
  assert.deepEqual(result.content, [{ type: "text", text: '{"width":320}' }]);
  assert.deepEqual(result.structuredContent, { width: 320 });
});

for (const resultType of ["failure", "denied", "rejected", "timeout"] as const) {
  test(`preserves ${resultType} as a tool error`, () => {
    const result = toMcpResult({ resultType, textResultForLlm: "", error: "upstream error" });
    assert.equal(result.isError, true);
    assert.deepEqual(result.content, [{ type: "text", text: `[${resultType}] upstream error` }]);
  });
}

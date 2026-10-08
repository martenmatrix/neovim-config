import assert from "node:assert/strict";
import { mkdtemp, readFile, readdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import type { SessionConfig } from "@github/copilot-sdk";
import {
  AUTO_APPROVED_READ_TOOLS,
  FigmaRuntime,
  isAutoApprovedReadTool,
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
  const calls: Parameters<Session["rpc"]["tools"]["execute"]>[0][] = [];
  let result: Result = { resultType: "success", textResultForLlm: "design context" };
  const metadata = [
    ...AUTO_APPROVED_READ_TOOLS.map((name) => ({
      name: `figma-${name}`,
      mcpServerName: "figma",
      mcpToolName: name,
      description: `Read ${name}`,
      input_schema: name === "get_metadata"
        ? { type: "object", properties: { nodeId: { type: "string" } }, required: ["nodeId"], additionalProperties: false }
        : { type: "object", properties: {} },
    })),
    {
      name: "figma-create_new_file", mcpServerName: "figma", mcpToolName: "create_new_file", description: "Write",
      input_schema: { type: "object", properties: { name: { type: "string" } }, required: ["name"], additionalProperties: false },
    },
    {
      name: "figma-library_lookup", mcpServerName: "figma", mcpToolName: "get_libraries", description: "Read libraries",
      input_schema: { type: "object", properties: {} },
    },
    {
      name: "figma-future_tool", mcpServerName: "figma", mcpToolName: "future_tool", description: "Unknown future operation",
      input_schema: { type: "object", properties: {} },
    },
    { name: "other-whoami", mcpServerName: "other-server", mcpToolName: "whoami", description: "Foreign" },
  ];
  const session: Session = {
    sessionId: "owned-test-session",
    rpc: {
      tools: {
        initializeAndValidate: async () => ({}),
        getCurrentMetadata: async () => ({ tools: metadata }),
        execute: async (args) => {
          const tool = metadata.find((item) => item.name === args.name);
          if (!tool || !sessionConfig?.onPermissionRequest) throw new Error("Fixture was not initialized");
          const decision = await sessionConfig.onPermissionRequest({
            kind: "mcp", serverName: "figma", toolName: tool.mcpToolName, toolTitle: tool.description,
            args: args.arguments, readOnly: isAutoApprovedReadTool(tool.mcpToolName),
            ...(args.toolCallId ? { toolCallId: args.toolCallId } : {}),
          }, { sessionId: session.sessionId });
          if (decision.kind !== "approve-once") return { resultType: "denied", textResultForLlm: "Denied by runtime" };
          calls.push(args);
          return result;
        },
      },
      mcp: {
        listTools: async () => ({ tools: metadata.filter((tool) => tool.mcpServerName === "figma").map((tool) => ({ name: tool.mcpToolName })) }),
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

test("discovers every upstream tool and original schema once, disables other servers, and never modifies global config", async (t) => {
  const f = await fixture(t);
  let discovery = 0;
  f.session.rpc.tools.initializeAndValidate = async () => { discovery++; return {}; };
  const [tools, again] = await Promise.all([f.runtime.listTools(), f.runtime.listTools()]);
  assert.deepEqual(tools, again);
  assert.deepEqual(tools.map((tool) => tool.name), [...AUTO_APPROVED_READ_TOOLS, "create_new_file", "get_libraries", "future_tool"]);
  assert.equal(discovery, 2);
  assert.deepEqual(tools.find((tool) => tool.name === "get_metadata")?.inputSchema.required, ["nodeId"]);
  assert(tools.filter((tool) => isAutoApprovedReadTool(tool.name)).every((tool) => tool.annotations?.readOnlyHint));
  assert(tools.filter((tool) => !isAutoApprovedReadTool(tool.name)).every((tool) => tool.annotations === undefined));
  assert.deepEqual(f.config?.disabledMcpServers, ["other-server", "github-mcp-server", "githubiq"]);
  assert.deepEqual(f.config?.availableTools, ["mcp:*"]);
  assert.equal(f.config?.enableConfigDiscovery, false);
  assert.equal(f.config?.enableSessionStore, false);
  assert.equal(f.config?.remoteSession, "off");
  assert.deepEqual(f.config?.largeOutput, { enabled: false });
  assert.deepEqual(f.config?.mcpServers?.figma?.tools, ["*"]);
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
  assert.deepEqual(f.calls.map(({ toolCallId, ...call }) => {
    assert.equal(typeof toolCallId, "string");
    return call;
  }), [{ name: "figma-get_metadata", arguments: { nodeId: "1:2" } }]);
});

test("rejects foreign names, invalid schemas, and non-JSON arguments before invocation", async (t) => {
  const f = await fixture(t);
  for (const name of ["figma-whoami", "other-whoami", "shell", "not_advertised"]) {
    await assert.rejects(f.runtime.callTool(name, {}), /not available/);
  }
  await assert.rejects(f.runtime.callTool("get_metadata", {}), /Invalid get_metadata arguments/);
  await assert.rejects(f.runtime.callTool("get_metadata", { nodeId: 2 }), /Invalid get_metadata arguments/);
  await assert.rejects(f.runtime.callTool("whoami", { unsupported: undefined }), /expected JSON/);
  assert.deepEqual(f.calls, []);
});

test("fails discovery rather than silently omitting upstream tools", async (t) => {
  const f = await fixture(t);
  f.session.rpc.mcp.listTools = async () => ({ tools: [{ name: "missing_tool" }] });
  await assert.rejects(f.runtime.listTools(), /Incomplete Figma tool coverage: missing \[missing_tool\]/);
});

test("refuses writes and unknown read operations without explicit confirmation", async (t) => {
  const f = await fixture(t);
  for (const [name, args] of [
    ["create_new_file", { name: "Fixture" }],
    ["get_libraries", {}],
    ["future_tool", {}],
  ] as const) {
    await assert.rejects(f.runtime.callTool(name, args), /requires explicit confirmation/);
    await assert.rejects(f.runtime.callTool(name, args, async () => false), /rejected or cancelled/);
  }
  assert.deepEqual(f.calls, []);
});

test("approved writes, new reads, and future tools use their exact discovered runtime names and arguments", async (t) => {
  const f = await fixture(t);
  const approvals: string[] = [];
  const confirm = async (request: { name: string }) => { approvals.push(request.name); return true; };
  await f.runtime.callTool("create_new_file", { name: "Fixture" }, confirm);
  await f.runtime.callTool("get_libraries", { fileKey: "fixture" }, confirm);
  await f.runtime.callTool("future_tool", { payload: { id: 1 } }, confirm);
  assert.deepEqual(approvals, ["create_new_file", "get_libraries", "future_tool"]);
  assert.deepEqual(f.calls.map(({ toolCallId, ...call }) => {
    assert.equal(typeof toolCallId, "string");
    return call;
  }), [
    { name: "figma-create_new_file", arguments: { name: "Fixture" } },
    { name: "figma-library_lookup", arguments: { fileKey: "fixture" } },
    { name: "figma-future_tool", arguments: { payload: { id: 1 } } },
  ]);
  assert.equal(new Set(f.calls.map((call) => call.toolCallId)).size, 3);
  await assert.rejects(f.runtime.callTool("create_new_file", { name: "Fixture" }, async () => false), /rejected/);
  assert.equal(f.calls.length, 3, "Allow once must not approve the next call");
});

test("approval callbacks and caller mutations cannot change the validated arguments", async (t) => {
  const f = await fixture(t);
  const args = { name: "Fixture" };
  await f.runtime.callTool("create_new_file", args, async (request) => {
    args.name = "changed by caller";
    request.arguments.name = "changed by approval callback";
    return true;
  });
  assert.deepEqual(f.calls[0]?.arguments, { name: "Fixture" });
});

test("shutdown cancels an unanswered approval and prevents late approval from executing", async (t) => {
  const f = await fixture(t);
  let release: ((approved: boolean) => void) | undefined;
  let waiting: (() => void) | undefined;
  const ready = new Promise<void>((resolve) => { waiting = resolve; });
  const call = assert.rejects(f.runtime.callTool("create_new_file", { name: "Fixture" }, () => {
    waiting?.();
    return new Promise<boolean>((resolve) => { release = resolve; });
  }), /closed/);
  await ready;
  await f.runtime.close();
  release?.(true);
  await call;
  assert.deepEqual(f.calls, []);
});

test("unanswered approvals time out without invoking an upstream tool", async (t) => {
  const f = await fixture(t);
  const runtime = new FigmaRuntime({
    copilotHome: f.home, clientFactory: () => f.client, approvalTimeoutMs: 20,
  });
  t.after(() => runtime.close());
  await assert.rejects(runtime.callTool("create_new_file", { name: "Fixture" }, () => new Promise(() => {})), /approval timed out/);
  assert.deepEqual(f.calls, []);
  assert.equal(f.forceStops, 1);
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

test("permissions are bound to the exact active invocation and cannot authorize foreign or host operations", async (t) => {
  const f = await fixture(t);
  const execute = f.session.rpc.tools.execute;
  f.session.rpc.tools.execute = async (call) => {
    const handler = f.config?.onPermissionRequest;
    assert(handler);
    const permission = {
      kind: "mcp" as const, serverName: "figma", toolName: "get_metadata", toolTitle: "Metadata",
      readOnly: true, args: call.arguments, ...(call.toolCallId ? { toolCallId: call.toolCallId } : {}),
    };
    for (const changes of [
      { serverName: "other" }, { toolName: "create_new_file" },
      { args: { nodeId: "different" } }, { toolCallId: "stale" },
    ]) {
      assert.equal((await handler({ ...permission, ...changes }, { sessionId: "test" })).kind, "reject");
    }
    const { toolCallId, ...uncorrelated } = permission;
    assert(toolCallId);
    assert.equal((await handler(uncorrelated, { sessionId: "test" })).kind, "reject");
    assert.equal((await handler({
      kind: "read", path: "fixture", intention: "Read local data", ...(call.toolCallId ? { toolCallId: call.toolCallId } : {}),
    }, { sessionId: "test" })).kind, "reject");
    return execute(call);
  };
  await f.runtime.callTool("get_metadata", { nodeId: "1:2" });
  const handler = f.config?.onPermissionRequest;
  assert(handler);
  const last = f.calls[0];
  assert(last?.toolCallId);
  assert.equal((await handler({
    kind: "mcp", serverName: "figma", toolName: "get_metadata", toolTitle: "Metadata",
    readOnly: true, toolCallId: last.toolCallId,
  }, { sessionId: "test" })).kind, "reject");
});

test("managed or non-read-only permission requests for audited reads still require human confirmation", async (t) => {
  const f = await fixture(t);
  let managed = false;
  f.session.rpc.tools.execute = async (call) => {
    const handler = f.config?.onPermissionRequest;
    assert(handler);
    const decision = await handler({
      kind: "mcp", serverName: "figma", toolName: "whoami", toolTitle: "Identity",
      readOnly: managed, managedApprovalRequired: managed,
      ...(call.toolCallId ? { toolCallId: call.toolCallId } : {}),
    }, { sessionId: "test" });
    return { resultType: decision.kind === "approve-once" ? "success" : "denied", textResultForLlm: "Fixture" };
  };
  for (managed of [false, true]) {
    let approvals = 0;
    assert.equal((await f.runtime.callTool("whoami", {}, async () => { approvals++; return true; })).isError, false);
    assert.equal(approvals, 1);
    await assert.rejects(f.runtime.callTool("whoami", {}, async () => false), /rejected/);
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

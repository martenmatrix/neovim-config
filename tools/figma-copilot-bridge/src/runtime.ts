import {
  CopilotClient,
  type CopilotClientOptions,
  type CopilotSession,
  type PermissionHandler,
  type SessionConfig,
  type JsonValue,
} from "@github/copilot-sdk";
import {
  CallToolResultSchema,
  ToolSchema,
  type CallToolResult,
  type Tool,
} from "@modelcontextprotocol/sdk/types.js";
import { AjvJsonSchemaValidator } from "@modelcontextprotocol/sdk/validation/ajv-provider.js";
import type { JsonSchemaType, JsonSchemaValidator } from "@modelcontextprotocol/sdk/validation/types.js";
import { randomUUID } from "node:crypto";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { homedir, tmpdir } from "node:os";
import { join } from "node:path";
import { setTimeout as delay } from "node:timers/promises";
import { isDeepStrictEqual } from "node:util";

export const AUTO_APPROVED_READ_TOOLS = [
  "whoami",
  "get_design_context",
  "get_metadata",
  "get_screenshot",
  "get_variable_defs",
  "get_figjam",
  "get_code_connect_map",
] as const;

export const APPROVAL_TIMEOUT_MS = 300_000;
export const TOOL_TIMEOUT_MS = APPROVAL_TIMEOUT_MS + 60_000;

export type ApprovalRequest = {
  name: string;
  arguments: Record<string, unknown>;
  reason: string;
};
export type ApprovalHandler = (request: ApprovalRequest) => Promise<boolean>;

export async function confirmFigmaCall(
  request: ApprovalRequest,
  confirm?: ApprovalHandler,
): Promise<void> {
  if (!confirm) {
    throw new Error(`Figma ${request.name} requires explicit confirmation. Use a client with form elicitation support.`);
  }
  if (!(await confirm({ ...request, arguments: structuredClone(request.arguments) }))) {
    throw new Error(`Figma ${request.name} was rejected or cancelled. No permission was granted.`);
  }
}

export function isAutoApprovedReadTool(name: string): boolean {
  return AUTO_APPROVED_READ_TOOLS.some((tool) => tool === name);
}

type Session = {
  sessionId: string;
  rpc: {
    tools: Pick<
      CopilotSession["rpc"]["tools"],
      "initializeAndValidate" | "getCurrentMetadata" | "execute"
    >;
    mcp: Pick<CopilotSession["rpc"]["mcp"], "listConfigured" | "listTools">;
  };
};

export type RuntimeClient = {
  start(): Promise<void>;
  createSession(config: SessionConfig): Promise<Session>;
  deleteSession(id: string): Promise<void>;
  stop(): Promise<Error[]>;
  forceStop(): Promise<void>;
};

type RuntimeResult = Awaited<ReturnType<Session["rpc"]["tools"]["execute"]>>;
type Options = {
  clientFactory?: (options: CopilotClientOptions) => RuntimeClient;
  copilotHome?: string;
  timeoutMs?: number;
  approvalTimeoutMs?: number;
  pollMs?: number;
};

export interface FigmaBackend {
  listTools(): Promise<Tool[]>;
  callTool(name: string, args: Record<string, unknown>, confirm?: ApprovalHandler): Promise<CallToolResult>;
  close(): Promise<void>;
}

function isJson(value: unknown): value is JsonValue {
  if (value === null || typeof value === "string" || typeof value === "boolean") return true;
  if (typeof value === "number") return Number.isFinite(value);
  if (Array.isArray(value)) return value.every(isJson);
  if (typeof value !== "object" || Object.getPrototypeOf(value) !== Object.prototype) return false;
  return Object.values(value).every(isJson);
}

export function toMcpResult(result: RuntimeResult): CallToolResult {
  if (typeof result === "string") {
    return { content: [{ type: "text", text: result }] };
  }
  const content: unknown[] = result.contents?.length ? [...result.contents] : [];
  if (!result.contents?.length) {
    for (const [index, binary] of (result.binaryResultsForLlm ?? []).entries()) {
      content.push(
        binary.type === "image"
          ? { type: "image", data: binary.data, mimeType: binary.mimeType }
          : {
              type: "resource",
              resource: {
                uri: `figma-bridge://binary/${index}`,
                blob: binary.data,
                mimeType: binary.mimeType,
              },
            },
      );
    }
  }
  if (!content.some((block) => typeof block === "object" && block !== null && "type" in block && block.type === "text")) {
    if (result.textResultForLlm) {
      content.unshift({ type: "text", text: result.textResultForLlm });
    } else if (result.structuredContent !== undefined) {
      content.unshift({ type: "text", text: JSON.stringify(result.structuredContent) });
    }
  }
  if (result.resultType !== "success") {
    content.unshift({
      type: "text",
      text: `[${result.resultType}] ${result.error ?? result.textResultForLlm}`,
    });
  }
  return CallToolResultSchema.parse({
    content,
    isError: result.resultType !== "success",
    ...(result.structuredContent !== undefined
      ? { structuredContent: result.structuredContent }
      : {}),
    ...(result.mcpMeta ? { _meta: result.mcpMeta } : {}),
  });
}

export class FigmaRuntime implements FigmaBackend {
  private readonly options: Required<Options>;
  private client: RuntimeClient | undefined;
  private session: Session | undefined;
  private directory: string | undefined;
  private initialization: Promise<Tool[]> | undefined;
  private initialized: Promise<Tool[]> | undefined;
  private closing: Promise<void> | undefined;
  private closed = false;
  private readonly abort = new AbortController();
  private readonly invocations = new Map<string, {
    name: string;
    runtimeName: string;
    arguments: Record<string, unknown>;
    confirm: ApprovalHandler | undefined;
    approved: boolean;
  }>();
  private readonly tools = new Map<
    string,
    { tool: Tool; runtimeName: string; validate: JsonSchemaValidator<unknown> }
  >();

  constructor(options: Options = {}) {
    this.options = {
      clientFactory: options.clientFactory ?? ((config) => new CopilotClient(config)),
      copilotHome: options.copilotHome ?? process.env.COPILOT_HOME ?? join(homedir(), ".copilot"),
      timeoutMs: options.timeoutMs ?? 60_000,
      approvalTimeoutMs: options.approvalTimeoutMs ?? APPROVAL_TIMEOUT_MS,
      pollMs: options.pollMs ?? 250,
    };
  }

  private async bounded<T>(operation: Promise<T>, action: string, timeoutMs = this.options.timeoutMs): Promise<T> {
    let timer: NodeJS.Timeout | undefined;
    let cancel: (() => void) | undefined;
    try {
      return await Promise.race([
        operation,
        new Promise<never>((_, reject) => {
          timer = setTimeout(() => {
            this.closed = true;
            reject(new Error(`${action} timed out. Restart the Figma bridge.`));
            this.abort.abort();
            void this.client?.forceStop().catch((error: unknown) => {
              console.error("Figma bridge runtime cleanup failed:", error);
            });
          }, timeoutMs);
        }),
        new Promise<never>((_, reject) => {
          cancel = () => reject(new Error("Figma bridge is closed."));
          this.abort.signal.addEventListener("abort", cancel, { once: true });
          if (this.abort.signal.aborted) cancel();
        }),
      ]);
    } finally {
      clearTimeout(timer);
      if (cancel) this.abort.signal.removeEventListener("abort", cancel);
    }
  }

  private readonly permissionHandler: PermissionHandler = async (request) => {
    if (this.closed || request.kind !== "mcp" || request.serverName !== "figma") {
      return { kind: "reject", feedback: "This bridge permits only the exact requested Figma operation." };
    }
    const toolCallId = request.toolCallId;
    const invocation = toolCallId ? this.invocations.get(toolCallId) : undefined;
    if (
      !toolCallId ||
      !invocation ||
      (request.toolName !== invocation.name && request.toolName !== invocation.runtimeName) ||
      (request.args !== undefined && !isDeepStrictEqual(request.args, invocation.arguments))
    ) {
      return { kind: "reject", feedback: "This bridge permits only the exact requested Figma operation." };
    }
    if (!invocation.approved && (!request.readOnly || request.managedApprovalRequired)) {
      await this.bounded(confirmFigmaCall({
        name: invocation.name,
        arguments: invocation.arguments,
        reason: request.managedApprovalRequired
          ? "Organization policy requires an explicit user decision."
          : "The runtime reports that this operation is not read-only.",
      }, invocation.confirm), `Figma ${invocation.name} approval`, this.options.approvalTimeoutMs);
      if (this.closed || this.invocations.get(toolCallId) !== invocation) {
        return { kind: "reject", feedback: "This Figma invocation is no longer active." };
      }
      invocation.approved = true;
    }
    return { kind: "approve-once" };
  };

  private async disabledServers(): Promise<string[]> {
    let text: string;
    try {
      text = await readFile(join(this.options.copilotHome, "mcp-config.json"), "utf8");
    } catch (error) {
      if (!(error instanceof Error && "code" in error && error.code === "ENOENT")) throw error;
      return ["github-mcp-server", "githubiq"];
    }
    const config: unknown = JSON.parse(text);
    if (typeof config !== "object" || config === null || Array.isArray(config)) {
      throw new Error("Copilot MCP configuration must be an object.");
    }
    const servers = "mcpServers" in config ? config.mcpServers : {};
    if (typeof servers !== "object" || servers === null || Array.isArray(servers)) {
      throw new Error("Copilot mcpServers configuration must be an object.");
    }
    return [
      ...Object.keys(servers).filter((name) => name !== "figma"),
      "github-mcp-server",
      "githubiq",
    ];
  }

  private async initialize(): Promise<Tool[]> {
    const disabledMcpServers = await this.disabledServers();
    if (this.closed) throw new Error("Figma bridge is closed.");
    this.directory = await mkdtemp(join(tmpdir(), "figma-copilot-bridge-"));
    if (this.closed) throw new Error("Figma bridge is closed.");
    this.client = this.options.clientFactory({
      mode: "copilot-cli",
      baseDirectory: this.options.copilotHome,
      workingDirectory: this.directory,
      logLevel: "error",
    });
    await this.client.start();
    if (this.closed) throw new Error("Figma bridge is closed.");
    this.session = await this.client.createSession({
      availableTools: ["mcp:*"],
      disabledMcpServers,
      enableExperimentalMode: true,
      enableConfigDiscovery: false,
      enableSessionStore: false,
      enableHostGitOperations: false,
      enableSkills: false,
      enableFileHooks: false,
      enableOnDemandInstructionDiscovery: false,
      remoteSession: "off",
      mcpOAuthTokenStorage: "persistent",
      infiniteSessions: { enabled: false },
      largeOutput: { enabled: false },
      onPermissionRequest: this.permissionHandler,
      mcpServers: {
        figma: {
          type: "http",
          url: "https://mcp.figma.com/mcp",
          tools: ["*"],
          timeout: this.options.timeoutMs,
        },
      },
    });
    if (this.closed) throw new Error("Figma bridge is closed.");
    await this.session.rpc.tools.initializeAndValidate();
    for (;;) {
      if (this.closed) throw new Error("Figma bridge is closed.");
      const { servers } = await this.session.rpc.mcp.listConfigured();
      if (servers.some((server) => server.name !== "figma" && server.enabled)) {
        throw new Error("Isolation check failed: a non-Figma MCP server is enabled.");
      }
      const figma = servers.find((server) => server.name === "figma");
      if (!figma?.enabled) throw new Error("Figma MCP is disabled by configuration or policy.");
      const state = figma.live?.status;
      if (state === "connected") break;
      if (state === "needs-auth") {
        throw new Error("Figma authentication required. Authenticate figma in Copilot with /mcp, then restart the bridge.");
      }
      if (state === "failed" || state === "stopped" || state === "disabled" || state === "not_configured") {
        throw new Error(`Figma connection failed: ${figma.live?.error ?? state}`);
      }
      await delay(this.options.pollMs);
    }
    await this.session.rpc.tools.initializeAndValidate();
    if (this.closed) throw new Error("Figma bridge is closed.");
    const upstream = await this.session.rpc.mcp.listTools({ serverName: "figma" });
    const metadata = await this.session.rpc.tools.getCurrentMetadata();
    const validator = new AjvJsonSchemaValidator();
    for (const item of metadata.tools ?? []) {
      if (item.mcpServerName !== "figma" || !item.mcpToolName) continue;
      if (this.tools.has(item.mcpToolName)) {
        throw new Error(`Duplicate Figma tool '${item.mcpToolName}' in runtime metadata.`);
      }
      const tool = ToolSchema.parse({
        name: item.mcpToolName,
        description: item.description,
        inputSchema: item.input_schema,
        ...("title" in item && typeof item.title === "string" ? { title: item.title } : {}),
        ...(isAutoApprovedReadTool(item.mcpToolName)
          ? { annotations: { readOnlyHint: true, destructiveHint: false, openWorldHint: true } }
          : {}),
      });
      this.tools.set(tool.name, {
        tool,
        runtimeName: item.name,
        // AJV validates the schema; the MCP and validator packages use different schema types.
        validate: validator.getValidator(tool.inputSchema as JsonSchemaType),
      });
    }
    if (this.tools.size === 0) {
      throw new Error("Copilot returned no Figma tools. Check SDK/runtime compatibility and Figma authentication.");
    }
    const upstreamNames = new Set(upstream.tools.map((tool) => tool.name));
    const missing = [...upstreamNames].filter((name) => !this.tools.has(name));
    const unexpected = [...this.tools.keys()].filter((name) => !upstreamNames.has(name));
    if (missing.length || unexpected.length) {
      throw new Error(`Incomplete Figma tool coverage: missing [${missing.join(", ")}], unexpected [${unexpected.join(", ")}]. Check SDK compatibility and policy.`);
    }
    return [...this.tools.values()].map(({ tool }) => tool);
  }

  async listTools(): Promise<Tool[]> {
    if (this.closed) throw new Error("Figma bridge is closed.");
    if (!this.initialized) {
      this.initialization = this.initialize();
      this.initialized = this.bounded(this.initialization, "Figma connection");
    }
    return this.initialized;
  }

  async callTool(name: string, args: Record<string, unknown>, confirm?: ApprovalHandler): Promise<CallToolResult> {
    await this.listTools();
    const entry = this.tools.get(name);
    if (!entry || !this.session) throw new Error(`Figma tool '${name}' is not available.`);
    const validation = entry.validate(args);
    if (!validation.valid) throw new Error(`Invalid ${name} arguments: ${validation.errorMessage}`);
    if (!isJson(args)) throw new Error(`Invalid ${name} arguments: expected JSON values.`);
    const argumentsSnapshot = structuredClone(args);
    const invocation = {
      name,
      runtimeName: entry.runtimeName,
      arguments: argumentsSnapshot,
      confirm,
      approved: false,
    };
    if (!isAutoApprovedReadTool(name)) {
      await this.bounded(confirmFigmaCall({
        name,
        arguments: argumentsSnapshot,
        reason: "This operation is not on the bridge's audited read-only list. It may change remote data, run code, or incur costs.",
      }, confirm), `Figma ${name} approval`, this.options.approvalTimeoutMs);
      invocation.approved = true;
    }
    if (this.closed || !this.session) throw new Error("Figma bridge is closed.");
    const toolCallId = randomUUID();
    this.invocations.set(toolCallId, invocation);
    try {
      const result = await this.bounded(
        this.session.rpc.tools.execute({
          name: entry.runtimeName,
          arguments: argumentsSnapshot,
          toolCallId,
        }),
        `Figma ${name}`,
        this.options.timeoutMs + this.options.approvalTimeoutMs,
      );
      return toMcpResult(result);
    } finally {
      this.invocations.delete(toolCallId);
    }
  }

  async close(): Promise<void> {
    this.closed = true;
    this.abort.abort();
    this.invocations.clear();
    this.closing ??= this.cleanup();
    return this.closing;
  }

  private async cleanup(): Promise<void> {
    const errors: unknown[] = [];
    const watchdog = setTimeout(() => {
      console.error("Figma bridge: forcing runtime shutdown after cleanup timeout.");
      void this.client?.forceStop().catch((error: unknown) => {
        console.error("Figma bridge forced shutdown failed:", error);
      });
    }, 5_000);
    try {
      if (this.initialization) {
        try {
          await this.initialization;
        } catch (error) {
          console.error("Figma bridge discovery ended:", error instanceof Error ? error.message : error);
        }
      }
      if (!this.client) return;
      try {
        if (this.session) await this.client.deleteSession(this.session.sessionId);
      } catch (error) {
        errors.push(error);
      } finally {
        try {
          const stopErrors = await this.client.stop();
          errors.push(...stopErrors);
          if (stopErrors.length) await this.client.forceStop();
        } catch (error) {
          errors.push(error);
          await this.client.forceStop();
        }
      }
    } finally {
      clearTimeout(watchdog);
      if (this.directory) await rm(this.directory, { recursive: true });
    }
    if (errors.length) throw new AggregateError(errors, "Figma bridge cleanup failed.");
  }
}

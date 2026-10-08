import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { FigmaRuntime } from "./runtime.js";
import { createServer } from "./server.js";

const backend = new FigmaRuntime();
const server = createServer(backend);
let stopping: Promise<void> | undefined;

function shutdown(): Promise<void> {
  stopping ??= Promise.resolve().then(async () => {
    const watchdog = setTimeout(() => process.exit(1), 8_000);
    try {
      await server.close();
      await backend.close();
    } finally {
      clearTimeout(watchdog);
    }
  });
  return stopping;
}

function stop(): void {
  void shutdown().catch((error: unknown) => {
    console.error("Figma bridge shutdown failed:", error);
    process.exitCode = 1;
  });
}

process.once("SIGINT", stop);
process.once("SIGTERM", stop);
process.stdin.once("end", stop);
server.onclose = stop;
server.onerror = (error) => console.error("Figma bridge protocol error:", error.message);

try {
  await server.connect(new StdioServerTransport());
} catch (error) {
  console.error("Figma bridge startup failed:", error);
  process.exitCode = 1;
  await shutdown();
}

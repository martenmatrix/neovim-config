# Figma through Copilot

An optional, read-only bridge from Avante/MCPHub to the official remote Figma MCP server.
The Copilot SDK executes tools directly; it does not send a prompt or run a second model turn.

```text
Avante -> MCPHub native server -> local stdio MCP bridge -> Copilot runtime -> Figma
```

## Setup

Requires Node.js 20.19+ or 22.12+ and a working Copilot CLI login with Figma authenticated through `/mcp`.
The pinned SDK includes its matching runtime, so the bridge does not update your global Copilot installation.
These are application dependencies, not editor tools installed through Mason.
The project-local npm configuration uses the public registry; it does not change your global npm settings.

From the Neovim configuration directory:

```sh
npm --prefix tools/figma-copilot-bridge ci
npm --prefix tools/figma-copilot-bridge run build
npm --prefix tools/figma-copilot-bridge run check
```

Restart Neovim. `:MCPHub` should show **Figma via Copilot (read-only)** with server name `figma-copilot`.
In Avante, paste a Figma frame URL and ask it to use `figma-copilot` for the design context.
Use `:FigmaBridgeRestart` to reconnect after authenticating or rebuilding.
Without a local build, the optional bridge stays inactive and existing MCPHub behavior is unchanged.

The bridge exposes `whoami`, `get_design_context`, `get_metadata`, `get_screenshot`,
`get_variable_defs`, `get_figjam`, and `get_code_connect_map`, when available upstream.
It discovers their real argument schemas from Copilot instead of duplicating them.
Figma file access, plan limits, and organization policies still apply.

## Isolation

- All source, tests, dependencies, and build output live in this directory.
- The only activation hook is `on_ready` in `lua/marten/plugins/mcphub.lua`.
- No global MCP configuration is rewritten. The bridge reads configured server names only to disable all non-Figma servers in its own session.
- Copilot owns OAuth and its existing credential storage. No tokens are copied into this repository or into Lua.
- Only read-only Figma tools are offered. Shell, file-writing, other MCP tools, skills, project instructions, and remote session export are disabled for the bridge session.
- The runtime runs in a temporary directory, not the project. Normal shutdown deletes its own Copilot session and temporary directory.
- Requests have a 60-second runtime deadline. Neovim allows 75 seconds for protocol overhead. Errors remain errors; authentication failures never become empty successful results.

The SDK APIs are experimental and version-pinned. CLI-compatible mode is required to reuse the approved
Copilot Figma authorization; the SDK's empty mode does not currently reuse that authorization here.
The bridge starts a separate runtime, not a connection to an existing interactive chat.

Text, image blocks, structured content, and result metadata are preserved when supplied by the runtime.
MCPHub's current Avante extension ignores image blocks, so the bridge temporarily hooks the calling sidebar
to insert screenshots after the complete tool-result batch. The hook restores itself after insertion or shutdown.
Screenshots then become normal Avante chat context and follow Avante's usual history storage.
This is a tools-only bridge, not a general MCP resource, sampling, or Figma write proxy.

## Disable or remove

`:FigmaBridgeStop` stops the bridge for the current Neovim session.
MCPHub's native-server start/stop controls also manage the bridge process.
To prevent startup, set this before MCPHub loads:

```lua
vim.g.figma_copilot_bridge = false
```

For complete removal, stop the bridge and remove this directory, the small `on_ready` hook in
`lua/marten/plugins/mcphub.lua`, and the README link. The hook also safely skips startup if this directory is absent.
No global MCP entries or credentials need to be reverted.

## Tests

Run from the Neovim configuration directory:

```sh
npm --prefix tools/figma-copilot-bridge test
nvim --headless -u NONE -l tools/figma-copilot-bridge/test/nvim.lua
npm --prefix tools/figma-copilot-bridge run check
FIGMA_BRIDGE_LIVE=1 nvim --headless -u NONE -l tools/figma-copilot-bridge/test/nvim.lua
```

The first two commands use fixtures and make no Figma requests. They cover isolation, schemas,
argument forwarding, large/fragmented responses, screenshot delivery into Copilot model requests,
permission denial, authentication errors, timeouts, process crashes, and cleanup.
The last two require existing authentication and call only `whoami`; identity details are not printed.

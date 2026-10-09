# Figma through Copilot

An optional, full-tool bridge from Avante/MCPHub to the official remote Figma MCP server.
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

Restart Neovim. `:MCPHub` should show **Figma via Copilot** with server name `figma-copilot`.
In Avante, paste a Figma frame URL and ask it to use `figma-copilot` for the design context.
Use `:FigmaBridgeRestart` to reconnect after authenticating or rebuilding.
Without a local build, the optional bridge stays inactive and existing MCPHub behavior is unchanged.

The bridge exposes every tool advertised by the authenticated upstream Figma server, including
library search, Code Connect, file creation, uploads, shaders, generative plugins, and Weave.
It discovers their real argument schemas and canonical execution names from Copilot instead of duplicating them.
Discovery compares the upstream tool list with the initialized runtime; missing tools fail explicitly.
The current server advertises 41 tools, but there is no fixed tool-count or exposure allowlist.
Figma file access, plan limits, and organization policies still apply.

## Approvals

Only the audited read tools `whoami`, `get_design_context`, `get_metadata`, `get_screenshot`,
`get_variable_defs`, `get_figjam`, and `get_code_connect_map` run without bridge confirmation.
Every other tool requires explicit approval for each call, including additional read tools and newly added tools.
The pinned SDK does not expose upstream read/write annotations, so unknown tools are not labelled read-only.
If the runtime reports an audited read as non-read-only or requires a managed approval, it also prompts.

The approval window shows the tool name, reason, and complete arguments in a scrollable buffer:

- `a`: allow this exact call once.
- `r` or `Enter`: reject.
- `q` or `Esc`: cancel.

There is no Allow Always. Parallel approvals are queued, and stopping/restarting closes outstanding windows.
Approval is enforced inside the bridge even when Avante and MCPHub globally auto-approve MCP calls.
Permission grants are bound to the exact active call, tool, and argument snapshot; they do not authorize
other Figma calls, another server, or local shell/file operations.
After an approved call starts, stopping or timing out cannot guarantee rollback of remote changes.
Other stdio MCP clients need standard form elicitation support to approve protected tools.
Clients without it can discover all tools and use audited reads, but protected calls fail explicitly.

## Isolation

- All source, tests, dependencies, and build output live in this directory.
- The only activation hook is `on_ready` in `lua/marten/plugins/mcphub.lua`.
- No global MCP configuration is rewritten. The bridge reads configured server names only to disable all non-Figma servers in its own session.
- Copilot owns OAuth and its existing credential storage. No tokens are copied into this repository or into Lua.
- Only Figma tools are offered. Host shell/file operations, other MCP servers, skills, project instructions, and remote session export are disabled for the bridge session.
- The runtime runs in a temporary directory, not the project. Normal shutdown deletes its own Copilot session and temporary directory.
- Connection and upstream MCP requests have a 60-second deadline. Approval allows up to five minutes; tool protocol requests allow six minutes plus 15 seconds of overhead. Startup still allows 75 seconds. Errors remain errors; authentication failures never become empty successful results.

The SDK APIs are experimental and version-pinned. CLI-compatible mode is required to reuse the approved
Copilot Figma authorization; the SDK's empty mode does not currently reuse that authorization here.
The bridge starts a separate runtime, not a connection to an existing interactive chat.

Text, image blocks, structured content, and result metadata are preserved when supplied by the runtime.
MCPHub's current Avante extension ignores image blocks, so the bridge temporarily hooks the calling sidebar
to insert images after the complete tool-result batch. The hook restores itself after insertion or shutdown.
Each image gets its own single-block history message, as required by Avante's history helpers.
Images then become normal Avante chat context and follow Avante's usual history storage.
If an older bridge already raised `more than one entry in message content`, restart Neovim and start a new
chat with `Space an`; the failed insertion may have left a malformed message in that chat's saved history.
Full tool coverage does not mean a transparent proxy for MCP resources, sampling, or MCP Apps UI.
Tool-provided browser-capture, upload/download, and polling instructions are returned to Avante; the bridge does
not autonomously run browser scripts or transfer local files. Avante must carry out those workflow steps with
its normal tools and permissions. All exposed schemas and descriptions increase Avante's MCP prompt context.

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

The first two commands use fixtures and make no Figma requests. They cover complete discovery, isolation, schemas,
argument forwarding, large/fragmented responses, screenshot delivery into Copilot model requests,
approved fixture writes, denial/cancellation, queued approvals, authentication errors, timeouts, process crashes, and cleanup.
The last two require existing authentication and execute only `whoami`; identity details are not printed.
The stdio check also attempts a protected tool without elicitation to prove confirmation enforcement;
that call is rejected before upstream execution. No live mutation is tested.

# Figma through CodeCompanion

Temporary authentication workaround for Copilot CLI's direct Figma connection over ACP:

```text
CodeCompanion -> Copilot CLI (ACP) -> figma_bridge (stdio) -> Copilot SDK runtime -> Figma
```

The SDK executes tool RPCs directly, without a second model turn. MCPHub is not involved.

## Setup

Requires Node.js 20.19+ or 22.12+, Copilot CLI on Neovim's PATH, and an existing Copilot/Figma login.
Authenticate Figma through the CLI's `/mcp` interface; do not copy credentials into this repository.

`lua/marten/plugins/codecompanion.lua` configures the bridge and its Lazy build hook.
It disables direct `figma` only in the outer ACP process and adds the stdio server as `figma_bridge`.
The isolated SDK runtime keeps its own Figma connection; global MCP configuration stays unchanged.

For an existing installation, build manually or run `:Lazy build codecompanion.nvim`:

```sh
npm --prefix tools/figma-copilot-bridge ci
npm --prefix tools/figma-copilot-bridge run build
```

Restart Neovim, then use `Space an` for a new chat. Paste a Figma URL and ask the agent to use `figma_bridge`.
Existing chats retain their previous ACP processes.

## Approvals

**The current editor setup auto-approves all tools, including remote Figma writes.**
CodeCompanion uses YOLO, Copilot CLI launches with `--allow-all`, and the bridge starts with `--auto-approve`.
Reviewing or reverting local code does not undo remote Figma changes.
Commit/push-only-on-request instructions remain model guidance, not an enforced permission boundary.

Without `--auto-approve`, the standalone bridge retains its strict policy: audited reads run automatically,
and other operations require per-call MCP form confirmation. Unsupported clients fail closed.
ACP currently lacks that form-confirmation path, which is why this configuration explicitly opts into auto-approval.

## Scope and isolation

- Exposes the upstream tool schemas; incomplete discovery fails explicitly. Figma access, plan limits, and organization policies still apply.
- Uses the pinned SDK's matching runtime and existing credential storage, without upgrading the global CLI or copying tokens.
- The inner bridge session allows only Figma: no host shell/files, other MCP servers, skills, or project instructions. This does not restrict the outer ACP agent.
- Preserves text, images, structured results, and metadata. CodeCompanion does not display agent-returned image blocks.
- Proxies tools, not MCP resources, sampling, or MCP Apps UI. External browser/file-transfer workflows remain the agent's responsibility.

Legacy Avante/MCPHub compatibility files remain here but are not used by the active configuration.
To disable or remove this workaround, remove its MCP configuration, corresponding launch flags, and build hook
from `lua/marten/plugins/codecompanion.lua` before deleting this directory. No global credentials need reverting.

## Checks

Run from the Neovim configuration directory:

```sh
npm --prefix tools/figma-copilot-bridge test
nvim --headless -u NONE -l tests/codecompanion.lua
npm --prefix tools/figma-copilot-bridge run check
```

The first two use fixtures, not live Figma. The live check verifies authenticated `whoami` without printing identity
details, then confirms the standalone bridge's strict default rejects a protected call before upstream execution.
No live mutation is tested.

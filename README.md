If using macOS, your NeoVim config is located under `~/.config/nvim`.

You'll have to download a [NerdFont](https://www.nerdfonts.com/font-downloads) in order to display icons correctly. If using iTerm navigate to Settings > Profiles > Your Profile > Text and activate "Use a different font for non-ASCII text". Additionally select a Nerd Font as the Non-ASCII Font.

Some formatters are pre-configured like `stylua` for Lua. You need to install the following formatters, if you want to use them:

**Lua**:

- `brew install stylua`

**Prettier**:

- `npm install -g prettier`

If you want to use `styled-components` with Typescript, you'll have to install the TypeScript Styled Plugin locally in your project and configure the tsconfig.json [like this](https://github.com/styled-components/typescript-styled-plugin?tab=readme-ov-file#with-vs-code) or you'll have to configure it globally the following way:

1. `npm install -g @styled/typescript-styled-plugin`
2. Lookup path, which contains your globally installed node_modules with `npm root -g`
3. Specify path in config at `lua/marten/plugins/lsp/lsp-config.lua` under `tsserver`

For variable/placeholder-transformations you'll need to install `jsregexp` for LuaSnip:

1. Go to `/Users/{user}/.local/share/nvim/lazy/LuaSnip`
2. Run `make install_jsregexp`

To enable all Telescope features install `ripgrep` and `fd`:

`brew install ripgrep`
`brew install fd`

Some othe recommended installs:
- `pnpm install neovim`

For unknown reasons Mason does not always install `js-debug-adapter` automatically, so you'll might have to run `:MasonInstall js-debug-adapter` to use some debugging features with JavaScript or TypeScript.

Run `pi install npm:pi-nvim` after installing pi.dev.

## Plugin updates

Run `:Lazy sync` as your normal user, not with `sudo`, to avoid root-owned plugin files.
Avante's required `mega.cmdparse` and `mega.logging` dependencies are installed by Lazy; LuaRocks remains disabled.

## Avante with GitHub Copilot

Avante uses your Copilot subscription through `github/copilot.vim`. Run `:Copilot setup` to sign in if needed.
The default is `claude-opus-5.5` with high reasoning effort. The Copilot request override preserves Claude's effort setting, which Avante's OpenAI parameter filter otherwise removes.
Replies default to English unless you explicitly request another language. Restart Neovim and start a new chat after changing these defaults.
High reasoning effort and long chat/file context can increase response latency.
MCP server/tool names are listed up front; Avante retrieves individual tool descriptions and argument schemas with `get_mcp_tool_schema` only when needed.
Streaming requests have a 10-second connection deadline and a five-minute total deadline, after which Avante reports a request error instead of waiting indefinitely.
The Figma bridge's runtime hop affects Figma calls, not ordinary Avante replies.
After these changes, restart Neovim and use `Space an` for a new chat to avoid carrying over previously loaded tool schemas.
If a request appears stuck, use `Space aS` to cancel it. Check `:messages` for request or tool errors; waiting for an edit approval can also pause the conversation.

[Optional remote Figma bridge](tools/figma-copilot-bridge/README.md): all Figma tools through the Copilot SDK, with per-call confirmation for non-audited operations, isolated in one removable directory.

The leader key is Space:

| Keys | Action |
| --- | --- |
| `Space aa` | Ask about the current file or visual selection |
| `Space an` | Start a new chat |
| `Space ae` in visual mode | Edit the selected code |
| `Space at` | Toggle the sidebar |
| `Space af` | Switch between the chat and file pane |
| `Space a?` | Choose a model |
| `Space aS` | Stop the current request |

Type your question in the input window, then press `Esc` followed by `Enter` to send it.
Use `@file` to add another file to the chat. Avante reads the project's `AGENTS.md` automatically.
Opening Avante from a terminal or file tree uses an editable file pane as its context, not the terminal URI or tree buffer.
Run the context regression tests with `nvim --headless -u NONE -l tests/avante.lua` after installing the plugins.

Reads, searches, diagnostics, chat bookkeeping, shell commands, and Python execution run without approval prompts.
Native file modifications (including creation, deletion, and moves) and the Git commit tool still require approval.
Shell/Python commands can modify files without Avante's native edit review; auto-approval is tool-based, not a read-only command filter.
With inline approvals, use `Space af` from
the chat to focus the file pane, then `co` to keep yours, `ct` to accept Avante's change, and `]x` / `[x` to move between changes.
Finish the review with Allow/Reject in the sidebar. Avoid Allow Always: it bypasses later prompts in that chat.
MCP calls are also auto-approved by MCPHub, including tools that change remote data or files; those changes do not necessarily use Avante's native review UI.
The optional Figma bridge independently requires per-call approval for every tool outside its audited read list, regardless of MCPHub auto-approval.

Telescope opens selected files in an editable file pane, even when launched from Avante or a terminal.
If no file pane exists, Telescope creates an empty one first.

## Terminal

`Space tT` opens a 15-line terminal below a file pane, leaving the Avante sidebar on the right.
If no file pane exists, an empty one is created first; opening a file is not required.
Only terminals opened with this mapping have their height fixed; plugin terminals keep their own layouts.

Run the layout regression tests with `nvim --headless -u NONE -l tests/terminal.lua`.

## C/C++ (clangd) with the Xcode toolchain on macOS

For C/C++/Obj-C projects that build with the Xcode toolchain, `lua/marten/plugins/lsp/lsp-config.lua` does two things so files don't show red everywhere:

- **Launches clangd via `xcrun -f clangd`** (follows `xcode-select`) instead of Mason's LLVM build, which can't parse toolchain-generated headers or a beta SDK.
- **Restricts `sourcekit-lsp` to `filetypes = { 'swift' }`**, so it doesn't spawn a second arg-less clangd that fights the real one and paints includes red.

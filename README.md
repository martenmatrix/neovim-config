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
The default is `claude-sonnet-5.5` with high reasoning effort. The Copilot request override preserves Claude's effort setting, which Avante's OpenAI parameter filter otherwise removes.

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

Reads, searches, diagnostics, chat bookkeeping, and all MCP calls run without approval prompts.
Native file modifications and shell commands require approval. With inline approvals, use `Space af` from
the chat to focus the file pane, then `co` to keep yours, `ct` to accept Avante's change, and `]x` / `[x` to move between changes.
Finish the review with Allow/Reject in the sidebar. Avoid Allow Always: it bypasses later prompts in that chat.
MCP calls are also auto-approved by MCPHub, including tools that change remote data or files; those changes do not necessarily use Avante's native review UI.

Telescope opens selected files in an editable file pane, even when launched from Avante or a terminal.
`Space tT` opens a 15-line terminal below a file pane, leaving the Avante sidebar on the right.
If no file pane exists, the terminal and Telescope create an empty one first; opening a file is not required.

## C/C++ (clangd) with the Xcode toolchain on macOS

For C/C++/Obj-C projects that build with the Xcode toolchain, `lua/marten/plugins/lsp/lsp-config.lua` does two things so files don't show red everywhere:

- **Launches clangd via `xcrun -f clangd`** (follows `xcode-select`) instead of Mason's LLVM build, which can't parse toolchain-generated headers or a beta SDK.
- **Restricts `sourcekit-lsp` to `filetypes = { 'swift' }`**, so it doesn't spawn a second arg-less clangd that fights the real one and paints includes red.

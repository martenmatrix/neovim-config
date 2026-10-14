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
Avante defaults to its supported `legacy` (suggestion-first) mode: finish generating proposed edits, then review them with native conflicts instead of approving each agentic edit while it runs.
Replies default to English unless you explicitly request another language. Restart Neovim after changing these defaults; existing saved chats can be reused.
High reasoning effort and long chat/file context can increase response latency.
Avante output skips extra Markdown decorations to reduce UI overhead in long chats; ordinary Markdown files keep their rendering.
MCP server/tool names are listed up front; Avante retrieves individual tool descriptions and argument schemas with `get_mcp_tool_schema` only when needed.
Streaming requests have a 10-second connection deadline and a five-minute total deadline, after which Avante reports a request error instead of waiting indefinitely.
The Figma bridge's runtime hop affects Figma calls, not ordinary Avante replies.
An optional new chat (`Space an`) avoids carrying over previously loaded tool schemas, but is not required for legacy review.
If a request appears stuck, use `Space aS` to cancel it. Check `:messages` for request or tool errors; waiting for an edit approval can also pause the conversation.

[Optional remote Figma bridge](tools/figma-copilot-bridge/README.md): all Figma tools through the Copilot SDK, with per-call confirmation for non-audited operations, isolated in one removable directory.

The leader key is Space:

| Keys | Action |
| --- | --- |
| `Space aa` | Ask about the current file or visual selection |
| `Space aw` | Focus the chat input and start typing |
| `Space aw` in visual mode | Attach the selected code as context and start typing |
| `Space ar` | Focus the latest completed response, or a pending approval popup in this tab |
| `Space a]` | Manually open the next pending review file |
| `Space aq` | Show pending review files in Neovim's quickfix list |
| `Space au` | Refresh the current file context (previously `Space ar`) |
| `Space an` | Start a new chat |
| `Space ae` in visual mode | Edit the selected code |
| `Space at` | Toggle the sidebar |
| `Space af` | Switch between the chat and file pane |
| `Space a?` | Choose a model |
| `Space aS` | Stop the current request |

Type your question in the input window, then press `Esc` followed by `Enter` to send it.
The new write/review shortcuts are Normal-mode bindings; `aw` also works directly from Visual mode.
Writing preserves the current chat and any existing draft. Selecting code attaches Avante's native selection context, not pasted text, and never submits a question automatically.
Avante captures whole selected lines, including for characterwise selections.
Review only changes focus, never accepts an edit. It waits for the response to finish and reports when this tab has nothing to review.
Avante input uses its own completion for `/` commands and mentions; Blink is disabled there to avoid duplicate menus.
In both chat and prompt inputs, `Ctrl+Space` opens completion, `Ctrl+k` / `Ctrl+l` select the next / previous item, `Ctrl+y` accepts the selected item (or the first if none is selected), and `Ctrl+e` closes the menu.
Type `@file` and accept it with `Ctrl+y` to open the file picker and add files to the chat.
These mappings do not replace `Tab`, `Enter`, or `Ctrl+s`; normal editor completion remains handled by Blink.
Avante natively loads the first available project-root instruction file, in this order: `AGENTS.md`, `CLAUDE.md`, `OPENCODE.md`, `.cursorrules`, `.windsurfrules`, `.github/copilot-instructions.md`.
It does not merge that list: `AGENTS.md` takes precedence. Project-local `avante.md` remains an additional instruction source.
Avante also reads the optional private `~/.copilot/instructions/global.instructions.md`, which Copilot CLI automatically loads.
Keep personal contents in that external file, never in this public repository. Plain `COPILOT.md` is not automatically loaded; merge personal advice into the shared global file.
Opening Avante from a terminal or file tree uses an editable file pane as its context, not the terminal URI or tree buffer.
Chat navigation preserves the same `j` / `k` / `l` / `;` home-row layout as file buffers, including while a request is running.
Run the context regression tests with `nvim --headless -u NONE -l tests/avante.lua` after installing the plugins.

### Reviewing proposed changes

Add the relevant existing files with `@file`, send your request, and let Avante finish its response.
Legacy submissions restore the edit-proposal prompt even if the sidebar was previously opened in chat-only mode.
The current instructions include the native proposal format even when a saved chat supplies its own system prompt; saved rules and conversation history are preserved.
The agent should propose edits rather than refuse because direct editing tools are unavailable. A plain Markdown diff is not the proposal format that opens native file review.
Proposals use Avante's native `SEARCH/REPLACE` format. After a successful response, Avante automatically loads the latest proposed changes into conflict buffers and focuses a file for review.
In legacy mode, `auto_apply_diff_after_generation = true` prepares these conflicts; it does not accept the incoming changes or save the files.
Cancelled responses and responses without proposed edits do not open file review. Completion in another tab does not steal focus; switch to its chat tab, press `Esc`, then `Space ar` and `A` to prepare review there.
`Space ar` still opens the latest response. Its native `A` / `a` shortcuts remain available for manual review when conflicts have not already been prepared; do not apply the same suggestions again over unresolved conflicts.
In each file, use `]x` / `[x` to navigate hunks, `ct` to accept the suggestion, or `co` to keep your original code.
Avante's default `diff.autojump = true` advances to the next conflict after resolving a hunk.
Resolving a hunk, accepting all hunks with `ca`, or ordinary editing such as `dd` never automatically switches review files.
After finishing the current file, press `Space a]` or run `:AvanteReviewNext` to open the next pending file manually.
This command refuses to leave a file while any conflict markers remain, including incomplete markers Avante cannot parse as a hunk.
`Space aq` / `:AvanteReviewList` creates a native quickfix list with one entry per pending file in this tab; `Enter` opens a listed file.
File navigation uses Neovim's native quickfix commands. It does not accept or save edits; resolved changes remain in their buffers.
Use `:b <filename>` to switch manually or return to a reviewed file. Resolve every conflict, then save each reviewed file with `:w` before requesting more changes.
Run `:AvanteReviewReload` to reload only the review hooks and restore missing conflict controls in existing prepared buffers.
It preserves pending diffs, chat history, and drafts; it does not rerun Avante setup, apply suggestions again, or save files.
There is no built-in `:AvanteNext` command in the installed Avante version; `AvanteReviewNext` / `AvanteReviewList` are explicit manual convenience commands.
The native `]x` / `[x` controls navigate hunks within a pending file, not between files.
If the command is not yet available in an older running instance, bootstrap it with `:lua dofile(vim.fn.stdpath('config') .. '/lua/marten/core/avante-review.lua').setup(nil, true)`.
This is proposal-first review, not an autonomous edit-and-test run followed by a final approval queue: proposed code cannot be tested as applied code until you accept it.

Reads, searches, diagnostics, chat bookkeeping, shell commands, and Python execution still run without approval prompts.
Avante is instructed not to bypass proposal review with shell, Python, or MCP writes. This is model guidance, not a filesystem sandbox: those tools can still modify files, and auto-approval is tool-based rather than a read-only command filter.
Native agentic text-editing tools are disabled in legacy mode. Other file operations and the Git commit tool still require approval.
If you switch back to agentic mode, edit approvals use Avante's built-in confirmation popup instead of inline chat buttons.
In that popup, press `c` to inspect the file; `Space ar` returns to the popup and `Ctrl-w f` toggles to the previous pane.
Press `y` to finish accepting the current edit, or `n` to reject it and submit the optional reason.
Avante is instructed to answer questions in rejection feedback before another edit, then continue with that feedback in mind.
This is model guidance, not a forced pause. To pause the current run instead, use `Space aS`, then `Space aw` to send the question separately.
Avoid `a` (All yes) unless intentionally approving the rest of the run: it bypasses later tool prompts in that run.
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

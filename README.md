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

## Upgrading nvim-treesitter to the rewritten version (v1 / main branch post-2025)

The rewritten nvim-treesitter dropped the `nvim-treesitter.configs` module entirely. If you upgrade and see `module 'nvim-treesitter.configs' not found`, update `lua/marten/plugins/treesitter.lua` as follows:

**Old API** (`init` + `nvim-treesitter.configs`):
```lua
init = function()
  require('nvim-treesitter').install { 'lua', 'typescript', ... }
end
```

**New API** — the `init` hook still works for parser installation, but `highlight` and `indent` must be configured manually since they are no longer part of the plugin's setup. Replace the entire `config` block with:

```lua
init = function()
  require('nvim-treesitter').install { 'lua', 'typescript', ... }
end,
config = function()
  vim.api.nvim_create_autocmd('FileType', {
    callback = function()
      local ok = pcall(vim.treesitter.start)
      if ok then
        vim.bo.indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
      end
    end,
  })
end,
```

Highlighting and indentation are now provided by Neovim's built-in treesitter APIs (`vim.treesitter`). The `ensure_installed` / `highlight` / `indent` keys inside `nvim-treesitter.configs.setup` no longer exist.

Run `pi install npm:pi-nvim` after installing pi.dev.

## C/C++ (clangd) with the Xcode toolchain on macOS

When a C/C++/Obj-C project builds with the Xcode toolchain (Swift C++ interop, a beta SDK, etc.), clangd needs a few things or those files show red everywhere. The nvim side lives in `lua/marten/plugins/lsp/lsp-config.lua` (see the `clangd` / `sourcekit` blocks):

1. **Toolchain clangd, not Mason's.** clangd is launched via `xcrun -f clangd` so it follows `xcode-select`. Mason's LLVM clangd can't parse toolchain-generated headers (e.g. Swift C++ interop headers) or the beta SDK and floods every file with errors.
2. **sourcekit-lsp is restricted to `filetypes = { 'swift' }`.** By default it also claims C/C++/Obj-C and spawns its own arg-less clangd (`-compile_args_from=lsp`, no `compile_commands.json`), which attaches alongside the real clangd and paints includes red. Symptom: red in `.cpp` but not `.mm`. Diagnose with `ps -Ao pid,ppid,command | grep clangd` — a clangd whose parent is `sourcekit-lsp` is the culprit.

Two pieces may live **outside** this repo (not version-controlled here):

3. **`~/Library/Preferences/clangd/config.yaml`** — adds `-I` search paths for build-generated headers that `compile_commands.json` omits (e.g. a `<Module>-Swift.h` under Xcode's DerivedSources). Scope it to your project with `If: PathMatch:`. Handy as a temporary workaround for an in-progress C++↔Swift interop change; delete it once the include is gone.
4. **`<project>/build/.../compile_commands.json`** — the fixed path your repo's `.clangd` points clangd at. If the build regenerates the DB somewhere under a build dir, symlink this fixed path to the newest one so it doesn't go stale.

Verify a file parses clean without opening the editor:

```bash
"$(xcrun -f clangd)" --check=<path/to/file.cpp> 2>&1 | grep "checks completed"
```

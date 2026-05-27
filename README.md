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

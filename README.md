> [!WARNING]
> This was at some time the `main` branch. However, I've re-written the complete history at one point to protect some personal details.

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

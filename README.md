If using macOS, your NeoVim config is located under `~/.config/nvim`.

You'll have to download a [NerdFont](https://www.nerdfonts.com/font-downloads) in order to display icons correctly. If using iTerm navigate to Settings > Profiles > Your Profile > Text and activate "Use a different font for non-ASCII text". Additionally select a Nerd Font as the Non-ASCII Font.

Additionally you'll need to [setup coq_nvim](https://github.com/ms-jpq/coq_nvim?tab=readme-ov-file#installation) after installing the plugin.

Some formatters are pre-configured like `stylua` for Lua. You need to install the following formatters, if you want to use them:

**Lua**:
- `brew install stylua`

If you want to use the debugger, you'll have to install some tools depending on the language you want to debug:
- [Go](https://github.com/mfussenegger/nvim-dap/wiki/Debug-Adapter-installation#go)

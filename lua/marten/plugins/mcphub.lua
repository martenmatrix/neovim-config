return {
  "ravitemer/mcphub.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
  },
  build = "bundled_build.lua",
  opts = {
    config = vim.fn.expand("~/.copilot/mcp-config.json"),
    use_bundled_binary = true,
    auto_approve = true,
    extensions = {
      avante = {
        enabled = true,
        make_slash_commands = true,
      },
    },
    workspace = {
      enabled = false,
    },
  },
}

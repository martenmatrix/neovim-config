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
    on_ready = function(hub)
      local directory = vim.fn.stdpath('config') .. '/tools/figma-copilot-bridge'
      local path = directory .. '/nvim.lua'
      local installed = vim.fn.filereadable(directory .. '/dist/src/index.js') == 1
      if
        vim.g.figma_copilot_bridge ~= false
        and vim.fn.filereadable(path) == 1
        and (vim.g.figma_copilot_bridge == true or installed)
      then
        local bridge = package.loaded['figma-copilot-bridge'] or dofile(path)
        bridge.setup(hub)
      end
    end,
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

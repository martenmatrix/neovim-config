return {
  'williamboman/mason.nvim', -- used for installing lsp servers and debug adapters
  lazy = false, -- do load instantly because it needs to be loaded before mason-lspconfig in plugins/lsp

  config = function()
    local mason = require 'mason'
    mason.setup {}
  end,
}

return {
  'mfussenegger/nvim-dap',
  dependencies = {
    'rcarriga/nvim-dap-ui', -- ui when debugging
    'nvim-neotest/nvim-nio', -- needed for nvim-dap ui
    'theHamsta/nvim-dap-virtual-text', -- live evaluation of variables
    'nvim-telescope/telescope-dap.nvim', -- telescope features for dap
    'leoluz/nvim-dap-go', -- easy nvim-dap config for go with neat additional features
    'jay-babu/mason-nvim-dap.nvim', -- use mason to install debug adapters
  },

  config = function()
    local dap = require 'dap'
    local ui = require 'dapui'
    local dap_go = require 'dap-go'
    local virtual_text = require 'nvim-dap-virtual-text'
    local mason_dap = require 'mason-nvim-dap'

    mason_dap.setup {
      ensure_installed = { 'delve' },
    }
    ui.setup()
    dap_go.setup()
    virtual_text.setup {}
    -- for golang
    -- you'll have to install delve with go install github.com/go-delve/delve/cmd/dlv@latest
    local setup_go_debugging_keymaps = function()
      vim.keymap.set(
        'n',
        '<leader>dt',
        ':lua require("dap-go").debug_test()<CR>',
        { desc = 'Debug closest method above cursor', buffer = true }
      )
      vim.keymap.set(
        'n',
        '<leader>dp',
        ':lua require("dap-go").debug_last_test()<CR>',
        { desc = 'Debug previous run test', buffer = true }
      )
    end
    vim.api.nvim_create_autocmd('FileType', {
      pattern = 'go',
      callback = setup_go_debugging_keymaps,
    })
  end,
}

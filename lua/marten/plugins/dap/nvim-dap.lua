return {
  'mfussenegger/nvim-dap',
  dependencies = {
    'rcarriga/nvim-dap-ui',
    'nvim-neotest/nvim-nio',
    'theHamsta/nvim-dap-virtual-text',
    'nvim-telescope/telescope-dap.nvim',

    'leoluz/nvim-dap-go',
  },

  config = function()
    local dap = require 'dap'
    local ui = require 'dapui'
    local dap_go = require 'dap-go'
    local virtual_text = require 'nvim-dap-virtual-text'
    ui.setup()
    virtual_text.setup()

    -- for golang
    -- you'll have to install delve with go install github.com/go-delve/delve/cmd/dlv@latest
    dap_go.setup()
    dap.adapters.go = {
      type = 'executable',
      command = 'node',
      args = { os.getenv 'HOME' .. '/dev/golang/vscode-go/dist/debugAdapter.js' },
    }
    dap.configurations.go = {
      {
        type = 'go',
        name = 'Debug',
        request = 'launch',
        showLog = false,
        program = '${file}',
        dlvToolPath = vim.fn.exepath 'dlv', -- Adjust to where delve is installed
      },
    }
  end,
}

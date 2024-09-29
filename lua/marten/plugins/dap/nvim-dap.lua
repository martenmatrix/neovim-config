return {
  'mfussenegger/nvim-dap',
  dependencies = {
    {
      'rcarriga/nvim-dap-ui', -- ui when debugging

      dependencies = {
        'nvim-neotest/nvim-nio', -- needed for nvim-dap ui
      },
    },
    'theHamsta/nvim-dap-virtual-text', -- live evaluation of variables
    'nvim-telescope/telescope-dap.nvim', -- telescope features for dap
    'leoluz/nvim-dap-go', -- easy nvim-dap config for go with neat additional features
    'jay-babu/mason-nvim-dap.nvim', -- use mason to install debug adapters
  },

  config = function()
    local dap = require 'dap'
    local dapui = require 'dapui'
    local dap_go = require 'dap-go'
    local virtual_text = require 'nvim-dap-virtual-text'
    local mason_dap = require 'mason-nvim-dap'

    vim.fn.sign_define('DapBreakpoint', { text = '🔰', texthl = '', linehl = '', numhl = '' })
    vim.fn.sign_define('DapBreakpointCondition', { text = '❓', texthl = '', linehl = '', numhl = '' })
    vim.fn.sign_define('DapBreakpointCondition', { text = '📩', texthl = '', linehl = '', numhl = '' })
    vim.fn.sign_define('DapStopped', { text = '➡️', texthl = '', linehl = '', numhl = '' })
    vim.fn.sign_define('DapBreakpointRejected', { text = '❌', texthl = '', linehl = '', numhl = '' })

    mason_dap.setup {
      automatic_installation = true,
      ensure_installed = { 'delve', 'js' }, -- TODO somehow js-debug-adapter is not automatically installed
    }

    dapui.setup()

    if not dap.adapters['pwa-node'] then
      require('dap').adapters['pwa-node'] = {
        type = 'server',
        host = 'localhost',
        port = '${port}',
        executable = {
          command = 'node',
          -- 💀 Make sure to update this path to point to your installation
          args = {
            require('mason-registry').get_package('js-debug-adapter'):get_install_path()
              .. '/js-debug/src/dapDebugServer.js',
            '${port}',
          },
        },
      }
    end
    if not dap.adapters['node'] then
      dap.adapters['node'] = function(cb, config)
        if config.type == 'node' then
          config.type = 'pwa-node'
        end
        local nativeAdapter = dap.adapters['pwa-node']
        if type(nativeAdapter) == 'function' then
          nativeAdapter(cb, config)
        else
          cb(nativeAdapter)
        end
      end
    end

    for _, language in ipairs { 'typescript', 'javascript', 'typescriptreact', 'javascriptreact' } do
      if not dap.configurations[language] then
        dap.configurations[language] = {
          {
            type = 'pwa-node',
            request = 'launch',
            name = 'Launch file',
            program = '${file}',
            cwd = '${workspaceFolder}',
          },
          {
            type = 'pwa-node',
            request = 'attach',
            name = 'Attach',
            processId = require('dap.utils').pick_process,
            cwd = '${workspaceFolder}',
          },
        }
      end
    end

    -- open and close dapui automatically
    dap.listeners.before.attach.dapui_config = function()
      vim.cmd 'NvimTreeClose'
      dapui.open()
    end
    dap.listeners.before.launch.dapui_config = function()
      vim.cmd 'NvimTreeClose'
      dapui.open()
    end
    dap.listeners.before.event_terminated.dapui_config = function()
      -- dapui.close()
    end
    dap.listeners.before.event_exited.dapui_config = function()
      -- dapui.close()
    end

    dap_go.setup()
    virtual_text.setup {}

    local setup_dap_keymaps = function()
      vim.keymap.set('n', '<F5>', function()
        dap.continue()
      end, { desc = 'Continue debugging' })
      vim.keymap.set('n', '<F10>', function()
        dap.step_over()
      end, { desc = 'Step over' })
      vim.keymap.set('n', '<F11>', function()
        dap.step_into()
      end, { desc = 'Step into' })
      vim.keymap.set('n', '<F12>', function()
        dap.step_out()
      end, { desc = 'Step out' })
      vim.keymap.set('n', '<Leader>b', function()
        dap.toggle_breakpoint()
      end, { desc = 'Toggle breakpoint' })
      vim.keymap.set('n', '<Leader>lp', function()
        dap.set_breakpoint(nil, nil, vim.fn.input 'Log point message: ')
      end, { desc = 'Set a log point' })
      vim.keymap.set('n', '<Leader>dl', function()
        dap.run_last()
      end, { desc = 'Debug last' })
      -- eval var under cursor
      vim.keymap.set('n', '<leader>d?', function()
        dapui.eval(nil, { enter = true })
      end, { desc = 'Evaluate hovered expression' })
    end
    setup_dap_keymaps()

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

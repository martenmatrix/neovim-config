return {
  -- NOTE ABOUT GIT TIMEOUT (5 git jobs have timed out...), this is often caused by .idea folders which can just be removed (run time git --no-optional-locks status --porcelain=v1 --ignored=matching -u to see why git is taking so long) (https://github.com/nvim-tree/nvim-tree.lua/discussions/2737#discussioncomment-8977898)
  'nvim-tree/nvim-tree.lua',
  dependencies = 'nvim-tree/nvim-web-devicons',
  config = function()
    local nvimtree = require 'nvim-tree'

    -- recommended settings from nvim-tree documentation
    vim.g.loaded_netrw = 1
    vim.g.loaded_netrwPlugin = 1

    nvimtree.setup {
      view = {
        width = 50,
        relativenumber = true,
      },
      -- change folder arrow icons
      renderer = {
        indent_markers = {
          enable = true,
        },
        icons = {
          glyphs = {
            folder = {
              arrow_closed = '', -- arrow when folder is closed
              arrow_open = '', -- arrow when folder is open
            },
          },
        },
      },
      -- disable window_picker for
      -- explorer to work well with
      -- window splits
      actions = {
        open_file = {
          window_picker = {
            enable = true,
          },
        },
      },
      filters = {
        custom = { '.DS_Store' },
        git_ignored = true,
      },
      git = {
        ignore = true,
      },
      update_focused_file = {
        enable = true,
      },
      on_attach = function(bufnr)
        local api = require 'nvim-tree.api'
        api.config.mappings.default_on_attach(bufnr)

        -- set keymaps
        local keymap = vim.keymap -- for conciseness

        -- remove quit keymap to not conflict with persistence
        keymap.del('n', 'q', { buffer = bufnr })

        keymap.set(
          'n',
          '<leader>ee',
          '<cmd>NvimTreeToggle<CR>',
          { desc = 'Toggle file explorer', buffer = bufnr, noremap = true, silent = true, nowait = true }
        ) -- toggle file explorer
        keymap.set(
          'n',
          '<leader>ef',
          '<cmd>NvimTreeFindFileToggle<CR>',
          { desc = 'Toggle file explorer on current file' }
        ) -- toggle file explorer on current file
        keymap.set(
          'n',
          '<leader>ec',
          '<cmd>NvimTreeCollapse<CR>',
          { desc = 'Collapse file explorer', buffer = bufnr, noremap = true, silent = true, nowait = true }
        ) -- collapse file explorer
        keymap.set(
          'n',
          '<leader>er',
          '<cmd>NvimTreeRefresh<CR>',
          { desc = 'Refresh file explorer', buffer = bufnr, noremap = true, silent = true, nowait = true }
        ) -- refresh file explorer
      end,
    }
  end,
}

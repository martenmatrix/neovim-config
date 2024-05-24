return {
  'nvim-telescope/telescope.nvim',
  tag = '0.1.6',
  dependencies = {
    'nvim-lua/plenary.nvim',
    'BurntSushi/ripgrep', --makes telescope respect .gitignore files
    'nvim-treesitter/nvim-treesitter',
    'nvim-tree/nvim-web-devicons',
    'molecule-man/telescope-menufacture', -- context menu for options
  },
  config = function()
    local telescope = require 'telescope'
    local actions = require 'telescope.actions'

    telescope.setup {
      defaults = {
        path_display = { 'smart' },
        mappings = {
          i = {
            ['<C-k>'] = actions.move_selection_previous, -- move to prev result
            ['<C-j>'] = actions.move_selection_next, -- move to next result
            ['<C-q>'] = actions.send_selected_to_qflist + actions.open_qflist,
          },
        },
      },

      extensions = {
        menufacture = {
          mappings = {
            main_menu = { [{ 'i', 'n' }] = '<C-S>' }, -- open options context menu
          },
        },
      },
    }

    telescope.load_extension 'menufacture'

    -- set keymaps
    local keymap = vim.keymap -- for conciseness

    keymap.set('n', '<leader>ff', telescope.extensions.menufacture.find_files, { desc = 'Fuzzy find files' })
    keymap.set('n', '<leader>fr', '<cmd>Telescope oldfiles', { desc = 'Fuzzy find recent files' })
    keymap.set('n', '<leader>fs', telescope.extensions.menufacture.live_grep, { desc = 'Find string in cwd' })
    keymap.set(
      'n',
      '<leader>fc',
      telescope.extensions.menufacture.grep_string,
      { desc = 'Find string under cursor in cwd' }
    )
  end,
}

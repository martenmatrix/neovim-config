return {
  -- '0x00-ketsu/autosave.nvim',
  'nvim-lua/plenary.nvim',
  'christoomey/vim-tmux-navigator',
  { 'wakatime/vim-wakatime', lazy = false },
  'fatih/vim-go',
  {
    'windwp/nvim-autopairs',
    event = 'InsertEnter',
    config = true,
    -- use opts = {} for passing setup options
    -- this is equalent to setup({}) function
  },
  {
    'windwp/nvim-ts-autotag',
    config = function()
      require('nvim-ts-autotag').setup {}
    end,
  },
  { 'akinsho/git-conflict.nvim', config = true },
  {
    'alvarosevilla95/luatab.nvim',
    config = function()
      require('luatab').setup {}
    end,
  },
  {
    'lukas-reineke/indent-blankline.nvim',
    main = 'ibl',
    config = function()
      local hooks = require 'ibl.hooks'
      hooks.register(hooks.type.HIGHLIGHT_SETUP, function()
        vim.api.nvim_set_hl(0, 'CurrentScope', { fg = '#fc5ef3' })
      end)

      require('ibl').setup {
        scope = { highlight = { 'CurrentScope' } },
      }
    end,
  },
}

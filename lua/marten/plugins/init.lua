return {
  -- '0x00-ketsu/autosave.nvim',
  'nvim-lua/plenary.nvim',
  {
    'christoomey/vim-tmux-navigator',
    init = function()
      vim.g.tmux_navigator_no_mappings = 1
    end,
    keys = {
      { '<C-j>', '<cmd>TmuxNavigateLeft<CR>', desc = 'Move to left window' },
      { '<C-k>', '<cmd>TmuxNavigateDown<CR>', desc = 'Move to lower window' },
      { '<C-l>', '<cmd>TmuxNavigateUp<CR>', desc = 'Move to upper window' },
      -- <C-;> needs a terminal that reports it distinctly (CSI u / kitty keyboard protocol)
      { '<C-;>', '<cmd>TmuxNavigateRight<CR>', desc = 'Move to right window' },
    },
  },
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
  { 'akinsho/git-conflict.nvim', version = '*', config = true },
  {
    'alvarosevilla95/luatab.nvim',
    config = function()
      require('luatab').setup {}
    end,
  },
}

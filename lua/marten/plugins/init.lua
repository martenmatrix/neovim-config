return {
  -- '0x00-ketsu/autosave.nvim',
  'nvim-lua/plenary.nvim',
  'christoomey/vim-tmux-navigator',
  {
    'folke/tokyonight.nvim',
    lazy = false,
    priority = 1000,
    opts = {},
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
}

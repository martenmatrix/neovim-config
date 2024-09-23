return {
  -- '0x00-ketsu/autosave.nvim',
  'nvim-lua/plenary.nvim',
  'christoomey/vim-tmux-navigator',
  {
    'folke/tokyonight.nvim',
    lazy = false,
    priority = 1000,
    opts = {},
    config = function()
      vim.cmd [[colorscheme tokyonight]]
    end,
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
    'iamcco/markdown-preview.nvim',
    cmd = { 'MarkdownPreviewToggle', 'MarkdownPreview', 'MarkdownPreviewStop' },
    ft = { 'markdown' },
    build = function()
      vim.fn['mkdp#util#install']()
    end,
    config = function()
      vim.keymap.set(
        'n',
        '<leader>md',
        '<cmd>MarkdownPreview<CR>',
        { desc = 'Preview markdown in browser', buffer = true }
      )
      vim.keymap.set(
        'n',
        '<leader>mds',
        '<cmd>MarkdownPreviewStop<CR>',
        { desc = 'Stop markdown preview', buffer = true }
      )
    end,
  },
}

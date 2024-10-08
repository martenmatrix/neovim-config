return {
  'folke/which-key.nvim',
  event = 'VeryLazy',
  init = function()
    vim.o.timeout = true
    vim.o.timeoutlen = 300
    vim.keymap.set('n', '<leader>hw', '<cmd>WhichKey<CR>', { desc = 'Show which-key help' })
  end,
  opts = {
    keys = {
      scroll_down = '<C-j>', -- binding to scroll down inside the popup
      scroll_up = '<C-k>', -- binding to scroll up inside the popup
    },
  },
}

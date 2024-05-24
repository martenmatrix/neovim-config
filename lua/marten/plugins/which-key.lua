return {
  'folke/which-key.nvim',
  event = 'VeryLazy',
  init = function()
    vim.o.timeout = true
    vim.o.timeoutlen = 300
  end,
  opts = {
    popup_mappings = {
      scroll_down = '<C-j>', -- binding to scroll down inside the popup
      scroll_up = '<C-k>', -- binding to scroll up inside the popup
    },
  },
}

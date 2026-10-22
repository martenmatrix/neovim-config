return {
  'lewis6991/gitsigns.nvim',
  config = function()
    require('gitsigns').setup {
      current_line_blame = true,
      current_line_blame_formatter = '<author>, <author_time:%d.%m.%y %H:%M> - <summary>',
    }
    -- Review only; commit only when the user explicitly asks.
    vim.keymap.set('n', '<leader>gd', '<cmd>Gitsigns diff<CR>', { desc = 'Git: review changes' })
  end,
}

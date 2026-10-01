vim.keymap.set('t', '<Esc><Esc>', [[<C-\><C-n>]], { desc = 'Exit terminal mode' })

local group = vim.api.nvim_create_augroup('custom-term-open', { clear = true })

vim.api.nvim_create_autocmd('TermOpen', {
  group = group,
  callback = function()
    vim.opt_local.number = false
    vim.opt_local.relativenumber = false
  end,
})

vim.keymap.set('n', '<leader>tT', function()
  local win = require('marten.core.windows').ensure_file_window()
  vim.api.nvim_set_current_win(win)
  vim.cmd 'belowright 15split | term'
  vim.opt_local.winfixheight = true
end, { desc = 'Open terminal' })

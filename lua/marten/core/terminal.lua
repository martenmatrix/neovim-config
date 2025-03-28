-- https://www.youtube.com/watch?v=ooTcnx066Do

vim.api.nvim_create_autocmd('TermOpen', {
  group = vim.api.nvim_create_augroup('custom-term-open', { clear = true }),
  callback = function()
    vim.opt.number = false
    vim.opt.relativenumber = false

    vim.keymap.set('t', '<Esc>', '<C-\\><C-n>', { buffer = 0, desc = 'Exit terminal mode' })
  end,
})

vim.keymap.set('n', '<leader>tT', function()
  vim.cmd.vnew()
  vim.cmd.term()
  vim.cmd.wincmd 'J'
  vim.api.nvim_win_set_height(0, 15)
end, { desc = 'Open terminal' })

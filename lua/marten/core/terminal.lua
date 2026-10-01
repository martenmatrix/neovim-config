-- https://www.youtube.com/watch?v=ooTcnx066Do

vim.keymap.set('t', '<Esc><Esc>', [[<C-\><C-n>]], { desc = 'Exit terminal mode' })

vim.api.nvim_create_autocmd('TermOpen', {
  group = vim.api.nvim_create_augroup('custom-term-open', { clear = true }),
  callback = function()
    vim.opt_local.number = false
    vim.opt_local.relativenumber = false
    vim.opt_local.winfixheight = true
    vim.opt_local.winfixwidth = true
  end,
})

vim.keymap.set('n', '<leader>tT', function()
  vim.cmd('botright 15split | term')
end, { desc = 'Open terminal' })

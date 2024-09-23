return {
  'fatih/vim-go',
  config = function()
    vim.api.nvim_create_autocmd('BufWritePre', {
      pattern = '*.go',
      callback = function()
        vim.cmd 'Fmt'
      end,
    })
  end,
}

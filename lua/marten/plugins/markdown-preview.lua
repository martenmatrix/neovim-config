return {
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
}

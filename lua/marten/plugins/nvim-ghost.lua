return {
  'subnut/nvim-ghost.nvim',
  config = function()
    -- doing it with vim.api and vim.bo.filetype = "typst" somehow does not start the lsp
    vim.cmd [[
      augroup nvim_ghost_user_autocommands
        au User *typst.app setfiletype typst 
      augroup END
    ]]
  end,
}

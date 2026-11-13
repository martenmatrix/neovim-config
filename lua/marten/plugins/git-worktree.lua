return {
  'polarmutex/git-worktree.nvim',
  tag = '2.1.0',
  dependencies = { 'nvim-lua/plenary.nvim', 'nvim-telescope/telescope.nvim', 'olimorris/codecompanion.nvim' },
  keys = {
    {
      '<leader>wn',
      function()
        require('marten.core.worktrees').new()
      end,
      desc = 'Worktrees: new isolated AI task',
    },
    {
      '<leader>ww',
      function()
        require('marten.core.worktrees').pick()
      end,
      desc = 'Worktrees: open in a task tab',
    },
  },
  init = function()
    vim.g.git_worktree = {
      change_directory_command = 'tcd',
      clearjumps_on_change = false,
      autopush = false,
    }
  end,
}

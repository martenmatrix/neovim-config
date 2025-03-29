-- Configure session directory
local state_dir = vim.fn.stdpath('state') or vim.fn.stdpath('data')
local session_dir = state_dir .. '/sessions/'

-- Create directory if it doesn't exist
vim.fn.mkdir(session_dir, "p")  -- "p" flag creates parent directories

return {
  'folke/persistence.nvim',
  event = 'BufReadPre', -- this will only start session saving when an actual file was opened
  opts = {
    dir = session_dir,
  },
  config = function()
    vim.keymap.set('n', '<leader>qs', function()
      require('persistence').load()
    end, { desc = 'Load the session for the current directory' })

    vim.keymap.set('n', '<leader>qS', function()
      require('persistence').select()
    end, { desc = 'Select a session to load' })

    vim.keymap.set('n', '<leader>ql', function()
      require('persistence').load { last = true }
    end, { desc = 'Load the last session' })

    vim.keymap.set('n', '<leader>qd', function()
      require('persistence').stop()
    end, { desc = "Stop Persistence => Session won't be saved on exit" })
  end,
}

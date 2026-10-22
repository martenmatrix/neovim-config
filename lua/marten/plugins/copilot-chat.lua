return {
  {
    'CopilotC-Nvim/CopilotChat.nvim',
    cond = false,
    dependencies = {
      { 'nvim-lua/plenary.nvim', branch = 'master' },
    },
    build = 'make tiktoken',
    opts = {
      -- See Configuration section for options
    },
  },
}

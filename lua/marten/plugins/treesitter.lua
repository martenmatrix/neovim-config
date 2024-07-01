return {
  'nvim-treesitter/nvim-treesitter',

  config = function()
    require('nvim-treesitter.configs').setup {
      ensure_installed = {
        'json',
        'javascript',
        'typescript',
        'tsx',
        'yaml',
        'html',
        'css',
        'prisma',
        'markdown',
        'markdown_inline',
        'svelte',
        'graphql',
        'bash',
        'lua',
        'vim',
        'dockerfile',
        'gitignore',
        'query',
        'vimdoc',
        'c',
        'styled', -- styled-components
      },
      ignore_install = {},
      sync_install = false,
      auto_install = false,
      highlight = {
        enable = true,
      },
      incremental_selection = { enable = true },
      textobjects = { enable = true },
      indent = {
        enable = true,
      },
      modules = {},
    }
  end,
}

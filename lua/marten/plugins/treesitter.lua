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
      auto_install = true,
      highlight = {
        enable = true,
      },
      incremental_selection = { enable = true },
      textobjects = { enable = true },
      indent = {
        enable = true,
      },
    }
  end,
}

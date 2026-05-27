return {
  'nvim-treesitter/nvim-treesitter',
  lazy = false,
  build = ':TSUpdate',
  init = function()
    require('nvim-treesitter').install {
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
      'python',
    }
  end,
}

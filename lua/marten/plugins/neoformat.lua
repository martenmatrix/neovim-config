return {
  'sbdchd/neoformat',

  config = function()
    -- Enable alignment globally
    vim.g.neoformat_basic_format_align = 1

    -- Enable tab to spaces conversion globally
    vim.g.neoformat_basic_format_retab = 1

    -- Enable trimmming of trailing whitespace globally
    vim.g.neoformat_basic_format_trim = 1

    -- LUA
    -- CONFIG
    -- use stylua for lua formatting
    vim.g.neoformat_enabled_lua = { 'stylua' }

    -- PRETTIER, TYPESCRIPT, JAVASCRIPT
    -- CONFIG
    -- look for project-local version of prettier first
    vim.g.neoformat_try_node_exe = 1

    vim.g.neoformat_enabled_javascript = { 'prettier' }
    vim.g.neoformat_enabled_javascriptreact = { 'prettier' } -- JSX
    vim.g.neoformat_enabled_typescript = { 'prettier' }
    vim.g.neoformat_enabled_typescriptreact = { 'prettier' } -- TSX
    vim.g.neoformat_enabled_json = { 'prettier' }
    vim.g.neoformat_enabled_css = { 'prettier' }
    vim.g.neoformat_enabled_scss = { 'prettier' }
    vim.g.neoformat_enabled_less = { 'prettier' }
    vim.g.neoformat_enabled_html = { 'prettier' }
    vim.g.neoformat_enabled_vue = { 'prettier' }
    vim.g.neoformat_enabled_yaml = { 'prettier' }
    vim.g.neoformat_enabled_markdown = { 'prettier' }
    vim.g.neoformat_enabled_graphql = { 'prettier' }
    vim.g.neoformat_enabled_mdx = { 'prettier' }
    vim.g.neoformat_enabled_solidity = { 'prettier' }

    -- GO
    -- CONFIG
    vim.g.neoformat_enabled_go = { 'go-fmt' }

    vim.keymap.set('n', '<leader>fo', function()
      vim.cmd [[try | undojoin | silent Neoformat go-fmt | catch /E790/ | silent Neoformat go-fmt | endtry]]
    end, { desc = 'Format code' })
  end,
}

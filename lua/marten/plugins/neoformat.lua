return {
  'sbdchd/neoformat',

  config = function()
    -- Enable alignment globally
    vim.g.neoformat_basic_format_align = 1

    -- Enable tab to spaces conversion globally
    vim.g.neoformat_basic_format_retab = 1

    -- Enable trimmming of trailing whitespace globally
    vim.g.neoformat_basic_format_trim = 1

    -- create group, which clears itself after config-reload to prevent autocmd duplicates
    local format_group = vim.api.nvim_create_augroup('FormatGroup', { clear = true })

    -- LUA
    -- CONFIG
    -- use stylua for lua formatting
    vim.g.neoformat_enabled_lua = { 'stylua' }

    -- auto-format lua on save
    vim.api.nvim_create_autocmd('BufWritePre', {
      group = format_group,
      pattern = '*.lua',
      callback = function()
        vim.cmd 'Neoformat stylua'
      end,
    })

    -- PRETTIER, TYPESCRIPT, JAVASCRIPT
    -- CONFIG
  end,
}

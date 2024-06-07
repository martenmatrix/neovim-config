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
    vim.api.nvim_create_autocmd('CursorHold', {
      group = format_group,
      pattern = '*.lua',

      callback = function()
        local file_path = vim.fn.expand '%'
        local changed_files = vim.system({ 'git', 'diff', '--name-only' }, { text = true }):wait()
        if string.find(changed_files.stdout, file_path) then
          print 'Current file was not modified. Did you forget to :w?'
          return nil
        end

        --        local diff_output = vim.fn.system(string.format('git diff --unified=0 --minimal %s', file_path))
        --   print(diff_output)

        print('Current file path: ' .. file_path)

        vim.cmd [[try | undojoin | silent Neoformat stylua | catch /E790/ | silent Neoformat stylua | endtry]]
      end,
    })

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

    vim.api.nvim_create_autocmd('CursorHold', {
      group = format_group,
      pattern = {
        '*.js',
        '*.jsx',
        '*.ts',
        '*.tsx',
        '*.json',
        '*.css',
        '*.scss',
        '*.less',
        '*.html',
        '*.vue',
        '*.yaml',
        '*.yml',
        '*.md',
        '*.graphql',
        '*.gql',
        '*.mdx',
        '*.sol',
      },
      callback = function()
        vim.cmd [[try | undojoin | silent Neoformat prettier | catch /E790/ | silent Neoformat prettier | endtry]]
      end,
    })

    -- GO
    -- CONFIG
    vim.g.neoformat_enabled_go = { 'go-fmt' }

    -- auto-format lua on save
    vim.api.nvim_create_autocmd('CursorHold', {
      group = format_group,
      pattern = '*.go',
      callback = function()
        vim.cmd [[try | undojoin | silent Neoformat go-fmt | catch /E790/ | silent Neoformat go-fmt | endtry]]
      end,
    })

    vim.keymap.set('n', '<leader>fo', '<cmd>:Neoformat<CR>', { desc = 'Format code' })
  end,
}

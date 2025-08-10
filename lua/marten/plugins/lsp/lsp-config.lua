return {
  'nvim-lspconfig',
  dependencies = {
    'williamboman/mason-lspconfig.nvim',
    'hrsh7th/cmp-nvim-lsp',
    {
      'folke/lazydev.nvim',
      ft = 'lua', -- only load on lua files
      opts = {
        library = {
          -- See the configuration section for more details
          -- Load luvit types when the `vim.uv` word is found
          { path = 'luvit-meta/library', words = { 'vim%.uv' } },
        },
      },
    },
    { 'Bilal2453/luvit-meta', lazy = true }, -- optional `vim.uv` typings
  },
  config = function()
    -- vim.g.coq_settings needs to be set before lazys setup function is called, thus those settings are located in the init file

    local lspconfig = require 'lspconfig'
    local mason_lspconfig = require 'mason-lspconfig'
    local cmp_nvim_lsp = require 'cmp_nvim_lsp'

    local capabilities = cmp_nvim_lsp.default_capabilities()

    local setup_keymaps = function()
      vim.keymap.set('n', 'K', vim.lsp.buf.hover, { buffer = 0, desc = 'Show documentation for hovered text' })
      vim.keymap.set('n', 'gd', vim.lsp.buf.definition, { buffer = 0, desc = 'Go to definition' })
      vim.keymap.set('n', 'gt', vim.lsp.buf.type_definition, { buffer = 0, desc = 'Go to type definition' })
      vim.keymap.set('n', 'gi', vim.lsp.buf.implementation, { buffer = 0, desc = 'Go to implementation' })
      vim.keymap.set('n', 'gr', vim.lsp.buf.rename, { buffer = 0, desc = 'Rename' })
      vim.keymap.set(
        'n',
        'gw',
        vim.diagnostic.open_float,
        { buffer = 0, desc = 'Show warning/error in a floating window' }
      )
    end

    vim.api.nvim_create_autocmd('LspAttach', {
      group = vim.api.nvim_create_augroup("my.lsp.keys", {}),
      callback = function()
        setup_keymaps()
      end
    })

    vim.lsp.config('*', {
      capabilities = capabilities,
    })

    vim.lsp.config('lua_ls', {
      on_init = function(client)
        if client.workspace_folders then
          local path = client.workspace_folders[1].name
          if
            path ~= vim.fn.stdpath 'config'
            and (vim.uv.fs_stat(path .. '/.luarc.json') or vim.uv.fs_stat(path .. '/.luarc.jsonc'))
          then
            return
          end
        end

        client.config.settings.Lua = vim.tbl_deep_extend('force', client.config.settings.Lua, {
          runtime = {
            -- Tell the language server which version of Lua you're using (most
            -- likely LuaJIT in the case of Neovim)
            version = 'LuaJIT',
            -- Tell the language server how to find Lua modules same way as Neovim
            -- (see `:h lua-module-load`)
            path = {
              'lua/?.lua',
              'lua/?/init.lua',
            },
          },
          -- Make the server aware of Neovim runtime files
          workspace = {
            checkThirdParty = false,
            library = {
              vim.env.VIMRUNTIME,
              -- Depending on the usage, you might want to add additional paths
              -- here.
              -- '${3rd}/luv/library'
              -- '${3rd}/busted/library'
            },
            -- Or pull in all of 'runtimepath'.
            -- NOTE: this is a lot slower and will cause issues when working on
            -- your own configuration.
            -- See https://github.com/neovim/nvim-lspconfig/issues/3189
            -- library = {
            --   vim.api.nvim_get_runtime_file('', true),
            -- }
          },
        })
      end,
      settings = {
        Lua = {},
      },
    })

    vim.lsp.config('ts_ls', {
      init_options = {
        -- https://github.com/typescript-language-server/typescript-language-server/blob/master/docs/configuration.md
        plugins = {
          {
            name = '@styled/typescript-styled-plugin',
            location = '/Users/mbitterling/.nvm/versions/node/v20.15.0/lib/node_modules',
          },
        },
        tsserver = {
          logVerbosity = 'off',
        },
      },
    })

    vim.lsp.config('eslint', {
      dynamicRegistration = true,
    })

    mason_lspconfig.setup {
      automatic_installation = true,
      ensure_installed = { 'ts_ls', 'html', 'cssls', 'eslint', 'lua_ls', 'gopls', 'tinymist' },
    }

    vim.lsp.enable({"ts_ls", 'lua_ls', 'eslint', 'html', 'cssls', 'gopls', 'tinymist'})

    vim.lsp.set_log_level 'off'
  end,
}

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

    mason_lspconfig.setup {
      ensure_installed = { 'tsserver', 'html', 'cssls', 'eslint', 'lua_ls', 'gopls' },
    }

    vim.lsp.set_log_level 'trace'

    mason_lspconfig.setup_handlers {
      -- default handler
      function(server_name)
        lspconfig[server_name].setup {
          capabilities = capabilities,
          on_attach = setup_keymaps,
        }
      end,
      ['lua_ls'] = function()
        -- configure lua server (with special settings)
        lspconfig['lua_ls'].setup {
          capabilities = capabilities,
          root_dir = lspconfig.util.root_pattern(
            'init.lua',
            '.luarc.json',
            '.luarc.jsonc',
            '.luacheckrc',
            '.stylua.toml',
            'stylua.toml',
            'selene.toml',
            'selene.yml',
            '.git'
          ),
          on_attach = setup_keymaps,
        }
      end,
      ['tsserver'] = function()
        lspconfig['tsserver'].setup {
          capabilities = capabilities,
          init_options = {
            -- https://github.com/typescript-language-server/typescript-language-server/blob/master/docs/configuration.md
            plugins = {
              {
                name = '@styled/typescript-styled-plugin',
                location = '/Users/martenb/.nvm/versions/node/v22.0.0/lib/node_modules',
              },
            },
            tsserver = {
              logVerbosity = 'off',
            },
          },
          on_attach = setup_keymaps,
        }
      end,
      ['eslint'] = function()
        lspconfig['eslint'].setup {
          capabilities = capabilities,
          dynamicRegistration = true,
          on_attach = setup_keymaps,
        }
      end,
    }
  end,
}

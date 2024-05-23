return {
  'nvim-lspconfig',
  dependencies = {
    'williamboman/mason-lspconfig.nvim',
    'hrsh7th/cmp-nvim-lsp',
  },
  config = function()
    local lspconfig = require 'lspconfig'
    local mason_lspconfig = require 'mason-lspconfig'
    local cmp_nvim_lsp = require 'cmp_nvim_lsp'

    -- used to enable autocompletion (assign to every lsp server config)
    local capabilities = cmp_nvim_lsp.default_capabilities()

    mason_lspconfig.setup_handlers {
      -- default handler
      function(server_name)
        lspconfig[server_name].setup {
          capabilities = capabilities,
          on_attach = function()
            -- will run inside every buffer when they first get attached to lsp
            vim.keymap.set('n', 'K', vim.lsp.buf.hover, { buffer = 0, desc = 'Show documentation for hovered text' })
          end,
        }
      end,
      ['lua_ls'] = function()
        -- configure lua server (with special settings)
        lspconfig['lua_ls'].setup {
          capabilities = capabilities,
          settings = {
            Lua = {
              -- make the language server recognize "vim" global
              diagnostics = {
                globals = { 'vim' },
              },
            },
          },
        }
      end,
    }
  end,
}

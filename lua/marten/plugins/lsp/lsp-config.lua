return {
  'nvim-lspconfig',
  dependencies = {
    'williamboman/mason-lspconfig.nvim',
    'ms-jpq/coq_nvim',
    'ms-jpq/coq.artifacts',
    'ms-jpq/coq.thirdparty',
  },
  config = function()
    -- vim.g.coq_settings needs to be set before lazys setup function is called, thus those settings are located in the init file

    local lspconfig = require 'lspconfig'
    local mason_lspconfig = require 'mason-lspconfig'

    local coq = require 'coq'
    -- used to enable autocompletion (assign to every lsp server config)
    local capabilities = coq.lsp_ensure_capabilities()

    local setup_keymaps = function()
      vim.keymap.set('n', 'K', vim.lsp.buf.hover, { buffer = 0, desc = 'Show documentation for hovered text' })
      vim.keymap.set('n', 'gd', vim.lsp.buf.definition, { buffer = 0, desc = 'Go to definition' })
      vim.keymap.set('n', 'gt', vim.lsp.buf.type_definition, { buffer = 0, desc = 'Go to type definition' })
      vim.keymap.set('n', 'gi', vim.lsp.buf.implementation, { buffer = 0, desc = 'Go to implementation' })
    end

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
          on_init = function(client)
            local path = client.workspace_folders[1].name
            if vim.loop.fs_stat(path .. '/.luarc.json') or vim.loop.fs_stat(path .. '/.luarc.jsonc') then
              return
            end

            client.config.settings.Lua = vim.tbl_deep_extend('force', client.config.settings.Lua, {
              runtime = {
                -- Tell the language server which version of Lua you're using
                -- (most likely LuaJIT in the case of Neovim)
                version = 'LuaJIT',
              },
              -- Make the server aware of Neovim runtime files
              workspace = {
                checkThirdParty = false,
                library = {
                  vim.env.VIMRUNTIME,
                  -- Depending on the usage, you might want to add additional paths here.
                  -- "${3rd}/luv/library"
                  -- "${3rd}/busted/library",
                },
                -- or pull in all of 'runtimepath'. NOTE: this is a lot slower
                -- library = vim.api.nvim_get_runtime_file("", true)
              },
            })
          end,
          settings = {
            Lua = {},
          },
          on_attach = setup_keymaps,
        }
      end,
    }
  end,
}

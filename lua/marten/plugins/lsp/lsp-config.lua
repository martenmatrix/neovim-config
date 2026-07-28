return {
  'williamboman/mason-lspconfig.nvim',
  dependencies = {
    'neovim/nvim-lspconfig',
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
    local mason_lspconfig = require 'mason-lspconfig'

    local setup_keymaps = function(buffer)
      vim.keymap.set('n', 'K', vim.lsp.buf.hover, { buffer = buffer, desc = 'Show documentation for hovered text' })
      vim.keymap.set('n', 'gd', vim.lsp.buf.definition, { buffer = buffer, desc = 'Go to definition' })
      vim.keymap.set('n', 'gt', vim.lsp.buf.type_definition, { buffer = buffer, desc = 'Go to type definition' })
      vim.keymap.set('n', 'gi', vim.lsp.buf.implementation, { buffer = buffer, desc = 'Go to implementation' })
      vim.keymap.set('n', 'gr', vim.lsp.buf.rename, { buffer = buffer, desc = 'Rename' })
      vim.keymap.set('n', 'gw', vim.diagnostic.open_float, { buffer = buffer, desc = 'Show warning/error in a floating window' })
    end

    vim.api.nvim_create_autocmd('LspAttach', {
      group = vim.api.nvim_create_augroup('my.lsp.keys', {}),
      callback = function(ev)
        setup_keymaps(ev.buf)
      end,
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

    -- Only enable the styled-components TS plugin when it is actually installed
    -- on this machine, otherwise ts_ls fails to load the plugin.
    local styled_plugin_location = vim.fn.expand '~/Library/pnpm/global/5/node_modules'
    local ts_plugins = {}
    if vim.fn.isdirectory(styled_plugin_location .. '/@styled/typescript-styled-plugin') == 1 then
      table.insert(ts_plugins, {
        name = '@styled/typescript-styled-plugin',
        location = styled_plugin_location,
      })
    end

    vim.lsp.config('ts_ls', {
      root_markers = { 'package.json' },
      init_options = {
        -- https://github.com/typescript-language-server/typescript-language-server/blob/master/docs/configuration.md
        plugins = ts_plugins,
        tsserver = {
          logVerbosity = 'off',
        },
      },
      on_attach = function(_, bufnr)
        vim.keymap.set('n', '<leader>mi', function()
          vim.lsp.buf.code_action {
            apply = true,
            context = { only = { 'source.addMissingImports.ts' } },
          }
        end, { buffer = bufnr, silent = true, desc = 'TS: Add Missing Imports' })
      end,
    })

    vim.lsp.config('eslint', {
      dynamicRegistration = true,
    })

    -- Use the Xcode toolchain's own clangd (resolved via `xcrun -f clangd`, so it
    -- follows `xcode-select`) instead of Mason's standalone LLVM build. Some
    -- projects compile with the Apple/Xcode toolchain, and some sources pull in
    -- toolchain-specific generated headers (e.g. a Swift C++ interop header like
    -- `MyModule-Swift.h`, which uses the toolchain's attribute macros) plus the
    -- macOS SDK. Only the frontend + resource-dir that produced those artifacts
    -- can parse them; Mason's clangd floods the whole translation unit with errors
    -- (which then makes every symbol — project types, NSString, etc. — show red).
    -- --query-driver lets clangd inherit the driver's SDK/framework search paths.
    local clangd_cmd = 'clangd'
    if vim.fn.executable 'xcrun' == 1 then
      local resolved = vim.fn.trim(vim.fn.system 'xcrun -f clangd 2>/dev/null')
      if vim.v.shell_error == 0 and resolved ~= '' and vim.fn.filereadable(resolved) == 1 then
        clangd_cmd = resolved
      end
    end
    vim.lsp.config('clangd', {
      cmd = {
        clangd_cmd,
        '--query-driver=/usr/bin/clang++,/usr/bin/clang,'
          .. '/Applications/Xcode*.app/Contents/Developer/Toolchains/**/clang*,'
          .. '/Library/Developer/CommandLineTools/usr/bin/clang*',
      },
    })

    local languages = { 'ts_ls', 'html', 'cssls', 'eslint', 'lua_ls', 'gopls', 'tinymist', 'pyright', 'denols', 'jdtls', 'clangd' }

    mason_lspconfig.setup {
      automatic_installation = true,
      ensure_installed = languages,
    }

    vim.lsp.enable(languages)

    -- sourcekit-lsp ships with the Swift/Xcode toolchain and is not installable
    -- via Mason, so enable it separately from the Mason-managed servers.
    -- Restrict it to Swift: by default sourcekit-lsp also claims C/C++/Obj-C and,
    -- for those, spawns its own clangd with `-compile_args_from=lsp` (no
    -- compile_commands.json, so no include paths). That second server attaches
    -- alongside our real clangd and floods C-family buffers with red diagnostics
    -- (unresolved project symbols, custom macros, etc.). Let clangd own the
    -- C-family filetypes; sourcekit-lsp handles only Swift.
    vim.lsp.config('sourcekit', {
      filetypes = { 'swift' },
    })
    vim.lsp.enable 'sourcekit'

    vim.lsp.log.set_level 'off'
  end,
}

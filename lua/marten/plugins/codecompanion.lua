local bridge =
  vim.fs.normalize(vim.fs.dirname(debug.getinfo(1, 'S').source:sub(2)) .. '/../../../tools/figma-copilot-bridge')
local bridge_config = vim.json.encode {
  mcpServers = {
    figma_bridge = {
      type = 'stdio',
      command = 'node',
      args = { bridge .. '/dist/src/index.js', '--auto-approve' },
      tools = { '*' },
      timeout = 375000,
    },
  },
}

return {
  'olimorris/codecompanion.nvim',
  tag = 'v19.27.0',
  build = 'npm --prefix '
    .. vim.fn.shellescape(bridge)
    .. ' ci && npm --prefix '
    .. vim.fn.shellescape(bridge)
    .. ' run build',
  cmd = { 'CodeCompanionChat', 'CodeCompanionActions', 'CodeCompanionCodeReview' },
  dependencies = { 'nvim-lua/plenary.nvim', 'nvim-treesitter/nvim-treesitter', 'saghen/blink.cmp' },
  keys = {
    {
      '<leader>aa',
      function()
        require('marten.core.codecompanion').write(true)
      end,
      mode = { 'n', 'x' },
      desc = 'AI: ask with code context',
    },
    {
      '<leader>aw',
      function()
        require('marten.core.codecompanion').write()
      end,
      mode = { 'n', 'x' },
      desc = 'AI: write in chat',
    },
    {
      '<leader>ae',
      function()
        require('marten.core.codecompanion').write()
      end,
      mode = 'x',
      desc = 'AI: discuss selected edit',
    },
    {
      '<leader>ar',
      function()
        require('marten.core.codecompanion').review()
      end,
      desc = 'AI: review changes',
    },
    {
      '<leader>an',
      function()
        require('marten.core.codecompanion').new_chat()
      end,
      desc = 'AI: new chat',
    },
    {
      '<leader>at',
      function()
        require('marten.core.codecompanion').toggle()
      end,
      desc = 'AI: toggle chat',
    },
    {
      '<leader>af',
      function()
        require('marten.core.codecompanion').switch()
      end,
      desc = 'AI: switch chat/file',
    },
    {
      '<leader>a?',
      function()
        require('marten.core.codecompanion').model()
      end,
      desc = 'AI: choose model',
    },
    {
      '<leader>aS',
      function()
        require('marten.core.codecompanion').stop()
      end,
      desc = 'AI: stop request',
    },
    {
      '<leader>ah',
      function()
        require('marten.core.codecompanion').resume()
      end,
      desc = 'AI: resume CLI session',
    },
  },
  config = function(_, opts)
    require('marten.core.codecompanion').setup()
    require('codecompanion').setup(opts)
  end,
  opts = {
    adapters = {
      acp = {
        extend = {
          copilot_acp = {
            commands = {
              default = {
                'copilot',
                '--acp',
                '--stdio',
                '--model',
                'claude-opus-5.5',
                '--reasoning-effort',
                'high',
                '--disable-mcp-server',
                'figma',
                '--additional-mcp-config',
                bridge_config,
                '--allow-all',
              },
            },
          },
        },
      },
    },
    interactions = {
      code_review = {
        keymaps = {
          definition = {
            modes = { n = 'gd' },
            callback = function()
              require('marten.core.codecompanion').review_goto 'definition'
            end,
            description = 'Go to definition in the source file',
          },
          implementation = {
            modes = { n = 'gi' },
            callback = function()
              require('marten.core.codecompanion').review_goto 'implementation'
            end,
            description = 'Go to implementation in the source file',
          },
        },
      },
      chat = {
        adapter = 'copilot_acp',
        opts = {
          completion_provider = 'blink',
          goto_file_action = function(path)
            vim.api.nvim_set_current_win(require('marten.core.windows').ensure_file_window())
            vim.cmd.edit(vim.fn.fnameescape(path))
          end,
          prompt_decorator = function(message)
            if message:match '^%s*[\\/]' then
              return message
            end
            -- Auto approval is not permission to commit or push.
            return message
              .. '\n\nOnly create Git commits or push when I explicitly ask for that action. '
              .. 'Finishing a task or reviewing changes is not permission to commit. '
              .. 'For routine read-only checks, run git status, git --no-pager status, ls, and pwd '
              .. 'as standalone commands in the session working directory. Do not prepend cd, '
              .. 'pipe their output, or combine these checks with other operations; run those separately. '
              .. 'Respond in English unless I request another language.'
          end,
        },
        tools = {
          opts = { approval_mode = 'yolo' },
          run_command = {
            opts = { safe_commands = { 'git status', 'git --no-pager status', 'ls', 'pwd' } },
          },
        },
        slash_commands = {
          file = { opts = { provider = 'telescope' } },
          buffer = { opts = { provider = 'telescope' } },
        },
      },
    },
    display = {
      chat = {
        window = { layout = 'vertical', position = 'right', width = 0.4, pertab = true },
      },
    },
  },
}

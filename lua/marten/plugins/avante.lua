return {
  'yetone/avante.nvim',
  -- if you want to build from source then do `make BUILD_FROM_SOURCE=true`
  -- ⚠️ must add this setting! ! !
  build = vim.fn.has 'win32' ~= 0 and 'powershell -ExecutionPolicy Bypass -File Build.ps1 -BuildFromSource false'
    or 'make',
  event = 'VeryLazy',
  version = false, -- Never set this value to "*"! Never!
  config = function(_, opts)
    local Sidebar = require 'avante.sidebar'
    local initialize = Sidebar.initialize
    Sidebar.initialize = function(self)
      -- Avante otherwise normalizes terminal URIs into nonexistent file paths.
      if vim.bo.buftype ~= '' then
        vim.api.nvim_set_current_win(require('marten.core.windows').ensure_file_window())
      end
      return initialize(self)
    end
    require('avante').setup(opts)
  end,
  ---@module 'avante'
  ---@type avante.Config
  opts = {
    instructions_file = 'avante.md',
    provider = 'copilot',
    behaviour = {
      auto_approve_tool_permissions = {
        'view',
        'ls',
        'glob',
        'grep',
        'get_diagnostics',
        'read_todos',
        'write_todos',
        'think',
        'attempt_completion',
        'delete_tool_use_messages',
        'use_mcp_tool',
        'access_mcp_resource',
      },
      auto_focus_on_diff_view = true,
      auto_apply_diff_after_generation = false,
    },
    system_prompt = function()
      local hub = require('mcphub').get_hub_instance()
      local tools_prompt = hub and hub:get_active_servers_prompt() or ''
      local language_prompt = 'Respond in English unless the user explicitly requests another language.'
      return tools_prompt ~= '' and (tools_prompt .. '\n\n' .. language_prompt) or language_prompt
    end,
    custom_tools = function()
      return {
        require('mcphub.extensions.avante').mcp_tool(),
      }
    end,
    providers = {
      copilot = {
        model = 'claude-opus-5.5',
        timeout = 120000,
        extra_request_body = {
          reasoning_effort = 'high',
        },
        parse_curl_args = function(self, prompt_opts)
          local request_provider = setmetatable(
            vim.tbl_extend('force', self, { extra_request_body = vim.deepcopy(self.extra_request_body) }),
            getmetatable(self)
          )
          local request = require('avante.providers.copilot').parse_curl_args(request_provider, prompt_opts)
          -- Avante's OpenAI filter drops Claude effort, but Copilot supports it.
          if self.model:match '^claude%-' then
            request.body.reasoning_effort = self.extra_request_body.reasoning_effort
          end
          return request
        end,
      },
    },
  },
  dependencies = {
    'nvim-lua/plenary.nvim',
    'MunifTanjim/nui.nvim',
    { 'ColinKennedy/mega.cmdparse', dependencies = { 'ColinKennedy/mega.logging' } },
    'github/copilot.vim',
    'ravitemer/mcphub.nvim',
    --- The below dependencies are optional,
    'nvim-mini/mini.pick', -- for file_selector provider mini.pick
    'nvim-telescope/telescope.nvim', -- for file_selector provider telescope
    'hrsh7th/nvim-cmp', -- autocompletion for avante commands and mentions
    'ibhagwan/fzf-lua', -- for file_selector provider fzf
    'folke/snacks.nvim', -- for input provider snacks
    'nvim-tree/nvim-web-devicons', -- or echasnovski/mini.icons
    {
      -- support for image pasting
      'HakonHarnes/img-clip.nvim',
      event = 'VeryLazy',
      opts = {
        -- recommended settings
        default = {
          embed_image_as_base64 = false,
          prompt_for_file_name = false,
          drag_and_drop = {
            insert_mode = true,
          },
          -- required for Windows users
          use_absolute_path = true,
        },
      },
    },
    {
      -- Make sure to set this up properly if you have lazy=true
      'MeanderingProgrammer/render-markdown.nvim',
      opts = {
        file_types = { 'markdown', 'Avante' },
      },
      ft = { 'markdown', 'Avante' },
    },
  },
}

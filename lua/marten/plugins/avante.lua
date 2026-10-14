local function mcp_servers_prompt(hub)
  local lines = {
    'MCP tools are available through use_mcp_tool; resources through access_mcp_resource.',
    'Before calling an unfamiliar MCP tool, use get_mcp_tool_schema with its exact server_name and tool_name to learn its arguments.',
    'Request only the schemas you need, and reuse schemas already retrieved in this chat.',
    'Server and tool names are case-sensitive. Disabled servers must be started through mcphub.toggle_mcp_server first.',
  }
  for _, server in ipairs(hub:get_servers(true)) do
    if server.status == 'connected' or server.status == 'disabled' then
      lines[#lines + 1] = server.name .. ' (' .. server.status .. ')'
      local capabilities = server.capabilities or {}
      local names = {}
      for _, tool in ipairs(capabilities.tools or {}) do
        names[#names + 1] = tool.name
      end
      if #names > 0 then
        lines[#lines + 1] = 'Tools: ' .. table.concat(names, ', ')
      end
      for _, resource in ipairs(capabilities.resources or {}) do
        lines[#lines + 1] = 'Resource: ' .. resource.uri
      end
      for _, template in ipairs(capabilities.resourceTemplates or {}) do
        lines[#lines + 1] = 'Resource template: ' .. template.uriTemplate
      end
    end
  end
  return table.concat(lines, '\n')
end

local mcp_tool_schema = {
  name = 'get_mcp_tool_schema',
  description = 'Get the description and argument schema of an MCP tool before calling it with use_mcp_tool.',
  param = {
    type = 'table',
    fields = {
      { name = 'server_name', description = 'Exact MCP server name from the server list.', type = 'string' },
      { name = 'tool_name', description = 'Exact tool name from that server.', type = 'string' },
    },
  },
  returns = {
    { name = 'schema', description = 'Tool description and JSON input schema.', type = 'string' },
    { name = 'error', description = 'Tool discovery error.', type = 'string', optional = true },
  },
  func = function(input)
    local hub = require('mcphub').get_hub_instance()
    if not hub then
      return nil, 'MCP Hub not initialized'
    end
    for _, server in ipairs(hub:get_servers()) do
      if server.name == input.server_name then
        for _, tool in ipairs((server.capabilities or {}).tools or {}) do
          if tool.name == input.tool_name then
            return vim.json.encode(tool)
          end
        end
        return nil, 'Unknown MCP tool: ' .. tostring(input.tool_name)
      end
    end
    return nil, 'MCP server is not connected: ' .. tostring(input.server_name)
  end,
}

local function personal_instructions()
  local path = vim.fn.expand '~/.copilot/instructions/global.instructions.md'
  local lines, err, errname = require('avante.utils').read_file_from_buf_or_disk(path)
  if errname == 'ENOENT' then
    return ''
  end
  if err then
    error('Cannot read personal Copilot instructions: ' .. err)
  end
  return table.concat(lines, '\n')
end

local function focus_write()
  local Utils = require 'avante.utils'
  local selection = Utils.get_visual_selection_and_range()
  if selection and (vim.bo.buftype ~= '' or Utils.is_sidebar_buffer(0)) then
    vim.notify('Select code in a file buffer first.', vim.log.levels.WARN, { title = 'Avante' })
    return
  end
  if selection then
    vim.cmd.normal { args = { vim.api.nvim_replace_termcodes('<Esc>', true, false, true) }, bang = true }
  end

  local avante = require 'avante'
  local sidebar = avante.get()
  if not sidebar or not sidebar:is_open() then
    require('avante.api').ask { floating = false, selection = selection }
    sidebar = avante.get()
  elseif selection then
    -- Reopening the sidebar would discard the draft and reset an active chat's UI.
    sidebar.code.selection = selection
    sidebar.token_count = nil
    if Utils.is_valid_container(sidebar.containers.selected_code, true) then
      sidebar:adjust_selected_code_container_layout()
    else
      sidebar:create_selected_code_container()
    end
    local bufnr = sidebar.containers.selected_code.bufnr
    Utils.unlock_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(selection.content, '\n'))
    Utils.lock_buf(bufnr)
    sidebar:render_selected_code()
    sidebar:render_input(require('avante.config').ask_opts.ask)
  end

  if not sidebar or not Utils.is_valid_container(sidebar.containers.input, true) then
    vim.notify('Could not open the chat input.', vim.log.levels.ERROR, { title = 'Avante' })
    return
  end
  sidebar:focus_input()
  vim.cmd.startinsert { bang = true }
end

local function focus_review()
  local popup = require('avante.llm_tools.helpers').confirm_popup
  local winid = popup and popup._popup and popup._popup.winid
  if
    winid
    and vim.api.nvim_win_is_valid(winid)
    and vim.api.nvim_win_get_tabpage(winid) == vim.api.nvim_get_current_tabpage()
  then
    vim.cmd.stopinsert()
    if vim.api.nvim_get_current_win() ~= winid then
      popup:window_focus_handler()
    end
    return
  end

  local sidebar = require('avante').get()
  if
    require('avante.config').mode ~= 'legacy'
    or not sidebar
    or not require('avante.utils').is_valid_container(sidebar.containers.result, true)
    or not sidebar.chat_history
    or #sidebar.chat_history.messages == 0
  then
    vim.notify(
      'No edit approval or completed response is available in this tab.',
      vim.log.levels.INFO,
      { title = 'Avante' }
    )
    return
  end
  if sidebar.is_generating then
    vim.notify(
      'Avante is still generating suggestions; wait for completion before review.',
      vim.log.levels.INFO,
      { title = 'Avante' }
    )
    return
  end
  vim.cmd.stopinsert()
  sidebar:focus()
  vim.api.nvim_win_set_cursor(
    sidebar.containers.result.winid,
    { vim.api.nvim_buf_line_count(sidebar.containers.result.bufnr), 0 }
  )
end

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
    local Config = require 'avante.config'
    local Utils = require 'avante.utils'
    local automatic_reviews = setmetatable({}, { __mode = 'k' })
    require('marten.core.avante-review').setup()
    local get_winid = Utils.get_winid
    Utils.get_winid = function(bufnr)
      -- Avante otherwise jumps to another tab when the same file is open there.
      for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if vim.api.nvim_win_get_buf(winid) == bufnr then
          return winid
        end
      end
      return get_winid(bufnr)
    end
    local initialize = Sidebar.initialize
    Sidebar.initialize = function(self)
      -- Avante otherwise normalizes terminal URIs into nonexistent file paths.
      if vim.bo.buftype ~= '' then
        vim.api.nvim_set_current_win(require('marten.core.windows').ensure_file_window())
      end
      return initialize(self)
    end
    local apply = Sidebar.apply
    Sidebar.apply = function(self, current_cursor)
      local pending = automatic_reviews[self]
      if pending and not current_cursor then
        if self.is_generating then
          vim.notify(
            'Avante is still generating suggestions; wait for completion before review.',
            vim.log.levels.INFO,
            { title = 'Avante' }
          )
          return
        end
        automatic_reviews[self] = nil
        if Config.mode == 'legacy' and Config.behaviour.auto_apply_diff_after_generation then
          if self.chat_history ~= pending.history or self.current_state ~= 'succeeded' then
            return
          end
          local submitted = false
          for i = pending.message_count + 1, #self.chat_history.messages do
            if self.chat_history.messages[i].is_user_submission then
              submitted = true
              break
            end
          end
          if submitted then
            if not Utils.is_valid_container(self.containers.result, true) then
              return
            end
            local last_line = vim.api.nvim_buf_line_count(self.containers.result.bufnr)
            local response = self:get_content_between_separators(last_line)
            if not response:find '\nReplace lines: %d+%-%d+\n```' then
              return
            end
            if vim.api.nvim_win_get_tabpage(self.containers.result.winid) ~= vim.api.nvim_get_current_tabpage() then
              vim.notify(
                'Suggestions are ready in their chat tab; use Space ar, then A to review.',
                vim.log.levels.INFO,
                { title = 'Avante' }
              )
              return
            end
            if not self.code.winid or not vim.api.nvim_win_is_valid(self.code.winid) then
              vim.notify(
                'Suggestions are ready, but the file pane is closed.',
                vim.log.levels.WARN,
                { title = 'Avante' }
              )
              return
            end
            -- Native auto-apply otherwise uses whichever response the current cursor is near.
            vim.cmd.stopinsert()
            self:focus()
            vim.api.nvim_win_set_cursor(self.containers.result.winid, { last_line, 0 })
          end
        end
      end
      return apply(self, current_cursor)
    end
    local handle_submit = Sidebar.handle_submit
    Sidebar.handle_submit = function(self, request)
      if Config.mode == 'legacy' then
        Config.ask_opts.ask = true
        self:render_input(true)
      end
      if
        Config.mode == 'legacy'
        and Config.behaviour.auto_apply_diff_after_generation
        and not self.is_generating
        and request ~= ''
      then
        automatic_reviews[self] = {
          history = self.chat_history,
          message_count = #self.chat_history.messages,
        }
      end
      local result = handle_submit(self, request)
      if require('avante.utils').is_valid_container(self.containers.result) then
        -- Avante replaces j/k with hard-coded vertical motions on every request.
        for lhs, mapping in pairs(require 'marten.core.navigation') do
          vim.keymap.set('n', lhs, function()
            self.scroll = false
            return type(mapping.rhs) == 'function' and mapping.rhs() or mapping.rhs
          end, { buffer = self.containers.result.bufnr, expr = true, desc = mapping.desc })
        end
      end
      return result
    end
    require('avante').setup(opts)
    local cmp = require 'cmp'
    for _, filetype in ipairs { 'AvanteInput', 'AvantePromptInput' } do
      local completion =
        assert(require('cmp.config').filetypes[filetype], 'Avante did not configure completion for ' .. filetype)
      local mapping = cmp.mapping.preset.insert(vim.tbl_extend('force', completion.mapping or {}, {
        ['<C-y>'] = cmp.mapping.confirm { select = true },
        ['<C-k>'] = cmp.mapping.select_next_item { behavior = cmp.SelectBehavior.Select },
        ['<C-l>'] = cmp.mapping.select_prev_item { behavior = cmp.SelectBehavior.Select },
        ['<C-Space>'] = cmp.mapping.complete(),
      }))
      -- Filetype setup replaces its configuration, so retain Avante's registered sources.
      cmp.setup.filetype(filetype, vim.tbl_extend('force', completion, { mapping = mapping }))
    end
    vim.keymap.set({ 'n', 'x' }, '<leader>aw', focus_write, { desc = 'avante: write with selected code context' })
    vim.keymap.set('n', '<leader>ar', focus_review, { desc = 'avante: review response or pending approval' })
  end,
  ---@module 'avante'
  ---@type avante.Config
  opts = {
    instructions_file = 'avante.md',
    mode = 'legacy',
    provider = 'copilot',
    mappings = {
      refresh = '<leader>au',
    },
    behaviour = {
      confirmation_ui_style = 'popup',
      auto_approve_tool_permissions = {
        'view',
        'ls',
        'glob',
        'grep',
        'bash',
        'python', -- Avante's run_python tool checks permissions as "python".
        'get_diagnostics',
        'read_todos',
        'write_todos',
        'think',
        'attempt_completion',
        'delete_tool_use_messages',
        'get_mcp_tool_schema',
        'use_mcp_tool',
        'access_mcp_resource',
      },
      auto_focus_on_diff_view = true,
      auto_apply_diff_after_generation = true, -- Legacy prepares conflicts; acceptance and saving stay manual.
    },
    system_prompt = function()
      local hub = require('mcphub').get_hub_instance()
      local tools_prompt = hub and mcp_servers_prompt(hub) or ''
      local language_prompt = 'Respond in English unless the user explicitly requests another language.'
      local feedback_prompt = 'When a tool is rejected with a question, answer it in chat before another edit. '
        .. 'Then continue with the feedback in mind; do not blindly retry the rejected patch.'
      local review_prompt = [[In legacy mode, propose file edits as SEARCH/REPLACE blocks only.
Do not refuse an editing request just because direct edit tools are unavailable.
Avante converts your proposals into editable file-review hunks after your response.
For each change, use this exact format without Markdown fences:
<FILEPATH>/absolute/path/to/file</FILEPATH>
<SEARCH>
exact existing lines
</SEARCH>
<REPLACE>
replacement lines
</REPLACE>
Read the current file contents so SEARCH matches exactly. Use one block per change.
Never write via shell, Python or MCP. Do not claim unapplied suggestions were tested.]]
      local prompts = { language_prompt, feedback_prompt }
      if require('avante.config').mode == 'legacy' then
        prompts[#prompts + 1] = review_prompt
      end
      if tools_prompt ~= '' then
        table.insert(prompts, 1, tools_prompt)
      end
      local personal_prompt = personal_instructions()
      if personal_prompt ~= '' then
        table.insert(prompts, 1, personal_prompt)
      end
      return table.concat(prompts, '\n\n')
    end,
    custom_tools = function()
      return {
        mcp_tool_schema,
        require('mcphub.extensions.avante').mcp_tool(),
      }
    end,
    providers = {
      copilot = {
        model = 'claude-opus-5.5',
        timeout = 300000,
        extra_request_body = {
          reasoning_effort = 'high',
        },
        parse_curl_args = function(self, prompt_opts)
          local request_provider = setmetatable(
            vim.tbl_extend('force', self, { extra_request_body = vim.deepcopy(self.extra_request_body) }),
            getmetatable(self)
          )
          local request = require('avante.providers.copilot').parse_curl_args(request_provider, prompt_opts)
          -- Avante does not forward request.timeout to its streaming curl transport.
          request.rawArgs = vim.list_extend(request.rawArgs or {}, {
            '--connect-timeout',
            '10',
            '--max-time',
            tostring(self.timeout / 1000),
            '--no-buffer',
          })
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
        overrides = {
          filetype = {
            Avante = { enabled = false },
          },
        },
      },
      ft = { 'markdown', 'Avante' },
    },
  },
}

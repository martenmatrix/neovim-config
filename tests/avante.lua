local child = vim.fn.jobstart({ vim.v.progpath, '--embed', '--headless', '-u', 'NONE', '-n' }, { rpc = true })
assert(child > 0, 'Could not start Neovim for Avante tests')
local artifacts = vim.fn.tempname()
vim.fn.mkdir(artifacts, 'p')

local ok, err = xpcall(function()
  vim.rpcrequest(child, 'nvim_ui_attach', 160, 60, { rgb = true })
  vim.rpcrequest(
    child,
    'nvim_exec_lua',
    [[
    local repo, artifacts = ...
    artifacts = assert(vim.uv.fs_realpath(artifacts))
    vim.opt.runtimepath:prepend(repo)
    for _, path in ipairs(vim.fn.glob(vim.fn.stdpath('data') .. '/lazy/*', false, true)) do
      vim.opt.runtimepath:append(path)
    end
    vim.o.shell = '/bin/cat'
    vim.o.splitright = true
    vim.o.splitbelow = true
    vim.g.avante_login = true
    require('marten.core.keymaps')
    local which_key = dofile(repo .. '/lua/marten/plugins/which-key.lua')
    which_key.init()
    require('which-key').setup(which_key.opts)
    vim.cmd.cd(artifacts)
    local fixture = artifacts .. '/fixture.lua'
    vim.fn.writefile({ 'return 1' }, fixture)
    local errors = {}
    local notices = {}
    vim.notify = function(message, level)
      notices[#notices + 1] = { message = tostring(message), level = level }
      if level == vim.log.levels.ERROR then errors[#errors + 1] = tostring(message) end
    end
    local spec = dofile(repo .. '/lua/marten/plugins/avante.lua')
    local language_prompt = 'Respond in English unless the user explicitly requests another language.'
    local feedback_rule = 'When a tool is rejected with a question, answer it in chat before another edit.'
    local personal_fixture = artifacts .. '/global.instructions.md'
    local personal_rule = 'Follow the private fixture policy.'
    local expand = vim.fn.expand
    vim.fn.expand = function(path, ...)
      if path == '~/.copilot/instructions/global.instructions.md' then return personal_fixture end
      return expand(path, ...)
    end
    local original_mcphub = package.loaded.mcphub
    package.loaded.mcphub = { get_hub_instance = function() return nil end }
    assert(spec.opts.system_prompt():find(language_prompt, 1, true), 'English instructions must be present without MCPHub')
    assert(spec.opts.system_prompt():find(feedback_rule, 1, true),
      'Rejection feedback instructions must be present without MCPHub or personal files')
    vim.fn.mkdir(personal_fixture)
    local readable, read_error = pcall(spec.opts.system_prompt)
    assert(not readable and tostring(read_error):find('Cannot read personal Copilot instructions', 1, true),
      'Existing personal instruction sources must not fail silently')
    vim.fn.delete(personal_fixture, 'd')
    vim.fn.writefile({ personal_rule }, personal_fixture)
    assert(spec.opts.system_prompt():find(personal_rule, 1, true),
      'Private global instructions must load without MCPHub')
    local tools = spec.opts.custom_tools()
    assert(#tools == 3, 'Schema discovery must preserve MCP tool and resource access')
    local schema_tool = tools[1]
    local schema, schema_error = schema_tool.func({ server_name = 'fixture', tool_name = 'lookup' })
    assert(schema == nil and schema_error == 'MCP Hub not initialized', 'Discovery must report an unavailable hub')
    local fixture_tool = {
      name = 'lookup',
      description = string.rep('Detailed tool documentation. ', 10000),
      inputSchema = { type = 'object', properties = { query = { type = 'string' } }, required = { 'query' } },
    }
    local servers = {
      {
        name = 'fixture',
        status = 'connected',
        capabilities = {
          tools = { fixture_tool },
          resources = { { uri = 'fixture://readme' } },
          resourceTemplates = { { uriTemplate = 'fixture://files/{path}' } },
        },
      },
      { name = 'offline', status = 'disabled', capabilities = { tools = { { name = 'other' } } } },
    }
    package.loaded.mcphub.get_hub_instance = function()
      return {
        get_servers = function(_, include_disabled)
          return include_disabled and servers or { servers[1] }
        end,
      }
    end
    local system_prompt = spec.opts.system_prompt()
    assert(system_prompt:find(language_prompt, 1, true), 'Language instructions must preserve MCP discovery')
    assert(system_prompt:find(personal_rule, 1, true), 'MCP discovery must preserve private instructions')
    for _, text in ipairs({ 'fixture (connected)', 'lookup', 'offline (disabled)', 'fixture://readme', 'fixture://files/{path}' }) do
      assert(system_prompt:find(text, 1, true), 'MCP discovery must preserve ' .. text)
    end
    assert(#system_prompt < 1000, 'Detailed MCP schemas must not bloat the system prompt')
    schema, schema_error = schema_tool.func({ server_name = 'fixture', tool_name = 'lookup' })
    assert(schema_error == nil and vim.deep_equal(vim.json.decode(schema), fixture_tool), 'Discovery must return the complete requested schema')
    schema, schema_error = schema_tool.func({ server_name = 'fixture', tool_name = 'missing' })
    assert(schema == nil and schema_error == 'Unknown MCP tool: missing', 'Unknown tools must report an error')
    schema, schema_error = schema_tool.func({ server_name = 'offline', tool_name = 'other' })
    assert(schema == nil and schema_error == 'MCP server is not connected: offline', 'Disabled servers must not be callable')
    package.loaded.mcphub = original_mcphub
    assert(spec.opts.providers.copilot.model == 'claude-opus-5.5', 'Opus 5.5 must be the default model')
    assert(spec.opts.providers.copilot.extra_request_body.reasoning_effort == 'high', 'High reasoning must remain enabled')
    local opts = vim.deepcopy(spec.opts)
    opts.history = { storage_path = artifacts .. '/history' }
    opts.prompt_logger = { enabled = false }
    opts.behaviour.use_cwd_as_project_root = true
    opts.custom_tools = function() return {} end
    spec.config(spec, opts)
    do
      local rendering = assert(vim.iter(spec.dependencies):find(function(dependency)
        return type(dependency) == 'table' and dependency[1] == 'MeanderingProgrammer/render-markdown.nvim'
      end))
      require('render-markdown').setup(rendering.opts)
      vim.cmd.runtime('plugin/render-markdown.lua')
      local namespace = require('render-markdown.core.ui').ns
      local markdown = artifacts .. '/rendering.md'
      local lines = { '# Rendering fixture', '', 'Body text.', '', 'Cursor here.' }
      vim.fn.writefile(lines, markdown)
      vim.cmd.edit(markdown)
      vim.bo.filetype = 'markdown'
      vim.api.nvim_win_set_cursor(0, { #lines, 0 })
      assert(vim.wait(2000, function()
        return #vim.api.nvim_buf_get_extmarks(0, namespace, 0, -1, {}) > 0
      end), 'Ordinary Markdown files must retain their decorations')
      local output = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(output, 0, -1, false, lines)
      vim.api.nvim_win_set_buf(0, output)
      vim.bo.filetype = 'Avante'
      vim.api.nvim_win_set_cursor(0, { #lines, 0 })
      vim.wait(150, function() return false end)
      assert(#vim.api.nvim_buf_get_extmarks(output, namespace, 0, -1, {}) == 0,
        'Avante output must not receive extra Markdown decorations')
      vim.cmd.edit(fixture)
      vim.api.nvim_buf_delete(output, { force = true })
    end
    for _, key in ipairs({ ' aw', ' ar', ' au', ' a]', ' aq' }) do
      assert(vim.fn.maparg(key, 'i') == '', 'Leader shortcuts must not intercept ordinary typing')
    end
    local blink = require('blink.cmp.config')
    blink.merge_with(dofile(repo .. '/lua/marten/plugins/lsp/blink-cmp.lua').opts)
    assert(blink.enabled(), 'Blink completion must remain enabled in ordinary buffers')
    vim.bo.filetype = 'AvantePromptInput'
    assert(not blink.enabled(), 'Blink must not compete with Avante prompt completion')
    local cmp = require('cmp')
    local prompt_sources = vim.tbl_map(function(source) return source.name end, cmp.get_config().sources)
    assert(vim.tbl_contains(prompt_sources, 'avante_prompt_mentions'), 'Avante prompt mentions must remain available')
    vim.bo.filetype = ''
    vim.cmd.edit(fixture)
    require('avante.api').ask({ ask = false, new_chat = true })
    local approval_sidebar = require('avante').get()
    local helpers = require('avante.llm_tools.helpers')
    local confirm_inline = helpers.confirm_inline
    helpers.confirm_inline = function() error('Approvals must use the native popup, not inline buttons') end
    local Confirm = require('avante.ui.confirm')
    local open = Confirm.open
    local prompts = 0
    Confirm.open = function(self)
      prompts = prompts + 1
      return open(self)
    end
    local command_result, command_error
    require('avante.llm_tools.bash').func({ path = artifacts, command = 'printf approval-fixture' }, {
      session_ctx = {},
      on_complete = function(result, err)
        command_result, command_error = result, err
      end,
    })
    assert(vim.wait(2000, function() return command_result ~= nil end), 'Shell command did not complete')
    assert(command_error == nil, tostring(command_error))
    assert(vim.trim(command_result) == 'approval-fixture', 'Auto-approved shell command must execute')
    assert(prompts == 0, 'Shell commands must not show approval prompts')
    local python_approved
    helpers.confirm('Python execution', function(approved) python_approved = approved end, nil, {}, 'python')
    assert(vim.wait(1000, function() return python_approved ~= nil end), 'Python permission did not resolve')
    assert(python_approved and prompts == 0, 'Python execution must be auto-approved')
    for _, tool in ipairs({
      'edit_file', 'replace_in_file', 'str_replace', 'insert', 'create', 'write_to_file',
      'write_global_file', 'move_path', 'copy_path', 'delete_path', 'create_dir', 'undo_edit',
      'git_commit', 'unknown_tool',
    }) do
      local approved
      local count = prompts
      helpers.confirm('Fixture modification', function(result) approved = result end, nil, {}, tool)
      assert(prompts == count + 1, tool .. ' must still require approval')
      assert(helpers.confirm_popup and helpers.confirm_popup._popup, tool .. ' must display a native approval popup')
      assert(approval_sidebar.permission_handler == nil, 'Popup approvals must not install inline handlers')
      helpers.confirm_popup:cancel()
      assert(vim.wait(1000, function() return approved ~= nil end), tool .. ' permission did not resolve')
      assert(approved == false, tool .. ' must honor rejection')
    end
    for _, case in ipairs({ { key = 'y', approved = true }, { key = 'n', approved = false } }) do
      local approved
      helpers.confirm('Fixture modification', function(result) approved = result end,
        { skip_reject_prompt = true }, {}, 'str_replace')
      assert(vim.bo.filetype == 'AvanteConfirm', 'The approval popup must receive keyboard focus')
      local popup = helpers.confirm_popup
      vim.api.nvim_set_current_win(approval_sidebar.containers.input.winid)
      vim.api.nvim_feedkeys(' ar', 'xt', false)
      assert(vim.api.nvim_get_current_win() == popup._popup.winid, 'Space ar must focus the pending approval')
      vim.api.nvim_feedkeys(' ar', 'xt', false)
      assert(vim.api.nvim_get_current_win() == popup._popup.winid, 'Repeated review must keep focus on approval')
      assert(approved == nil, 'Focusing review must not approve or reject the edit')
      vim.api.nvim_feedkeys(' aw', 'xt', false)
      assert(vim.api.nvim_get_current_win() == approval_sidebar.containers.input.winid,
        'Space aw must reach the input from the approval popup')
      assert(helpers.confirm_popup == popup and approved == nil, 'Writing must preserve the pending approval')
      vim.cmd.stopinsert()
      local owner_tab = vim.api.nvim_get_current_tabpage()
      vim.cmd.tabnew()
      local other_tab = vim.api.nvim_get_current_tabpage()
      local other_win = vim.api.nvim_get_current_win()
      vim.api.nvim_feedkeys(' ar', 'xt', false)
      assert(vim.api.nvim_get_current_tabpage() == other_tab and vim.api.nvim_get_current_win() == other_win,
        'Review must not jump to another tab with a pending approval')
      assert(helpers.confirm_popup == popup and approved == nil, 'Another tab must not resolve the pending approval')
      assert(notices[#notices].message == 'No edit approval or completed response is available in this tab.',
        'An approval in another tab must not be offered for review here')
      vim.cmd('tabclose!')
      assert(vim.api.nvim_get_current_tabpage() == owner_tab, 'Approval fixture must return to its owning tab')
      vim.api.nvim_feedkeys(' ar', 'xt', false)
      vim.api.nvim_feedkeys(case.key, 'xt', false)
      assert(vim.wait(1000, function() return approved ~= nil end), 'Popup keyboard action must resolve approval')
      assert(approved == case.approved, 'Popup keyboard action must preserve the selected decision')
      assert(helpers.confirm_popup == nil, 'Resolved approval must close the popup')
    end
    Confirm.open = open
    helpers.confirm_inline = confirm_inline
    approval_sidebar:close({ goto_code_win = false })
    local llm = require('avante.llm')
    local provider = require('avante.providers').copilot
    local copilot = require('avante.providers.copilot')
    local requests = 0
    local stops = 0
    local refreshes = 0
    local copilot_rule = 'Keep fixture functions focused.'
    local review_rule = 'In legacy mode, propose file edits as SEARCH/REPLACE blocks only'
    local refusal_rule = 'Do not refuse an editing request just because direct edit tools are unavailable.'
    local saved_rule
    local mock_response
    local last_stream_options
    local api = require('avante.api')
    local refresh = api.refresh
    api.refresh = function() refreshes = refreshes + 1 end
    llm.cancel_inflight_request = function() stops = stops + 1 end
    llm.stream = function(stream_opts)
      requests = requests + 1
      last_stream_options = stream_opts
      local prompt = llm.generate_prompts(stream_opts)
      assert(prompt.system_prompt:find(language_prompt, 1, true), 'English instructions must reach the model prompt')
      if not stream_opts.prompt_opts or not stream_opts.prompt_opts.system_prompt then
        assert(prompt.system_prompt:find('All changes to files must use this *SEARCH/REPLACE block* format', 1, true),
          'Opening chat for writing must retain the native legacy proposal instructions')
      end
      local tool_names = vim.tbl_map(function(tool) return tool.name end, prompt.tools)
      for _, name in ipairs({ 'str_replace', 'insert', 'create', 'write_to_file', 'edit_file', 'undo_edit' }) do
        assert(not vim.tbl_contains(tool_names, name), 'Legacy requests must not expose native editing tool ' .. name)
      end
      assert(vim.tbl_contains(tool_names, 'view'), 'Legacy mode must preserve file reads')
      local state = copilot.state
      copilot.state = {
        github_token = {
          token = 'fixture',
          expires_at = os.time() + 3600,
          endpoints = { api = 'https://api.githubcopilot.com' },
        },
      }
      local request = provider:parse_curl_args(prompt)
      copilot.state = state
      assert(request.body.model == 'claude-opus-5.5', 'The request must use Opus 5.5')
      assert(request.body.reasoning_effort == 'high', 'High effort must survive the native request builder')
      assert(provider.extra_request_body.reasoning_effort == 'high', 'Building a request must preserve the configured effort')
      assert(vim.json.encode(request.body.messages):find(copilot_rule, 1, true),
        'Project-local instructions must reach the actual Copilot request body')
      assert(vim.json.encode(request.body.messages):find(personal_rule, 1, true),
        'Private global instructions must reach the actual Copilot request body')
      assert(vim.json.encode(request.body.messages):find(feedback_rule, 1, true),
        'Question-first rejection instructions must reach the actual Copilot request body')
      assert(vim.json.encode(request.body.messages):find(review_rule, 1, true),
        'Proposal-only editing guidance must reach the actual Copilot request body')
      local request_messages = vim.json.encode(request.body.messages)
      assert(request_messages:find(refusal_rule, 1, true)
        and request_messages:find('<FILEPATH>/absolute/path/to/file</FILEPATH>', 1, true)
        and request_messages:find('<SEARCH>', 1, true)
        and request_messages:find('<REPLACE>', 1, true),
        'The actual request must explain how to propose edits without direct writing tools')
      if saved_rule then
        assert(request_messages:find(saved_rule, 1, true), 'Resumed chats must preserve saved system instructions')
      end
      stream_opts.on_messages_add({
        require('avante.history').Message:new('assistant',
          mock_response or 'Fixture response\nSecond fixture line\nThird fixture line', { state = 'generating' }),
      })
    end
    local state = copilot.state
    copilot.state = {
      github_token = {
        token = 'fixture',
        expires_at = os.time() + 3600,
        endpoints = { api = 'https://api.githubcopilot.com' },
      },
    }
    local curl = require('plenary.curl')
    local post = curl.post
    local stopped
    curl.post = function(_, request)
      assert(vim.deep_equal(request.raw, {
        '--connect-timeout', '10', '--max-time', '300', '--no-buffer',
      }), 'Streaming transport must enforce deadlines and disable buffering')
      vim.schedule(function() request.on_error({ exit = 28, message = 'Fixture request timed out' }) end)
      return {}
    end
    llm.curl({
      provider = provider,
      prompt_opts = { system_prompt = language_prompt, messages = {}, tools = {} },
      handler_opts = { on_stop = function(result) stopped = result end },
    })
    assert(vim.wait(1000, function() return stopped ~= nil end), 'Timed-out request must stop waiting')
    assert(stopped.reason == 'error' and stopped.error.exit == 28, 'Timeout must be reported as an error')
    curl.post = post
    copilot.state = state
    local project_rule = 'Use descriptive fixture identifiers.'
    vim.fn.writefile({ project_rule }, artifacts .. '/AGENTS.md')
    vim.fn.mkdir(artifacts .. '/.github', 'p')
    vim.fn.writefile({ copilot_rule }, artifacts .. '/.github/copilot-instructions.md')
    local function rules_prompt()
      local result
      approval_sidebar:get_generate_prompts_options('', function(options) result = llm.generate_prompts(options) end)
      assert(result, 'Project instruction prompt must resolve')
      return result
    end
    local rule_prompt = rules_prompt()
    assert(rule_prompt.system_prompt:find(project_rule, 1, true), 'Native project AGENTS.md must reach the model')
    assert(not rule_prompt.system_prompt:find(copilot_rule, 1, true), 'Native AGENTS.md precedence must be preserved')
    vim.fn.delete(artifacts .. '/AGENTS.md')
    rule_prompt = rules_prompt()
    assert(rule_prompt.system_prompt:find(copilot_rule, 1, true), 'Native project Copilot instructions must work as a fallback')
    for _, case in ipairs({ 'file', 'terminal', 'terminal-only', 'tree' }) do
      vim.cmd.tabnew()
      local file_win = vim.api.nvim_get_current_win()
      local job, terminal_buf
      if case ~= 'terminal-only' then vim.cmd.edit(fixture) end
      if case == 'terminal' or case == 'terminal-only' then
        if case == 'terminal' then vim.cmd('belowright 15new') end
        job = vim.fn.jobstart({ '/bin/cat' }, { term = true })
        terminal_buf = vim.api.nvim_get_current_buf()
        assert(vim.bo.buftype == 'terminal')
      elseif case == 'tree' then
        vim.cmd('topleft 30vnew')
        vim.bo.buftype = 'nofile'
        vim.bo.filetype = 'NvimTree'
        vim.wo.winfixbuf = true
      end
      local count = requests
      vim.api.nvim_feedkeys(' aw', 'xt', false)
      local sidebar = require('avante').get()
      assert(vim.api.nvim_get_current_win() == sidebar.containers.input.winid, 'Space aw must open the input')
      assert(requests == count, 'Opening the input must not submit a question')
      assert(vim.bo[sidebar.code.bufnr].buftype == '', 'Avante must use an editable file buffer')
      if case == 'terminal-only' then
        assert(sidebar.code.bufnr ~= terminal_buf, 'Terminal must not become the code buffer')
        assert(#sidebar.file_selector:get_selected_filepaths() == 0, 'Empty file pane must have no selected files')
      else
        assert(sidebar.code.winid == file_win, 'Avante must reuse the existing file window')
        assert(vim.api.nvim_buf_get_name(sidebar.code.bufnr) == fixture, case .. ': unexpected code buffer ' .. vim.api.nvim_buf_get_name(sidebar.code.bufnr))
        assert(vim.deep_equal(sidebar.file_selector:get_selected_filepaths(), { fixture }), 'Real file context must be preserved')
      end
      sidebar.file_selector:get_selected_files_contents()
      vim.api.nvim_set_current_win(sidebar.containers.input.winid)
      vim.api.nvim_exec_autocmds('ModeChanged', { pattern = 'i:n' })
      assert(not blink.enabled(), 'Blink must not compete with Avante chat completion')
      local input_sources = vim.tbl_map(function(source) return source.name end, cmp.get_config().sources)
      assert(vim.tbl_contains(input_sources, 'avante_commands'), 'Avante slash commands must remain available')
      assert(vim.tbl_contains(input_sources, 'avante_mentions'), 'Avante mentions must remain available')
      local count = requests
      sidebar:handle_submit('Explain this fixture')
      assert(vim.wait(2000, function() return requests > count end), 'Message submission did not reach the request builder')
      assert(vim.wait(1000, function()
        return vim.api.nvim_buf_line_count(sidebar.containers.result.bufnr) >= 5
      end), 'Fixture response must render before exercising counted navigation')
      vim.api.nvim_set_current_win(sidebar.containers.result.winid)
      vim.api.nvim_win_set_cursor(0, { 2, 0 })
      sidebar.scroll = true
      vim.api.nvim_feedkeys('k', 'xt', false)
      assert(vim.api.nvim_win_get_cursor(0)[1] == 3, 'k must move down in the chat while Avante is running')
      assert(not sidebar.scroll, 'Manual navigation must stop automatic scrolling')
      vim.api.nvim_feedkeys('l', 'xt', false)
      assert(vim.api.nvim_win_get_cursor(0)[1] == 2, 'l must move up in the chat while Avante is running')
      vim.api.nvim_feedkeys('2k', 'xt', false)
      assert(vim.api.nvim_win_get_cursor(0)[1] == 4,
        'Chat navigation must preserve counts: ' .. vim.inspect(vim.api.nvim_win_get_cursor(0))
          .. ', lines: ' .. vim.api.nvim_buf_line_count(0))
      vim.api.nvim_feedkeys(' af', 'xt', false)
      assert(vim.wait(1000, function() return vim.api.nvim_get_current_win() == sidebar.code.winid end),
        'Space af must switch to the file pane while Avante is running')
      local stop_count = stops
      vim.api.nvim_feedkeys(' aS', 'xt', false)
      assert(vim.wait(1000, function() return stops > stop_count end),
        'Space aS must reach the native stop action while Avante is running')
      local refresh_count = refreshes
      vim.api.nvim_feedkeys(' au', 'xt', false)
      assert(refreshes == refresh_count + 1, 'Space au must reach the native refresh action')
      vim.api.nvim_feedkeys(' ar', 'xt', false)
      assert(refreshes == refresh_count + 1, 'Space ar must no longer refresh the file context')
      assert(notices[#notices].message == 'Avante is still generating suggestions; wait for completion before review.',
        'Review must wait for the proposal to finish')
      if case == 'file' then
        sidebar:set_input_value('Draft fixture question')
        local input_buf = sidebar.containers.input.bufnr
        local history = vim.deepcopy(sidebar.chat_history)
        local selected_files = sidebar.file_selector:get_selected_filepaths()
        for _, selection_keys in ipairs({ 'V aw', 'v2; aw' }) do
          vim.api.nvim_set_current_win(sidebar.code.winid)
          vim.api.nvim_win_set_cursor(0, { 1, 0 })
          local request_count = requests
          vim.api.nvim_feedkeys(selection_keys, 'xt', false)
          assert(vim.api.nvim_get_current_win() == sidebar.containers.input.winid, 'Visual write must focus input')
          assert(sidebar.containers.input.bufnr == input_buf, 'Attaching code must not rebuild the input buffer')
          assert(sidebar:get_input_value() == 'Draft fixture question', 'Attaching code must preserve the draft')
          assert(vim.deep_equal(history, sidebar.chat_history), 'Attaching code must preserve the chat')
          assert(sidebar.is_generating and requests == request_count, 'Attaching code must not interrupt or submit a run')
          assert(vim.deep_equal(selected_files, sidebar.file_selector:get_selected_filepaths()),
            'Attaching a snippet must preserve existing file context')
          assert(sidebar.code.selection.content == 'return 1' and sidebar.code.selection.filepath == fixture,
            'Visual write must retain native code and file selection context')
          assert(vim.deep_equal(vim.api.nvim_buf_get_lines(sidebar.containers.selected_code.bufnr, 0, -1, false),
            { 'return 1' }), 'Attached code must be visible in the selection pane')
          local generate_opts
          sidebar:get_generate_prompts_options('', function(result) generate_opts = result end)
          assert(vim.wait(1000, function() return generate_opts ~= nil end), 'Selected-code prompt did not resolve')
          assert(generate_opts.selected_code.content == 'return 1' and generate_opts.selected_code.path == fixture,
            'Attached selection must be included in the next model prompt')
        end
      end
      assert(#errors == 0, table.concat(errors, '\n'))
      if job then
        assert(vim.api.nvim_buf_is_valid(terminal_buf), 'Terminal buffer must be preserved')
        assert(vim.bo[terminal_buf].buftype == 'terminal')
        assert(vim.fn.jobwait({ job }, 0)[1] == -1, 'Terminal job must remain running')
        vim.fn.jobstop(job)
      end
      sidebar:close({ goto_code_win = false })
      vim.cmd('tabclose!')
    end
    api.refresh = refresh
    local config = require('avante.config')
    local default_auto_review = config.behaviour.auto_apply_diff_after_generation
    config.override({ behaviour = { auto_apply_diff_after_generation = false } })
    local first_file = artifacts .. '/review-first.lua'
    local second_file = artifacts .. '/review-second.lua'
    local first_lines = { 'local first = 1', '', 'local second = 2', '', 'return first + second' }
    vim.fn.writefile(first_lines, first_file)
    vim.fn.writefile({ 'return "before"' }, second_file)
    local other_tab_file = artifacts .. '/review-other-tab.lua'
    vim.fn.writefile({ 'return "original"' }, other_tab_file)
    vim.cmd.tabnew()
    vim.cmd.edit(other_tab_file)
    local other_review_tab = vim.api.nvim_get_current_tabpage()
    local other_review_buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(other_review_buf, 0, -1, false, {
      '<<<<<<< HEAD', 'return "original"', '=======', 'return "proposed"', '>>>>>>> Snippet',
    })
    require('avante.diff').add_visited_buffer(other_review_buf)
    require('avante.diff').process(other_review_buf)
    vim.cmd.tabnew()
    vim.cmd.edit(first_file)
    vim.api.nvim_feedkeys(' aw', 'xt', false)
    vim.cmd.stopinsert()
    local review_sidebar = require('avante').get()
    review_sidebar:set_input_value('Preserved review draft')
    mock_response = table.concat({
      'Here are the proposed changes.',
      '<FILEPATH>' .. first_file .. '</FILEPATH>',
      '<SEARCH>', 'local first = 1', '</SEARCH>',
      '<REPLACE>', 'local first = 10', '</REPLACE>',
      '<FILEPATH>' .. first_file .. '</FILEPATH>',
      '<SEARCH>', 'local second = 2', '</SEARCH>',
      '<REPLACE>', 'local second = 20', '</REPLACE>',
      '<FILEPATH>' .. second_file .. '</FILEPATH>',
      '<SEARCH>', 'return "before"', '</SEARCH>',
      '<REPLACE>', 'return "after"', '</REPLACE>',
    }, '\n')
    local count = requests
    review_sidebar:handle_submit('Propose changes to both fixture files')
    assert(vim.wait(2000, function() return requests > count end), 'Legacy proposal request did not start')
    assert(vim.deep_equal(vim.api.nvim_buf_get_lines(review_sidebar.code.bufnr, 0, -1, false), first_lines),
      'Generating a proposal must not modify the file buffer')
    assert(vim.deep_equal(vim.fn.readfile(first_file), first_lines), 'Generating must not write proposed changes')
    last_stream_options.on_stop({ reason = 'complete' })
    assert(vim.wait(2000, function()
      return not review_sidebar.is_generating
        and table.concat(vim.api.nvim_buf_get_lines(review_sidebar.containers.result.bufnr, 0, -1, false), '\n')
          :find('local first = 10', 1, true)
    end), 'Completed proposals must render in the response')
    local review_history = vim.deepcopy(review_sidebar.chat_history)
    vim.api.nvim_set_current_win(review_sidebar.containers.input.winid)
    vim.api.nvim_feedkeys(' ar', 'xt', false)
    assert(vim.api.nvim_get_current_win() == review_sidebar.containers.result.winid,
      'Space ar must focus the completed proposal')
    assert(vim.api.nvim_win_get_cursor(0)[1] == vim.api.nvim_buf_line_count(0),
      'Review must reach the latest response instead of an older scroll position')
    assert(review_sidebar:get_input_value() == 'Preserved review draft', 'Review must preserve the draft')
    assert(vim.deep_equal(review_sidebar.chat_history, review_history), 'Review must preserve the chat')
    assert(vim.deep_equal(vim.api.nvim_buf_get_lines(review_sidebar.code.bufnr, 0, -1, false), first_lines),
      'Focusing review must not apply any suggestions')
    vim.api.nvim_feedkeys('A', 'xt', false)
    local first_buf = vim.fn.bufnr(first_file)
    assert(vim.wait(2000, function()
      return vim.tbl_contains(vim.api.nvim_buf_get_lines(first_buf, 0, -1, false), '<<<<<<< HEAD')
    end), 'Native A must prepare conflict review after generation')
    assert(vim.deep_equal(vim.fn.readfile(first_file), first_lines),
      'Preparing conflict review must not save unaccepted changes')
    assert(vim.deep_equal(vim.fn.readfile(second_file), { 'return "before"' }),
      'Preparing multi-file review must not save another file')
    vim.api.nvim_set_current_win(review_sidebar.code.winid)
    vim.api.nvim_set_current_buf(first_buf)
    require('avante.diff').process(first_buf)
    local pending_snapshots = {}
    for _, bufnr in ipairs({ first_buf, vim.fn.bufnr(second_file), other_review_buf }) do
      pending_snapshots[bufnr] = {
        lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false),
        modified = vim.bo[bufnr].modified,
        tick = vim.b[bufnr].changedtick,
      }
    end
    for _, key in ipairs({ ']x', '[x', 'ct', 'co' }) do
      vim.api.nvim_buf_del_keymap(first_buf, 'n', key)
    end
    local native_apply = require('avante.sidebar').apply
    local review_win = vim.api.nvim_get_current_win()
    local review_cursor = vim.api.nvim_win_get_cursor(review_win)
    for _ = 1, 2 do
      vim.cmd.AvanteReviewReload()
      for bufnr, snapshot in pairs(pending_snapshots) do
        assert(vim.deep_equal(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), snapshot.lines)
          and vim.bo[bufnr].modified == snapshot.modified and vim.b[bufnr].changedtick == snapshot.tick,
          'Review-only reload must preserve every pending buffer without applying or saving edits')
      end
      assert(vim.api.nvim_get_current_win() == review_win
        and vim.deep_equal(vim.api.nvim_win_get_cursor(review_win), review_cursor),
        'Review-only reload must preserve the focused window and cursor')
      assert(vim.deep_equal(review_sidebar.chat_history, review_history)
        and review_sidebar:get_input_value() == 'Preserved review draft',
        'Review-only reload must preserve the conversation and draft')
      assert(require('avante.sidebar').apply == native_apply,
        'Review-only reload must not rerun Avante setup or stack sidebar wrappers')
      for _, key in ipairs({ ']x', '[x', 'ct', 'co' }) do
        assert(vim.fn.maparg(key, 'n', false, true).buffer == 1,
          'Review-only reload must restore the native ' .. key .. ' mapping')
      end
    end
    vim.cmd.buffer { args = { tostring(vim.fn.bufnr(fixture)) }, mods = { hide = true } }
    vim.cmd.AvanteReviewNext()
    assert(vim.tbl_contains({ first_buf, vim.fn.bufnr(second_file) }, vim.api.nvim_get_current_buf()),
      'Manual review-next must reach a pending file from a finished or unrelated file in the same tab')
    local review_items = vim.fn.getqflist()
    assert(#review_items == 2 and vim.fn.getqflist({ title = 0 }).title == 'Avante pending files',
      'Manual navigation must use a native quickfix list with one entry per pending file')
    for _, item in ipairs(review_items) do
      assert(item.bufnr ~= other_review_buf, "The review list must not include another tab's pending file")
    end
    for bufnr, snapshot in pairs(pending_snapshots) do
      assert(vim.deep_equal(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), snapshot.lines),
        'Manual review-next must not apply, reject, or discard pending changes')
    end
    vim.api.nvim_set_current_buf(first_buf)
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    vim.api.nvim_feedkeys(']x', 'xt', false)
    assert(vim.api.nvim_win_get_cursor(0)[1] > 1, 'Native next-conflict navigation must move to the second hunk')
    vim.api.nvim_feedkeys('[x', 'xt', false)
    vim.api.nvim_feedkeys('ct', 'xt', false)
    assert(vim.api.nvim_get_current_buf() == first_buf and require('avante.diff').conflict_count(first_buf) == 1,
      'Review must stay in the current file while another hunk remains')
    local partially_reviewed = vim.api.nvim_buf_get_lines(first_buf, 0, -1, false)
    vim.cmd.AvanteReviewNext()
    assert(vim.api.nvim_get_current_buf() == first_buf
      and vim.deep_equal(vim.api.nvim_buf_get_lines(first_buf, 0, -1, false), partially_reviewed),
      'Manual file navigation must not abandon unresolved conflict markers or apply edits')
    assert(notices[#notices].level == vim.log.levels.WARN,
      'Refusing to leave unresolved conflict markers must explain the problem')
    local hidden = vim.o.hidden
    vim.o.hidden = false
    vim.api.nvim_feedkeys('co', 'xt', false)
    local second_buf = vim.fn.bufnr(second_file)
    local resolution_finished = false
    vim.defer_fn(function() resolution_finished = true end, 150)
    assert(vim.wait(1000, function() return resolution_finished end), 'Native resolution callbacks must finish')
    assert(vim.api.nvim_get_current_buf() == first_buf,
      'Resolving the last hunk must not automatically jump to another file')
    vim.api.nvim_feedkeys(' a]', 'xt', false)
    assert(vim.api.nvim_get_current_buf() == second_buf, 'Space a] must manually open the next pending file')
    assert(vim.api.nvim_get_current_win() == review_sidebar.code.winid,
      'Advancing review must reuse the file pane')
    assert(vim.api.nvim_buf_is_loaded(first_buf) and vim.bo[first_buf].modified,
      'Advancing review must retain unsaved changes even when hidden is disabled')
    vim.o.hidden = hidden
    assert(vim.api.nvim_win_get_cursor(0)[1] == 1,
      'The next file must open at its first unresolved hunk')
    local reviewed_first = { 'local first = 10', '', 'local second = 2', '', 'return first + second' }
    assert(vim.deep_equal(vim.api.nvim_buf_get_lines(first_buf, 0, -1, false), reviewed_first),
      'Native conflict controls must accept one hunk and reject the other')
    assert(vim.deep_equal(vim.fn.readfile(first_file), first_lines),
      'Advancing review must not automatically save the resolved file')
    vim.api.nvim_buf_call(first_buf, function() vim.cmd.write() end)
    assert(vim.deep_equal(vim.fn.readfile(first_file), reviewed_first), 'Reviewed changes must persist when saved')
    vim.cmd.buffer { args = { tostring(first_buf) }, mods = { hide = true } }
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    vim.api.nvim_feedkeys('dd', 'xt', false)
    local deletion_finished = false
    vim.defer_fn(function() deletion_finished = true end, 50)
    assert(vim.wait(1000, function() return deletion_finished end), 'Ordinary edit callbacks must finish')
    assert(vim.api.nvim_get_current_buf() == first_buf,
      'Ordinary dd in a finished review file must never jump to a pending file')
    assert(vim.tbl_contains(vim.api.nvim_buf_get_lines(second_buf, 0, -1, false), '<<<<<<< HEAD'),
      "Editing a finished file must preserve the other file's unresolved changes")
    vim.api.nvim_feedkeys('u', 'xt', false)
    assert(vim.deep_equal(vim.api.nvim_buf_get_lines(first_buf, 0, -1, false), reviewed_first),
      'Undoing the ordinary edit must preserve the previously resolved changes')
    vim.api.nvim_feedkeys(' a]', 'xt', false)
    assert(second_buf > 0, 'Native A must prepare every proposed file')
    assert(vim.wait(1000, function()
      return vim.fn.maparg('ct', 'n', false, true).buffer == 1
    end), 'Opening another proposed file must install native conflict controls')
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    vim.api.nvim_feedkeys('ct', 'xt', false)
    assert(vim.deep_equal(vim.api.nvim_buf_get_lines(second_buf, 0, -1, false), { 'return "after"' }),
      'Native review must also accept changes in the second file')
    vim.cmd.AvanteReviewNext()
    assert(notices[#notices].message == 'No pending Avante conflict markers remain in this tab.',
      'Manual next must report when no pending conflict markers remain')
    assert(vim.api.nvim_get_current_buf() == second_buf,
      'Completed review must not reopen an already resolved file')
    assert(require('avante.diff').conflict_count(other_review_buf) == 1,
      "Completing review must not visit or resolve another tab's pending file")
    assert(vim.deep_equal(vim.fn.readfile(second_file), { 'return "before"' }),
      'Completing review must leave saving under user control')
    vim.cmd.write()
    assert(vim.deep_equal(vim.fn.readfile(second_file), { 'return "after"' }), 'Second-file review must persist')
    assert(#errors == 0, table.concat(errors, '\n'))
    review_sidebar:close({ goto_code_win = false })
    vim.cmd('tabclose!')
    assert(vim.api.nvim_get_current_tabpage() == other_review_tab)
    vim.cmd('tabclose!')
    local recovery_file = artifacts .. '/review-recovery.lua'
    vim.fn.writefile({ 'return "original"' }, recovery_file)
    vim.cmd.tabnew()
    vim.cmd.edit(recovery_file)
    local recovery_buf = vim.api.nvim_get_current_buf()
    local recovery_lines = {
      '<<<<<<< HEAD', 'local first = "original"', '=======', 'local first = "recovered"', '>>>>>>> Snippet',
      '',
      '<<<<<<< HEAD', 'return first', '=======', 'return first .. "!"', '>>>>>>> Snippet',
    }
    vim.api.nvim_buf_set_lines(recovery_buf, 0, -1, false, recovery_lines)
    assert(require('avante.diff').conflict_count(recovery_buf) == 0,
      'Recovery must reproduce an existing conflict buffer missing from the native cache')
    vim.lsp.inlay_hint.enable(true, { bufnr = recovery_buf })
    dofile(repo .. '/lua/marten/core/avante-review.lua').setup(nil, true)
    assert(require('avante.diff').conflict_count(recovery_buf) == 2
      and vim.fn.maparg('ct', 'n', false, true).buffer == 1,
      'Bootstrapping review reload must recover an unregistered current conflict buffer')
    assert(vim.deep_equal(vim.api.nvim_buf_get_lines(recovery_buf, 0, -1, false), recovery_lines)
      and vim.deep_equal(vim.fn.readfile(recovery_file), { 'return "original"' }),
      'Bootstrapping reload must preserve pending markers and the original file on disk')
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    vim.api.nvim_feedkeys('ca', 'xt', false)
    assert(vim.api.nvim_get_current_buf() == recovery_buf
      and vim.deep_equal(vim.api.nvim_buf_get_lines(recovery_buf, 0, -1, false),
        { 'local first = "recovered"', '', 'return first .. "!"' }),
      'Native ca must finish every hunk in the current buffer without switching files or leaving markers')
    assert(vim.lsp.inlay_hint.is_enabled({ bufnr = recovery_buf }),
      'Recovery must not emit duplicate detection events that lose the original inlay-hint setting')
    vim.api.nvim_buf_set_lines(recovery_buf, 0, -1, false, { '<<<<<<< HEAD', 'return "unfinished"' })
    require('avante.diff').process(recovery_buf)
    assert(require('avante.diff').conflict_count(recovery_buf) == 0,
      'The incomplete-marker fixture must reproduce a zero native hunk count')
    vim.cmd.AvanteReviewNext()
    assert(vim.api.nvim_get_current_buf() == recovery_buf and notices[#notices].level == vim.log.levels.WARN,
      'A zero native hunk count must not let manual navigation abandon an incomplete HEAD marker')
    vim.cmd('tabclose!')
    vim.cmd.tabnew()
    vim.cmd.edit(fixture)
    vim.api.nvim_feedkeys(' aw', 'xt', false)
    vim.cmd.stopinsert()
    local auto_sidebar = require('avante').get()
    mock_response = table.concat({
      '<FILEPATH>' .. fixture .. '</FILEPATH>',
      '<SEARCH>', 'return 1', '</SEARCH>',
      '<REPLACE>', 'return 999', '</REPLACE>',
    }, '\n')
    local count = requests
    auto_sidebar:handle_submit('Keep this older proposal unapplied')
    assert(vim.wait(2000, function() return requests > count end), 'Older proposal did not start')
    last_stream_options.on_stop({ reason = 'complete' })
    assert(vim.wait(1000, function()
      return table.concat(vim.api.nvim_buf_get_lines(auto_sidebar.containers.result.bufnr, 0, -1, false), '\n')
        :find('return 999', 1, true)
    end), 'Older proposal must render before testing an old scroll position')
    local older_finished = false
    vim.defer_fn(function() older_finished = true end, 0)
    assert(vim.wait(1000, function() return older_finished end), 'Older completion callbacks must finish')
    config.override({ behaviour = { auto_apply_diff_after_generation = default_auto_review } })
    mock_response = table.concat({
      '<FILEPATH>' .. first_file .. '</FILEPATH>',
      '<SEARCH>', 'local first = 10', '</SEARCH>',
      '<REPLACE>', 'local first = 100', '</REPLACE>',
      '<FILEPATH>' .. second_file .. '</FILEPATH>',
      '<SEARCH>', 'return "after"', '</SEARCH>',
      '<REPLACE>', 'return "automatic"', '</REPLACE>',
    }, '\n')
    local count = requests
    auto_sidebar:handle_submit('Propose changes outside the current file')
    assert(vim.wait(2000, function() return requests > count end), 'Automatic-review proposal did not start')
    auto_sidebar.scroll = false
    vim.api.nvim_win_set_cursor(auto_sidebar.containers.result.winid, { 1, 0 })
    vim.api.nvim_set_current_win(auto_sidebar.containers.result.winid)
    vim.api.nvim_feedkeys('A', 'xt', false)
    assert(vim.deep_equal(vim.api.nvim_buf_get_lines(first_buf, 0, -1, false), reviewed_first),
      'Review must not prepare conflicts before generation finishes')
    auto_sidebar:set_input_value('Draft while waiting for automatic review')
    vim.api.nvim_set_current_win(auto_sidebar.containers.input.winid)
    last_stream_options.on_stop({ reason = 'complete' })
    assert(vim.wait(2000, function()
      return vim.tbl_contains(vim.api.nvim_buf_get_lines(first_buf, 0, -1, false), '<<<<<<< HEAD')
        and vim.tbl_contains(vim.api.nvim_buf_get_lines(second_buf, 0, -1, false), '<<<<<<< HEAD')
        and vim.api.nvim_get_current_win() == auto_sidebar.code.winid
    end), 'Completion must automatically open native multi-file conflict review without Space ar or A')
    assert(vim.tbl_contains({ first_file, second_file }, vim.api.nvim_buf_get_name(0)),
      'Automatic review must show a proposed file, not the original unrelated file')
    assert(vim.deep_equal(vim.fn.readfile(fixture), { 'return 1' })
      and vim.deep_equal(vim.api.nvim_buf_get_lines(vim.fn.bufnr(fixture), 0, -1, false), { 'return 1' }),
      'Automatic review must not select an older response from a stale cursor position')
    assert(auto_sidebar:get_input_value() == 'Draft while waiting for automatic review',
      'Automatic review must preserve a draft typed during generation')
    assert(vim.deep_equal(vim.fn.readfile(first_file), reviewed_first)
      and vim.deep_equal(vim.fn.readfile(second_file), { 'return "after"' }),
      'Automatically prepared conflicts must not be accepted or saved')
    local current_review_buf = vim.api.nvim_get_current_buf()
    local next_review_buf = current_review_buf == first_buf and second_buf or first_buf
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    vim.api.nvim_feedkeys('co', 'xt', false)
    assert(vim.api.nvim_get_current_buf() == current_review_buf,
      'Automatically prepared review must stay in the file after rejecting its final hunk')
    vim.cmd.AvanteReviewNext()
    assert(vim.api.nvim_get_current_buf() == next_review_buf,
      'The next automatically prepared file must remain available through manual navigation')
    vim.api.nvim_feedkeys('co', 'xt', false)
    vim.cmd.AvanteReviewNext()
    assert(notices[#notices].message == 'No pending Avante conflict markers remain in this tab.',
      'Manual navigation must finish without revisiting resolved files')
    for _, buf in ipairs({ first_buf, second_buf }) do
      vim.api.nvim_buf_call(buf, function() vim.cmd.write() end)
    end
    for _, case in ipairs({ 'answer', 'cancelled', 'other-tab' }) do
      mock_response = case == 'answer' and 'This is an explanation without file changes.' or table.concat({
        '<FILEPATH>' .. first_file .. '</FILEPATH>',
        '<SEARCH>', 'local first = 10', '</SEARCH>',
        '<REPLACE>', 'local first = 1000', '</REPLACE>',
      }, '\n')
      local count = requests
      auto_sidebar:handle_submit('Check completion behavior: ' .. case)
      assert(vim.wait(2000, function() return requests > count end), case .. ': request did not start')
      vim.api.nvim_set_current_win(auto_sidebar.containers.input.winid)
      local owner_tab = vim.api.nvim_get_current_tabpage()
      if case == 'other-tab' then vim.cmd.tabnew() end
      local focused_win = vim.api.nvim_get_current_win()
      last_stream_options.on_stop({ reason = case == 'cancelled' and 'cancelled' or 'complete' })
      local completion_checked = false
      vim.defer_fn(function() completion_checked = true end, 50)
      assert(vim.wait(1000, function() return completion_checked end), 'Completion callbacks must finish')
      assert(vim.api.nvim_get_current_win() == focused_win, case .. ': completion must not steal focus; current='
        .. vim.api.nvim_buf_get_name(0) .. ', state=' .. tostring(auto_sidebar.current_state))
      assert(vim.deep_equal(vim.api.nvim_buf_get_lines(first_buf, 0, -1, false), reviewed_first),
        case .. ': completion must not prepare unwanted conflicts')
      if case == 'other-tab' then
        assert(notices[#notices].message == 'Suggestions are ready in their chat tab; use Space ar, then A to review.',
          'Background-tab completion must explain how to open its review')
        vim.cmd('tabclose!')
        assert(vim.api.nvim_get_current_tabpage() == owner_tab)
        vim.api.nvim_feedkeys(' ar', 'xt', false)
        vim.api.nvim_feedkeys('A', 'xt', false)
        assert(vim.wait(2000, function()
          return vim.tbl_contains(vim.api.nvim_buf_get_lines(first_buf, 0, -1, false), '<<<<<<< HEAD')
        end), 'A background-tab proposal must remain available for manual review')
        vim.api.nvim_win_set_cursor(0, { 1, 0 })
        vim.api.nvim_feedkeys('co', 'xt', false)
        vim.cmd.write()
      end
    end
    assert(#errors == 0, table.concat(errors, '\n'))
    auto_sidebar:close({ goto_code_win = false })
    vim.cmd('tabclose!')
    vim.cmd.tabnew()
    vim.cmd.edit(fixture)
    local resume_file_win = vim.api.nvim_get_current_win()
    api.ask({ ask = false, new_chat = true })
    local resume_sidebar = require('avante').get()
    saved_rule = 'Preserve the saved fixture policy.'
    resume_sidebar.chat_history.system_prompt = saved_rule .. ' This older chat has no native edit instructions.'
    local History = require('avante.history')
    resume_sidebar:add_history_messages({
      History.Message:new('user', 'Original fixture request', { is_user_submission = true }),
      History.Message:new('assistant', 'I cannot edit files from chat.', { state = 'generated' }),
    }, { eager_update = true })
    local saved_history = vim.deepcopy(resume_sidebar.chat_history)
    local history_path = require('avante.path').history
    history_path.save(resume_sidebar.code.bufnr, resume_sidebar.chat_history)
    resume_sidebar:close({ goto_code_win = false })
    vim.api.nvim_set_current_win(resume_file_win)
    local history_selector = require('avante.history_selector')
    local select_history = history_selector.open
    history_selector.open = function(_, callback) callback(saved_history.filename) end
    api.select_history()
    history_selector.open = select_history
    resume_sidebar = require('avante').get()
    assert(resume_sidebar.chat_history.filename == saved_history.filename
      and vim.deep_equal(resume_sidebar.chat_history.messages, saved_history.messages),
      'The native history selector must reuse the existing conversation')
    assert(config.ask_opts.ask == false, 'The resumed fixture must reproduce the old chat-only setting')
    local native_prompt
    resume_sidebar:get_generate_prompts_options('', function(options)
      native_prompt = llm.generate_prompts(options)
    end)
    assert(not native_prompt.system_prompt:find('All changes to files must use this *SEARCH/REPLACE block* format', 1, true),
      'The saved fixture prompt must reproduce the missing native legacy template')
    resume_sidebar:set_input_value('Retained resumed-chat draft')
    mock_response = table.concat({
      '<FILEPATH>' .. fixture .. '</FILEPATH>',
      '<SEARCH>', 'return 1', '</SEARCH>',
      '<REPLACE>', 'return 2', '</REPLACE>',
    }, '\n')
    local count = requests
    resume_sidebar:handle_submit('Propose the edit in this existing conversation')
    assert(vim.wait(2000, function() return requests > count end), 'Resumed legacy submission did not start')
    assert(config.ask_opts.ask == true, 'Submitting in legacy mode must clear the stale chat-only setting')
    assert(resume_sidebar.chat_history.filename == saved_history.filename,
      'Correcting the prompt must not create a new conversation')
    assert(resume_sidebar.chat_history.system_prompt == saved_history.system_prompt,
      'Correcting the prompt must not erase saved system instructions')
    for i, message in ipairs(saved_history.messages) do
      assert(vim.deep_equal(resume_sidebar.chat_history.messages[i], message),
        'Correcting the prompt must preserve existing conversation messages')
    end
    last_stream_options.on_stop({ reason = 'complete' })
    local resumed_buf = vim.fn.bufnr(fixture)
    assert(vim.wait(2000, function()
      return vim.tbl_contains(vim.api.nvim_buf_get_lines(resumed_buf, 0, -1, false), '<<<<<<< HEAD')
        and vim.api.nvim_get_current_win() == resume_sidebar.code.winid
    end), 'A resumed chat must prepare native review in its own tab without starting a new chat')
    assert(resume_sidebar:get_input_value() == 'Retained resumed-chat draft',
      'Resumed-chat prompt repair must preserve the input draft')
    assert(vim.deep_equal(vim.fn.readfile(fixture), { 'return 1' }),
      'Resumed proposals must remain unaccepted until reviewed')
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    vim.api.nvim_feedkeys('co', 'xt', false)
    vim.cmd.write()
    assert(#errors == 0, table.concat(errors, '\n'))
    resume_sidebar:close({ goto_code_win = false })
    vim.cmd('tabclose!')
    saved_rule = nil
    mock_response = nil
    vim.cmd.tabnew()
    vim.cmd.edit(fixture)
    local count = requests
    vim.api.nvim_feedkeys('V aw', 'xt', false)
    local sidebar = require('avante').get()
    assert(sidebar.code.selection.content == 'return 1' and sidebar.code.selection.filepath == fixture,
      'Visual write must also attach code when opening a closed chat')
    assert(vim.deep_equal(vim.api.nvim_buf_get_lines(sidebar.containers.selected_code.bufnr, 0, -1, false),
      { 'return 1' }), 'A newly opened chat must show its attached selection')
    assert(requests == count, 'Opening a chat with selected code must not submit a question')
    vim.cmd.stopinsert()
    local review_focus_finished = false
    vim.defer_fn(function() review_focus_finished = true end, 150)
    assert(vim.wait(1000, function() return review_focus_finished end),
      'Native delayed review cursor moves must finish before testing Insert-mode input')
  ]],
    { vim.fn.getcwd(), artifacts }
  )
  vim.rpcrequest(child, 'nvim_input', ' aw')
  assert(
    vim.wait(2000, function()
      return vim.rpcrequest(
        child,
        'nvim_exec_lua',
        "return vim.bo.filetype == 'AvanteInput' and vim.api.nvim_get_mode().mode == 'i'",
        {}
      )
    end),
    'Space aw must enter typing mode'
  )
  vim.rpcrequest(child, 'nvim_input', 'Draft ar')
  assert(
    vim.wait(1000, function()
      return vim.rpcrequest(
        child,
        'nvim_exec_lua',
        "return require('avante').get():get_input_value() == 'Draft ar'",
        {}
      )
    end),
    'Typing a review-key prefix in Insert mode must remain ordinary text'
  )
  vim.rpcrequest(
    child,
    'nvim_exec_lua',
    [[
    local sidebar = require('avante').get()
    require('cmp').setup.buffer({ completion = { autocomplete = false } })
    vim.g.avante_test_file_picker_calls = 0
    sidebar.file_selector.open = function()
      vim.g.avante_test_file_picker_calls = vim.g.avante_test_file_picker_calls + 1
    end
  ]],
    {}
  )
  vim.rpcrequest(child, 'nvim_exec_lua', "require('avante').get():set_input_value('')", {})
  vim.rpcrequest(child, 'nvim_input', '@')
  assert(
    vim.wait(1000, function()
      return vim.rpcrequest(child, 'nvim_exec_lua', "return require('avante').get():get_input_value() == '@'", {})
    end),
    'The mention trigger must be typed before requesting completion'
  )
  vim.rpcrequest(child, 'nvim_input', '<C-Space>')
  assert(
    vim.wait(2000, function()
      return vim.rpcrequest(
        child,
        'nvim_exec_lua',
        [[
      local cmp = require('cmp')
      return cmp.visible() and #cmp.get_entries() > 1
    ]],
        {}
      )
    end),
    'Ctrl+Space must open the native Avante mention completion menu'
  )
  vim.rpcrequest(
    child,
    'nvim_exec_lua',
    "require('cmp').select_next_item({ behavior = require('cmp').SelectBehavior.Select })",
    {}
  )
  local initial_item =
    vim.rpcrequest(child, 'nvim_exec_lua', "return require('cmp').get_selected_entry():get_completion_item().label", {})
  vim.rpcrequest(child, 'nvim_input', '<C-k>')
  assert(
    vim.wait(1000, function()
      return vim.rpcrequest(
        child,
        'nvim_exec_lua',
        "return require('cmp').get_selected_entry():get_completion_item().label ~= ...",
        { initial_item }
      )
    end),
    'Ctrl+k must select the next Avante completion'
  )
  vim.rpcrequest(child, 'nvim_input', '<C-l>')
  assert(
    vim.wait(1000, function()
      return vim.rpcrequest(
        child,
        'nvim_exec_lua',
        "return require('cmp').get_selected_entry():get_completion_item().label == ...",
        { initial_item }
      )
    end),
    'Ctrl+l must select the previous Avante completion'
  )
  vim.rpcrequest(child, 'nvim_input', '<C-e>')
  assert(
    vim.wait(1000, function()
      return vim.rpcrequest(child, 'nvim_exec_lua', "return not require('cmp').visible()", {})
    end),
    'Ctrl+e must close the Avante completion menu'
  )
  vim.rpcrequest(child, 'nvim_exec_lua', "require('avante').get():set_input_value('')", {})
  vim.rpcrequest(child, 'nvim_input', '@file')
  assert(
    vim.wait(1000, function()
      return vim.rpcrequest(child, 'nvim_exec_lua', "return require('avante').get():get_input_value() == '@file'", {})
    end),
    'Typing a file mention must remain ordinary input'
  )
  vim.rpcrequest(child, 'nvim_input', '<C-Space>')
  assert(
    vim.wait(2000, function()
      return vim.rpcrequest(
        child,
        'nvim_exec_lua',
        [[
      local cmp = require('cmp')
      local entries = cmp.get_entries()
      return cmp.visible() and #entries == 1 and entries[1]:get_completion_item().label == '@file '
    ]],
        {}
      )
    end),
    'Ctrl+Space must open the filtered @file completion'
  )
  vim.rpcrequest(child, 'nvim_input', '<C-y>')
  assert(
    vim.wait(2000, function()
      return vim.rpcrequest(
        child,
        'nvim_exec_lua',
        [[
      return vim.g.avante_test_file_picker_calls == 1
        and require('avante').get():get_input_value() == ''
    ]],
        {}
      )
    end),
    'Ctrl+y must accept @file and execute its native file-picker callback'
  )
end, debug.traceback)
vim.fn.jobstop(child)
vim.fn.delete(artifacts, 'rf')
assert(ok, err)
print 'Avante defaults, MCP discovery, requests, approvals, focus, selection, instructions, and context regression tests passed'

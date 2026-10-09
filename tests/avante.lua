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
    vim.cmd.cd(artifacts)
    local fixture = artifacts .. '/fixture.lua'
    vim.fn.writefile({ 'return 1' }, fixture)
    local errors = {}
    vim.notify = function(message, level)
      if level == vim.log.levels.ERROR then errors[#errors + 1] = tostring(message) end
    end
    local spec = dofile(repo .. '/lua/marten/plugins/avante.lua')
    local language_prompt = 'Respond in English unless the user explicitly requests another language.'
    local original_mcphub = package.loaded.mcphub
    package.loaded.mcphub = { get_hub_instance = function() return nil end }
    assert(spec.opts.system_prompt() == language_prompt, 'English instructions must be present without MCPHub')
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
    opts.system_prompt = function() return language_prompt end
    opts.custom_tools = function() return {} end
    spec.config(spec, opts)
    local helpers = require('avante.llm_tools.helpers')
    local confirm_inline = helpers.confirm_inline
    local prompts = 0
    helpers.confirm_inline = function(callback)
      prompts = prompts + 1
      callback('reject_once')
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
      assert(vim.wait(1000, function() return approved ~= nil end), tool .. ' permission did not resolve')
      assert(approved == false, tool .. ' must honor rejection')
    end
    helpers.confirm_inline = confirm_inline
    local llm = require('avante.llm')
    local provider = require('avante.providers').copilot
    local copilot = require('avante.providers.copilot')
    local requests = 0
    llm.stream = function(stream_opts)
      requests = requests + 1
      local prompt = llm.generate_prompts(stream_opts)
      assert(prompt.system_prompt:find(language_prompt, 1, true), 'English instructions must reach the model prompt')
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
      require('avante.api').ask({ ask = false, new_chat = true })
      local sidebar = require('avante').get()
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
      local count = requests
      sidebar:handle_submit('Explain this fixture')
      assert(vim.wait(2000, function() return requests > count end), 'Message submission did not reach the request builder')
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
  ]],
    { vim.fn.getcwd(), artifacts }
  )
end, debug.traceback)
vim.fn.jobstop(child)
vim.fn.delete(artifacts, 'rf')
assert(ok, err)
print 'Avante defaults, MCP discovery, request deadlines, tool approvals, language, and terminal-context regression tests passed'

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
    assert(spec.opts.providers.copilot.model == 'claude-opus-5.5', 'Opus 5.5 must be the default model')
    assert(spec.opts.providers.copilot.extra_request_body.reasoning_effort == 'high', 'High reasoning must remain enabled')
    local opts = vim.deepcopy(spec.opts)
    opts.history = { storage_path = artifacts .. '/history' }
    opts.prompt_logger = { enabled = false }
    opts.behaviour.use_cwd_as_project_root = true
    opts.system_prompt = function() return '' end
    opts.custom_tools = function() return {} end
    spec.config(spec, opts)
    local llm = require('avante.llm')
    local provider = require('avante.providers').copilot
    local copilot = require('avante.providers.copilot')
    local requests = 0
    llm.stream = function(stream_opts)
      requests = requests + 1
      local prompt = llm.generate_prompts(stream_opts)
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
print 'Avante defaults and terminal-context regression tests passed'

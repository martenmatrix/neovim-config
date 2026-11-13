local repo = vim.fn.getcwd()
local plugins = vim.fn.stdpath 'data' .. '/lazy'
local artifacts = vim.fn.tempname()
vim.fn.mkdir(artifacts, 'p')
artifacts = assert(vim.uv.fs_realpath(artifacts))
local child = vim.fn.jobstart({ vim.v.progpath, '--embed', '--headless', '-u', 'NONE', '-n' }, {
  rpc = true,
  env = { XDG_DATA_HOME = artifacts .. '/data', XDG_STATE_HOME = artifacts .. '/state' },
})
assert(child > 0, 'Could not start Neovim for worktree tests')

local function exec(code, ...)
  return vim.rpcrequest(child, 'nvim_exec_lua', code, { ... })
end

local function wait_for(code, message)
  local ready = vim.wait(10000, function()
    return exec(code)
  end, 10)
  if not ready then
    local state = exec [[
      local state = { cwd = vim.fn.getcwd(), mode = vim.fn.mode(), errors = errors }
      state.chats = vim.tbl_map(function(chat)
        return { cycle = chat.cycle, running = chat.current_request ~= nil, status = chat.status }
      end, chats or {})
      if vim.bo.filetype == 'TelescopePrompt' then
        local picker = require('telescope.actions.state').get_current_picker(vim.api.nvim_get_current_buf())
        state.prompt, state.results = picker:_get_prompt(), picker.manager:num_results()
        state.entries = picker.finder.results
      end
      return state
    ]]
    error(message .. ': ' .. vim.inspect(state))
  end
end

local function keys(value)
  vim.rpcrequest(child, 'nvim_input', value)
end

local function run()
  vim.rpcrequest(child, 'nvim_ui_attach', 180, 60, { rgb = true })
  exec(
    [[
    local repo, plugins, artifacts = ...
    vim.opt.rtp:prepend(repo)
    for _, path in ipairs(vim.fn.glob(plugins .. '/*', false, true)) do
      vim.opt.rtp:append(path)
    end
    vim.cmd 'filetype plugin on'
    require 'marten.core.keymaps'
    vim.o.swapfile = false
    vim.o.splitright = true
    vim.o.splitbelow = true
    vim.o.shell = '/bin/sh'
    _G.source = artifacts .. '/source project'
    _G.foreign = artifacts .. '/foreign project'
    _G.git = function(directory, ...)
      local result = vim.system({ 'git', '-C', directory, ... }, { text = true }):wait()
      assert(result.code == 0, result.stderr)
      return vim.trim(result.stdout)
    end
    for _, directory in ipairs({ source, foreign }) do
      vim.fn.mkdir(directory, 'p')
      vim.fn.writefile({ directory == foreign and "return 'foreign'" or "return 'first'" }, directory .. '/first.lua')
      vim.fn.writefile({ "return 'second'" }, directory .. '/second.lua')
      git(directory, 'init', '-q')
      git(directory, 'add', '.')
      git(directory, '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.com', 'commit', '-qm', 'chore(): fixture')
    end
    _G.source_head = git(source, 'rev-parse', 'HEAD')
    vim.fn.writefile({ 'staged work' }, source .. '/existing.txt')
    git(source, 'add', 'existing.txt')
    vim.fn.writefile({ 'unstaged work' }, source .. '/existing.txt')
    _G.source_index = git(source, 'write-tree')
    vim.cmd.tcd(vim.fn.fnameescape(source))
    vim.cmd.edit(vim.fn.fnameescape(source .. '/first.lua'))
    _G.origin = vim.api.nvim_get_current_tabpage()
    dofile(repo .. '/lua/marten/plugins/everforest.lua').config()
    require('telescope').setup {}
    local cc = dofile(repo .. '/lua/marten/plugins/codecompanion.lua')
    cc.opts.adapters.acp.extend.copilot_acp.commands.default =
      { 'python3', repo .. '/tests/fixtures/codecompanion-acp.py' }
    cc.config(cc, cc.opts)
    vim.cmd.runtime 'plugin/codecompanion.lua'
    local manager = dofile(repo .. '/lua/marten/plugins/git-worktree.lua')
    manager.init()
    for _, spec in ipairs({ cc, manager }) do
      for _, mapping in ipairs(spec.keys) do
        vim.keymap.set(mapping.mode or 'n', mapping[1], mapping[2])
      end
    end
    _G.controls = require 'marten.core.codecompanion'
    _G.worktrees = require 'marten.core.worktrees'
    _G.chats = {}
    _G.errors = {}
    vim.notify = function(message, level)
      if level == vim.log.levels.ERROR then table.insert(errors, tostring(message)) end
    end
    vim.ui.input = function(_, callback) _G.task_prompt = callback end
    vim.env.NVIM_ACP_FIXTURE_LOG = artifacts .. '/acp.jsonl'
    vim.env.NVIM_ACP_FIXTURE_DELAY = '0.2'
    vim.api.nvim_create_autocmd('User', {
      pattern = 'CodeCompanionChatAdapter',
      callback = function(event)
        if event.data.adapter then
          -- Run before the scheduled process spawn, forcing the startup cwd race.
          vim.schedule(function() vim.api.nvim_set_current_tabpage(origin) end)
        end
      end,
    })
    vim.api.nvim_create_autocmd('User', {
      pattern = 'CodeCompanionChatCreated',
      callback = function(event)
        table.insert(chats, require('codecompanion').buf_get_chat(event.data.bufnr))
      end,
    })
  ]],
    repo,
    plugins,
    artifacts
  )
  keys ' an'
  wait_for('return task_prompt ~= nil', 'Space an must prompt for a new isolated task')
  exec [[
    vim.cmd.tcd(vim.fn.fnameescape(foreign))
    task_prompt('task-a')
    task_prompt = nil
    vim.cmd.tcd(vim.fn.fnameescape(source))
  ]]
  wait_for('return #chats == 1', 'Creating the first worktree must start its native chat')
  exec [[
    _G.a = chats[1]
    _G.path_a = vim.b[a.bufnr].codecompanion_cwd
    assert(path_a ~= source and vim.fs.basename(path_a) == 'task-a', 'Task A must have its own checkout')
    assert(git(path_a, 'rev-parse', 'HEAD') == source_head, 'Creation must use the captured source repository')
    assert(git(path_a, 'branch', '--show-current') == 'ai/task-a', 'The task must use a separate branch')
    assert(vim.fn.filereadable(path_a .. '/existing.txt') == 0, 'Uncommitted source work must not be copied')
    assert(vim.api.nvim_buf_get_name(a.buffer_context.bufnr) == path_a .. '/first.lua',
      'Initial source context must use the task checkout, not the original file')
    assert(vim.fn.getcwd() == source, 'The regression must switch tabs before ACP startup')
  ]]
  keys '<Esc> wn'
  wait_for('return task_prompt ~= nil', 'Space wn must provide the same task launcher')
  exec "task_prompt('task-b'); task_prompt = nil"
  wait_for('return #chats == 2', 'Creating the second task must start another native chat')
  wait_for(
    [[
    return chats[1].acp_connection.session_id ~= nil and chats[2].acp_connection.session_id ~= nil
  ]],
    'Both ACP sessions must connect after asynchronous tab switches'
  )
  exec(
    [[
    local artifacts, repo = ...
    _G.b = chats[2]
    _G.path_b = vim.b[b.bufnr].codecompanion_cwd
    assert(path_b ~= path_a, 'Tasks must not share a checkout')
    for _, chat in ipairs(chats) do
      local cwd = vim.b[chat.bufnr].codecompanion_cwd
      local pid = chat.acp_connection._state.handle.pid
      local spawned, established = false, false
      for _, line in ipairs(vim.fn.readfile(artifacts .. '/acp.jsonl')) do
        local entry = vim.json.decode(line)
        if entry.pid == pid then
          assert(entry.cwd == cwd, 'Each agent process must start in its captured task directory')
          if entry.method == 'initialize' then spawned = true end
          if entry.method == 'session/new' then
            assert(entry.session_cwd == cwd, 'Session creation must not inherit another tab cwd')
            established = true
          end
        end
      end
      assert(spawned and established, 'The fixture must exercise real process and session startup')
    end
    assert(vim.fn.getcwd() == source, 'The original tab must retain its directory')
    for _, plugin in ipairs(dofile(repo .. '/lua/marten/plugins/init.lua')) do
      if type(plugin) == 'table' and plugin[1] == 'alvarosevilla95/luatab.nvim' then plugin.config() end
    end
    local labels = require('luatab').helpers.tabline()
    assert(labels:find('AI: task-a', 1, true) and labels:find('AI: task-b', 1, true),
      'The rendered tabline must distinguish the two task worktrees')
    _G.before_tabs = #vim.api.nvim_list_tabpages()
  ]],
    artifacts,
    repo
  )
  keys '<Esc> ww'
  wait_for(
    'return vim.bo.filetype == "TelescopePrompt" and vim.fn.mode() == "i"',
    'Space ww must open a visible worktree picker'
  )
  keys 'ai/task-a'
  wait_for(
    [[
    local state = require 'telescope.actions.state'
    local picker = state.get_current_picker(vim.api.nvim_get_current_buf())
    local selected = state.get_selected_entry()
    return picker and picker:_get_prompt() == 'ai/task-a' and selected and selected.value.path == path_a
  ]],
    'The picker must find task A'
  )
  keys '<CR>'
  wait_for(
    'return controls.current_chat() == a and vim.fn.mode() == "i"',
    'Selecting task A must focus its existing chat'
  )
  exec [[
    assert(#vim.api.nvim_list_tabpages() == before_tabs and #chats == 2, 'Picking a task must not duplicate tabs or agents')
    _G.tab_a = vim.api.nvim_get_current_tabpage()
    vim.api.nvim_win_set_width(a.ui.winnr, 53)
    _G.layout_a = vim.fn.winlayout()
  ]]
  keys '<Esc>G$Adraft task A<Esc>'
  exec [[
    assert(table.concat(vim.api.nvim_buf_get_lines(a.bufnr, 0, -1, false), '\n'):find('draft task A', 1, true),
      'Typing in the reopened task must retain the chat draft')
    a:add_buf_message { role = 'user', content = 'HOLD_FIXTURE' }
    a:submit()
    worktrees.open(path_b)
    _G.tab_b = vim.api.nvim_get_current_tabpage()
    b:add_buf_message { role = 'user', content = 'HOLD_FIXTURE' }
    b:submit()
  ]]
  wait_for(
    'return a.current_request ~= nil and b.current_request ~= nil',
    'Two tasks must be able to run simultaneously'
  )
  exec [[
    local store = require 'codecompanion.interactions.code_review.store'
    assert(store.round_open(path_a) and store.round_open(path_b), 'Each worktree must have a separate review round')
    a:stop()
  ]]
  wait_for('return a.current_request == nil and a.cycle > 1', 'Task A must finish cancellation in the background')
  exec [[
    assert(require('codecompanion.interactions.code_review.store').round_open(path_b),
      'Background completion must not clear the other worktree review round')
    assert(vim.api.nvim_get_current_tabpage() == tab_b, 'Background completion must not steal focus')
    b:stop()
  ]]
  wait_for('return b.current_request == nil and b.cycle > 1', 'Task B must finish cancellation')
  exec [[
    worktrees.open(path_a)
    vim.cmd.tcd(vim.fn.fnameescape(foreign))
    worktrees.open(path_a)
    assert(vim.fn.getcwd() == path_a, 'Returning to a task must restore its own directory after cross-project navigation')
    assert(vim.deep_equal(vim.fn.winlayout(), layout_a), 'Returning to task A must retain its layout')
    assert(vim.api.nvim_win_get_width(a.ui.winnr) == 53, 'Returning must preserve resized chat panes')
    a:add_buf_message { role = 'user', content = 'EDIT_FIXTURE' }
    a:submit()
    worktrees.open(path_b)
    b:add_buf_message { role = 'user', content = 'FOLLOWUP_FIXTURE' }
    b:submit()
  ]]
  wait_for(
    'return a.current_request == nil and b.current_request == nil and a.cycle > 2 and b.cycle > 2',
    'Both agents must complete edits in their separate checkouts'
  )
  exec [[
    assert(vim.fn.readfile(path_a .. '/first.lua')[1] == "return 'changed first'", 'Task A edits must stay in A')
    assert(vim.fn.readfile(path_b .. '/first.lua')[1] == "return 'followup'", 'Task B edits must stay in B')
    assert(vim.fn.readfile(source .. '/first.lua')[1] == "return 'first'", 'The original checkout must remain unchanged')
    assert(vim.fn.readfile(source .. '/existing.txt')[1] == 'unstaged work', 'Original dirty work must survive')
    assert(git(source, 'write-tree') == source_index and git(source, 'rev-parse', 'HEAD') == source_head,
      'Task creation and review must not alter the original index or HEAD')
    local baseline = require 'codecompanion.interactions.code_review.baseline'
    assert(#baseline.diff(path_a) == 2 and #baseline.diff(path_b) == 1, 'Review diffs must remain worktree-specific')
    worktrees.open(path_a)
    controls.review()
    assert(vim.bo.filetype == 'codecompanion_code_review', 'Native review must work inside task worktrees')
    require('codecompanion.interactions.code_review.window').close()
    worktrees.open(path_b)
    controls.review()
    assert(vim.bo.filetype == 'codecompanion_code_review', 'Native review must also open in the second task')
    require('codecompanion.interactions.code_review.window').close()
    assert(#baseline.diff(path_a) == 2, 'Reviewing B must not consume A changes')
    worktrees.open(path_a)
    _G.chat_a_buffer = a.bufnr
    a.ui:hide()
    vim.cmd 'tabclose!'
    worktrees.open(path_a, 'first.lua')
    assert(controls.current_chat().bufnr == chat_a_buffer, 'Reopening a closed task tab must reuse its living chat')
    local count = #vim.api.nvim_list_tabpages()
    worktrees.new()
    task_prompt('task-a')
    assert(#vim.api.nvim_list_tabpages() == count and #errors == 1
      and errors[1]:find('already exists', 1, true), 'Duplicate task names must fail explicitly without another tab')
    errors = {}
    worktrees.new()
    task_prompt('../escape')
    assert(#errors == 1 and errors[1]:find('task name', 1, true), 'Invalid task names must be rejected explicitly')
    errors = {}
    _G.agent_pids = { a.acp_connection._state.handle.pid, b.acp_connection._state.handle.pid }
    a:close()
    b:close()
    assert(#errors == 0, table.concat(errors, '\n'))
  ]]
  wait_for(
    [[
    return vim.uv.kill(agent_pids[1], 0) == nil and vim.uv.kill(agent_pids[2], 0) == nil
  ]],
    'Closing both task chats must stop their ACP processes'
  )
end

local ok, failure = xpcall(run, debug.traceback)
vim.fn.jobstop(child)
vim.fn.delete(artifacts, 'rf')
assert(ok, failure)
print 'Worktree shortcuts, concurrent ACP isolation, native reviews and tab/chat restoration passed'

local child = vim.fn.jobstart({ vim.v.progpath, '--embed', '--headless', '-u', 'NONE', '-n' }, { rpc = true })
assert(child > 0, 'Could not start Neovim for CodeCompanion tests')
local artifacts = vim.fn.tempname()
vim.fn.mkdir(artifacts, 'p')

local function exec(code, ...)
  return vim.rpcrequest(child, 'nvim_exec_lua', code, { ... })
end

local function wait_for(code, message)
  assert(
    vim.wait(5000, function()
      return exec(code)
    end, 10),
    message
  )
end

local function keys(value)
  vim.rpcrequest(child, 'nvim_input', value)
end

local function run()
  vim.rpcrequest(child, 'nvim_ui_attach', 180, 60, { rgb = true })
  exec(
    [[
    local repo, directory = ...
    vim.opt.rtp:prepend(repo)
    for _, path in ipairs(vim.fn.glob(vim.fn.stdpath('data') .. '/lazy/*', false, true)) do
      vim.opt.rtp:append(path)
    end
    vim.cmd 'filetype plugin on'
    require 'marten.core.keymaps'
    vim.o.splitright = true
    vim.o.splitbelow = true
    vim.o.swapfile = false
    vim.o.shell = '/bin/sh'
    vim.cmd.cd(directory)
    vim.fn.writefile({ "return 'first'" }, 'first.lua')
    vim.fn.writefile({ "return 'second'" }, 'second.lua')
    local function git(...)
      local result = vim.system({ 'git', ... }, { text = true }):wait()
      assert(result.code == 0, result.stderr)
      return vim.trim(result.stdout)
    end
    _G.fixture_git = git
    git('init', '-q')
    git('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.com', 'add', '.')
    git('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.com', 'commit', '-qm', 'chore(): fixture')
    _G.fixture_head = git('rev-parse', 'HEAD')
    vim.fn.writefile({ 'staged work' }, 'existing.txt')
    git('add', 'existing.txt')
    vim.fn.writefile({ 'unstaged work' }, 'existing.txt')
    _G.fixture_index = git('write-tree')
    vim.cmd.edit('first.lua')
    _G.fixture_editor = vim.api.nvim_get_current_win()
    local blink = dofile(repo .. '/lua/marten/plugins/lsp/blink-cmp.lua')
    require('blink.cmp').setup(blink.opts)
    local renderer = dofile(repo .. '/lua/marten/plugins/render-markdown.lua')
    require('render-markdown').setup(renderer.opts)
    vim.cmd.runtime('plugin/render-markdown.lua')
    require('img-clip').setup(dofile(repo .. '/lua/marten/plugins/img-clip.lua').opts)
    local spec = dofile(repo .. '/lua/marten/plugins/codecompanion.lua')
    spec.opts.adapters.acp.extend.copilot_acp.commands.default = { 'python3', repo .. '/tests/fixtures/codecompanion-acp.py' }
    spec.opts.interactions.code_review.opts = { storage_dir = directory .. '/.git/reviews' }
    spec.config(spec, spec.opts)
    vim.cmd.runtime('plugin/codecompanion.lua')
    for _, mapping in ipairs(spec.keys) do
      vim.keymap.set(mapping.mode or 'n', mapping[1], mapping[2])
    end
    _G.cc = require 'codecompanion'
    _G.controls = require 'marten.core.codecompanion'
    _G.fixture_errors = {}
    _G.fixture_notices = {}
    vim.notify = function(message, level)
      table.insert(fixture_notices, tostring(message))
      if level == vim.log.levels.ERROR then table.insert(fixture_errors, tostring(message)) end
    end
    controls.write(true)
    _G.chat = controls.current_chat()
    assert(chat and chat.adapter.type == 'acp', 'The chat must use ACP')
    assert(chat.buffer_context.bufnr == vim.api.nvim_win_get_buf(fixture_editor), 'Current-file context must be real code')
    assert(#chat.context_items > 0, 'Ask must attach current-file context')
    for _, plugin in ipairs(dofile(repo .. '/lua/marten/plugins/init.lua')) do
      if type(plugin) == 'table' and plugin[1] == 'alvarosevilla95/luatab.nvim' then plugin.config() end
    end
    chat:set_title('Instructions\n# Table of contents\n- [Project context](#project-context)')
    assert(require('luatab').helpers.title(chat.bufnr) == 'CodeCompanion',
      'Chat tabs must not expose instruction text from an ACP session title')
    assert(not require('luatab').helpers.tabline():find('Project context', 1, true),
      'The rendered tabline must use the safe chat label')
    assert(require('luatab').helpers.title(vim.api.nvim_win_get_buf(fixture_editor)) == 'first.lua',
      'Ordinary file labels must remain unchanged')
  ]],
    vim.fn.getcwd(),
    artifacts
  )
  wait_for('return chat.acp_connection and chat.acp_connection.session_id ~= nil', 'ACP fixture must connect')
  exec [[
    local select = vim.ui.select
    _G.model_picker = false
    vim.ui.select = function(items, opts, callback)
      assert(opts.prompt == 'Select Model' and items[1].modelId == 'fixture-model',
        'Model shortcut must offer ACP models, not switch to HTTP')
      model_picker = true
      callback(nil)
    end
    controls.model()
    vim.ui.select = select
    assert(model_picker, 'Model shortcut must open the native picker')
  ]]
  keys '<Esc>G$Afirst draft'
  wait_for(
    [[return vim.api.nvim_get_current_line():find('first draft', 1, true) ~= nil]],
    'Typing must reach the draft'
  )
  keys '<Esc>'
  exec [[
    _G.fixture_chat_buf = chat.bufnr
    _G.fixture_chat_win = chat.ui.winnr
    vim.api.nvim_win_set_width(fixture_chat_win, 53)
    vim.api.nvim_set_current_win(fixture_editor)
    vim.cmd 'split'
    _G.fixture_extra = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_height(fixture_extra, 16)
    _G.fixture_layout = vim.fn.winlayout()
    _G.fixture_sizes = {}
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      fixture_sizes[win] = { vim.api.nvim_win_get_width(win), vim.api.nvim_win_get_height(win) }
    end
    vim.api.nvim_set_current_win(fixture_editor)
  ]]
  keys 'V aa'
  wait_for('return vim.bo.filetype == "codecompanion" and vim.fn.mode() == "i"', 'Visual ask must focus chat input')
  exec [[
    assert(controls.current_chat().bufnr == fixture_chat_buf, 'Selection must reuse this chat')
    local text = table.concat(vim.api.nvim_buf_get_lines(chat.bufnr, 0, -1, false), '\n')
    assert(text:find('first draft', 1, true), 'Selection must preserve draft')
    assert(text:find("return 'first'", 1, true), 'Selection must attach code')
    assert(chat.cycle == 1, 'Selection must not submit')
    assert(vim.deep_equal(fixture_layout, vim.fn.winlayout()), 'Selection must preserve window identities')
    for win, size in pairs(fixture_sizes) do
      assert(vim.api.nvim_win_get_width(win) == size[1] and vim.api.nvim_win_get_height(win) == size[2],
        'Selection must retain manually adjusted split sizes')
    end
  ]]
  keys '<Esc>'
  exec [[
    vim.api.nvim_set_current_win(fixture_editor)
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
  ]]
  keys 'v2; aw'
  wait_for('return vim.bo.filetype == "codecompanion" and vim.fn.mode() == "i"', 'Character selection must focus input')
  exec [[
    local text = table.concat(vim.api.nvim_buf_get_lines(chat.bufnr, 0, -1, false), '\n')
    assert(text:find('```lua\nret\n```', 1, true), 'Character selection must retain exact columns')
  ]]
  keys '<Esc>'
  exec [[
    vim.api.nvim_set_current_win(fixture_editor)
    controls.write()
    assert(controls.current_chat() == chat, 'Write must focus existing chat')
    vim.cmd.stopinsert()
    require('codecompanion.interactions.chat.tools.approvals'):set_mode(chat.bufnr, { mode = 'ask' })
    vim.cmd 'tabnew'
    local second_tab = vim.api.nvim_get_current_tabpage()
    vim.cmd.edit('first.lua')
    controls.write()
    _G.other = controls.current_chat()
    assert(other ~= chat, 'A new tab must not steal the old tab chat')
    assert(vim.api.nvim_get_current_tabpage() == second_tab, 'Chat focus must stay in its tab')
  ]]
  wait_for('return other.acp_connection and other.acp_connection.session_id ~= nil', 'Second tab must connect')
  exec [[
    assert(require('codecompanion.interactions.chat.tools.approvals'):get_mode(other.bufnr) == 'yolo',
      'New chats must start in full auto-approval mode')
    other:add_buf_message({ role = 'user', content = 'FULL_AUTO_PERMISSIONS_FIXTURE' })
    other:submit()
  ]]
  wait_for(
    [[return other.current_request == nil and table.concat(vim.api.nvim_buf_get_lines(other.bufnr,0,-1,false),'\n'):find('Fixture status approvals received',1,true) ~= nil]],
    'A new full-auto chat must approve ACP commands outside the Auto safe list without prompting'
  )
  exec [[
    other:close()
    vim.cmd 'tabclose!'
    vim.api.nvim_set_current_win(fixture_editor)
    controls.write()
    assert(controls.current_chat() == chat, 'Returning to a tab must restore its chat')
    require('codecompanion.interactions.chat.tools.approvals'):set_mode(chat.bufnr, { mode = 'auto' })
    vim.cmd.stopinsert()
    chat:add_buf_message({ role = 'user', content = 'EDIT_FIXTURE' })
    chat:submit()
  ]]
  wait_for('return chat.cycle > 1 and chat.current_request == nil', 'Fixture edit must complete')
  exec [[
    assert(#vim.api.nvim_list_tabpages() == 1, 'Completion must not open a review tab')
    assert(vim.api.nvim_win_get_buf(fixture_editor) == chat.buffer_context.bufnr, 'Completion must not switch files')
    assert(vim.fn.readfile('first.lua')[1] == "return 'changed first'", 'Agent edits must be applied')
    assert(fixture_git('rev-parse', 'HEAD') == fixture_head, 'Snapshot must not move branch HEAD')
    assert(fixture_git('write-tree') == fixture_index, 'Snapshot must preserve the real staging index')
    controls.review()
    _G.review_tab = vim.api.nvim_get_current_tabpage()
    _G.review_tree = vim.api.nvim_get_current_win()
    assert(vim.bo.filetype == 'codecompanion_code_review',
      'Manual review must open native checklist: ' .. table.concat(fixture_notices, '; '))
    _G.review_text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
    assert(review_text:find('first.lua', 1, true) and review_text:find('second.lua', 1, true), 'Review must list both changed files')
    assert(not review_text:find('existing.txt', 1, true), 'Pre-existing dirty work must be baseline, not agent changes')
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(review_tab)) do
      if win ~= review_tree then _G.review_pane = win end
    end
    _G.saved_lsp_clients = vim.lsp.get_clients
    _G.saved_definition = vim.lsp.buf.definition
    _G.saved_implementation = vim.lsp.buf.implementation
    _G.navigation = {}
    _G.implementation_ready = false
    vim.lsp.get_clients = function(opts)
      if opts and opts.method == 'textDocument/definition' then return { {} } end
      if opts and opts.method == 'textDocument/implementation' then return implementation_ready and { {} } or {} end
      return saved_lsp_clients(opts)
    end
    local function location()
      assert(vim.api.nvim_get_current_win() == fixture_editor, 'LSP navigation must use the original file pane')
      assert(vim.fn.expand('%:t') == 'first.lua' and vim.bo.buftype == '', 'LSP must use the real file, not diff text')
      assert(vim.api.nvim_win_get_buf(fixture_chat_win) == fixture_chat_buf, 'Navigation must not replace chat')
      assert(vim.deep_equal(vim.api.nvim_win_get_cursor(0), { 1, 9 }), 'Diff rows must map to real source lines and columns')
    end
    vim.lsp.buf.definition = function() location(); navigation.definition = true end
    vim.lsp.buf.implementation = function() location(); navigation.implementation = true end
    vim.api.nvim_set_current_win(review_pane)
    for row, text in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
      if text == "return 'changed first'" then _G.review_source_row = row end
      if text == "return 'first'" then _G.review_deleted_row = row end
    end
    assert(review_source_row and review_deleted_row, 'Fixture must contain both sides of a replacement')
    vim.api.nvim_win_set_cursor(review_pane, { review_deleted_row, 0 })
    vim.fn.maparg('gd', 'n', false, true).callback()
    assert(vim.api.nvim_get_current_win() == review_pane and not navigation.definition,
      'Deleted lines must not navigate to a different source symbol')
    assert(fixture_notices[#fixture_notices]:find('Deleted lines', 1, true), 'Deleted-line navigation must explain the limitation')
    vim.api.nvim_win_set_cursor(review_pane, { review_source_row, 9 })
    vim.fn.maparg('gd', 'n', false, true).callback()
    assert(navigation.definition, 'Definition must resolve from the real source position')
  ]]
  wait_for('return vim.fn.mode() == "n"', 'LSP navigation must leave the source in Normal mode')
  exec [[
    controls.review()
    assert(vim.api.nvim_get_current_tabpage() == review_tab, 'Navigation must preserve the existing review')
    vim.api.nvim_set_current_win(review_pane)
    vim.api.nvim_win_set_cursor(review_pane, { review_source_row, 9 })
    vim.fn.maparg('gi', 'n', false, true).callback()
  ]]
  wait_for(
    [[return vim.api.nvim_get_current_win() == fixture_editor and vim.fn.mode() == "n" and not navigation.implementation]],
    'Implementation must wait for a newly opened file to attach to its LSP'
  )
  exec [[
    implementation_ready = true
    vim.api.nvim_exec_autocmds('LspAttach', { buffer = vim.api.nvim_get_current_buf(), data = { client_id = 0 } })
    assert(navigation.implementation, 'Delayed LSP attachment must complete the pending navigation')
    vim.lsp.get_clients = saved_lsp_clients
    vim.lsp.buf.definition = saved_definition
    vim.lsp.buf.implementation = saved_implementation
    controls.review()
    vim.api.nvim_set_current_win(review_tree)
    vim.api.nvim_win_set_width(review_tree, 31)
    _G.review_layout = vim.fn.winlayout()
    _G.review_width = vim.api.nvim_win_get_width(review_tree)
    vim.cmd 'tabprevious'
    controls.review()
    assert(vim.api.nvim_get_current_tabpage() == review_tab, 'Review shortcut must focus existing native review')
    assert(vim.deep_equal(review_layout, vim.fn.winlayout()), 'Focusing review must preserve its splits')
    assert(vim.api.nvim_win_get_width(review_tree) == review_width, 'Focusing review must preserve resized width')
    local rows = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for i, row in ipairs(rows) do
      if row:find('first.lua', 1, true) then vim.api.nvim_win_set_cursor(0, { i + 1, 0 }); break end
    end
  ]]
  keys 'gr'
  wait_for([[return vim.fn.readfile('first.lua')[1] == "return 'first'"]], 'Native revert must write original file')
  keys 'u'
  wait_for(
    [[return vim.fn.readfile('first.lua')[1] == "return 'changed first'"]],
    'Native undo must restore reverted edit'
  )
  keys 'gc'
  wait_for('return vim.bo.filetype == "codecompanion_input" and vim.fn.mode() == "i"', 'Native comment must open input')
  keys 'Please keep this readable<Esc><CR>'
  wait_for(
    'return #require("codecompanion.interactions.code_review").pending() == 1',
    'Review comment must be retained'
  )
  exec [[
    vim.api.nvim_set_current_win(review_tree)
    assert(vim.api.nvim_win_get_width(review_tree) == review_width, 'Review actions must retain layout')
    local rows = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for i, row in ipairs(rows) do
      if row:find('second.lua', 1, true) then vim.api.nvim_win_set_cursor(0, { i, 0 }); break end
    end
  ]]
  keys 'ga'
  wait_for(
    [[return not table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(review_tree),0,-1,false),'\n'):find('second.lua',1,true)]],
    'File acceptance must remove it from checklist'
  )
  exec [[
    assert(vim.fn.readfile('second.lua')[1] == "return 'changed second'", 'Accept must retain saved changes')
    require('codecompanion.interactions.code_review.window').close()
    vim.api.nvim_set_current_win(fixture_chat_win)
    chat:add_buf_message({ role = 'user', content = 'Please action #{code_review}\nFOLLOWUP_FIXTURE' })
    chat:submit()
  ]]
  wait_for(
    [[return chat.current_request == nil and vim.fn.readfile('first.lua')[1] == "return 'followup'"]],
    'Feedback must produce a further edit'
  )
  exec [[
    assert(#require('codecompanion.interactions.code_review').pending() == 0, 'Sending feedback must consume comments')
    controls.review()
    local text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
    assert(text:find('first.lua', 1, true) and not text:find('second.lua', 1, true),
      'Next review round must show only followup edits: ' .. text .. '; ' .. table.concat(fixture_notices, '; '))
    require('codecompanion.interactions.code_review.window').close()
    vim.api.nvim_set_current_win(fixture_chat_win)
    chat:add_buf_message({ role = 'user', content = 'HOLD_FIXTURE' })
    chat:submit()
  ]]
  wait_for('return chat.current_request ~= nil', 'Hold request must start')
  exec [[
    local request = chat.current_request
    vim.api.nvim_set_current_win(fixture_editor)
    local lines = vim.api.nvim_buf_get_lines(chat.bufnr, 0, -1, false)
    controls.write()
    assert(chat.current_request == request, 'Focus must not cancel or replace a request')
    assert(vim.deep_equal(lines, vim.api.nvim_buf_get_lines(chat.bufnr, 0, -1, false)),
      'Writing during streaming must not corrupt the unified chat')
    controls.stop()
  ]]
  wait_for(
    'return chat.current_request == nil and vim.bo[chat.bufnr].modifiable',
    'Native stop must return chat to editable input'
  )
  exec [[
    local confirm = require('codecompanion.interactions.chat.acp.request_permission').confirm
    local function approved(kind, input)
      local choice
      confirm(chat, {
        id = 'fixture',
        tool_call = { kind = kind, title = 'Fixture', rawInput = input or {} },
        options = {
          { kind = 'allow_once', optionId = 'allow', name = 'Allow' },
          { kind = 'reject_once', optionId = 'reject', name = 'Reject' },
        },
        respond = function(value) choice = value end,
      })
      return choice
    end
    for _, kind in ipairs({ 'read', 'search', 'edit', 'fetch' }) do
      assert(approved(kind) == 'allow', kind .. ' should be automatic in Auto mode')
    end
    assert(approved('execute', { command = 'git status --short' }) == 'allow', 'Safe commands should be automatic')
    assert(approved('execute', { command = 'git --no-pager status -sb' }) == 'allow',
      'Status must remain automatic with a leading --no-pager option')
    assert(approved('execute', { command = 'git --no-pager status -sb | head' }) == nil,
      'Status pipelines must still ask')
    assert(approved('execute', { command = 'cd /tmp && git --no-pager status -sb' }) == nil,
      'Directory-changing command chains must still ask')
    assert(approved('execute', { command = 'git status; git commit -am fixture' }) == nil,
      'Command chains must ask, not auto-approve')
    assert(approved('execute', { command = 'git push' }) == nil, 'Push must ask')
    assert(approved('execute', { command = 'git commit -am fixture' }) == nil, 'Commit must ask')
    assert(approved('other', { tool = 'figma_write_fixture' }) == nil, 'Unknown MCP mutations must ask')
    chat:stop()
    assert(fixture_git('rev-parse', 'HEAD') == fixture_head and fixture_git('write-tree') == fixture_index,
      'Review must not commit or change staging')
    _G.fixture_sources = require('blink.cmp.sources.lib').get_enabled_provider_ids('default')
    assert(vim.tbl_contains(fixture_sources, 'codecompanion'), 'Chat must use native Blink source')
    chat:close()
  ]]
  exec [[
    vim.api.nvim_set_current_win(fixture_editor)
    vim.cmd.enew()
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'CompletionFixtureWord', 'CompletionFix' })
    vim.api.nvim_win_set_cursor(0, { 2, 13 })
  ]]
  keys 'A<C-Space>'
  wait_for('return require("blink.cmp").is_visible()', 'Ordinary code must have a Blink completion menu')
  keys '<C-y>'
  wait_for(
    [[return vim.api.nvim_get_current_line() == 'CompletionFixtureWord']],
    'Ctrl+y must accept ordinary code completion'
  )
  keys '<Esc>'
  exec [[
    vim.bo.modified = false
    _G.long_chat = controls.new_chat()
    _G.chat = long_chat
    local lines = { '# Rendered heading', '' }
    for _ = 1, 300 do
      vim.list_extend(lines, { '## Earlier response', '', 'Some **Markdown** context.', '', '```lua', 'return true', '```', '' })
    end
    vim.list_extend(lines, { '## Me', '', '' })
    vim.api.nvim_buf_set_lines(chat.bufnr, 0, -1, false, lines)
    vim.api.nvim_win_set_cursor(0, { #lines, 0 })
    vim.cmd 'redraw!'
  ]]
  wait_for(
    [[return #vim.api.nvim_buf_get_extmarks(chat.bufnr,require('render-markdown.core.ui').ns,0,-1,{}) > 0]],
    'CodeCompanion Markdown decorations must actually render'
  )
  keys 'G$a'
  wait_for('return vim.fn.mode() == "i"', 'Long chat must enter Insert mode')
  local started = vim.uv.hrtime()
  keys 'x'
  wait_for([[return vim.api.nvim_get_current_line() == 'x']], 'First keystroke must appear without a second key')
  local elapsed_ms = (vim.uv.hrtime() - started) / 1e6
  assert(elapsed_ms < 500, 'First key in a long rendered chat took ' .. elapsed_ms .. 'ms')
  keys '<BS>#'
  wait_for([[return vim.api.nvim_get_current_line() == '#']], 'Chat context trigger must reach the draft')
  keys '<C-Space>'
  wait_for(
    [[
      local cmp = require 'blink.cmp'
      local context, item = cmp.get_context(), cmp.get_selected_item()
      return cmp.is_visible() and context and context.line == '#' and #cmp.get_items() > 2
        and item and item.source_id == 'codecompanion'
    ]],
    'Chat must show native context entries for the current trigger, not an earlier completion'
  )
  local selected = exec 'return require("blink.cmp").get_selected_item_idx()'
  keys '<C-k>'
  wait_for(
    'return require("blink.cmp").is_visible() and require("blink.cmp").get_selected_item_idx() > ' .. tostring(selected),
    'Ctrl+k must advance the menu'
  )
  keys '<C-l>'
  wait_for(
    'return require("blink.cmp").get_selected_item_idx() == ' .. tostring(selected),
    'Ctrl+l must restore menu selection'
  )
  keys '<C-y>'
  wait_for(
    [[return vim.api.nvim_get_current_line():find('#{',1,true) ~= nil]],
    'Ctrl+y must insert real chat context completion'
  )
  keys '<Esc>'
  exec [[
    vim.api.nvim_win_set_cursor(0, { 5, 0 })
  ]]
  keys 'k'
  wait_for('return vim.api.nvim_win_get_cursor(0)[1] == 6', 'Home-row k must move down in chat')
  keys 'l'
  wait_for('return vim.api.nvim_win_get_cursor(0)[1] == 5', 'Home-row l must move up in chat')
  exec [[
    vim.api.nvim_set_current_win(fixture_editor)
    vim.cmd.enew()
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { '# Ordinary Markdown', '', '**Still rendered**', '', 'Cursor' })
    vim.bo.filetype = 'markdown'
    vim.api.nvim_win_set_cursor(0, { 5, 0 })
    vim.cmd 'redraw!'
  ]]
  wait_for(
    [[return #vim.api.nvim_buf_get_extmarks(0,require('render-markdown.core.ui').ns,0,-1,{}) > 0]],
    'Ordinary Markdown rendering must remain enabled'
  )
  exec [[
    chat:close()
    vim.bo.modified = false
    _G.saved_select = vim.ui.select
    _G.resume_picker = false
    vim.ui.select = function(items, opts, callback)
      assert(opts.prompt == 'Resume Session', 'History shortcut must use native ACP resume')
      resume_picker = true
      callback(items[1], 1)
    end
    controls.resume()
  ]]
  wait_for('return resume_picker', 'History shortcut must wait for ACP initialization, then show sessions')
  wait_for(
    [[return table.concat(vim.api.nvim_buf_get_lines(controls.current_chat().bufnr,0,-1,false),'\n'):find('Resumed fixture history',1,true) ~= nil]],
    'Native ACP resume must restore history into the new chat'
  )
  exec [[
    vim.ui.select = saved_select
    controls.current_chat():close()
    vim.api.nvim_set_current_win(fixture_editor)
    vim.cmd 'term'
    local terminal_buf = vim.api.nvim_get_current_buf()
    controls.write(true)
    _G.chat = controls.current_chat()
    assert(chat.buffer_context.buftype == '' and not chat.buffer_context.path:find('term://',1,true),
      'Terminal launch must use a real editable file pane')
    vim.api.nvim_buf_delete(terminal_buf, { force = true })
    local png = vim.base64.decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==')
    local path = vim.fn.getcwd() .. '/.git/input.png'
    local file = assert(vim.uv.fs_open(path, 'w', 384))
    assert(vim.uv.fs_write(file, png))
    assert(vim.uv.fs_close(file))
    local images = require 'img-clip'
    assert(images.paste_image({}, path), 'Image plugin must paste an actual file in chat')
    chat:add_buf_message { role = 'user', content = '\nIMAGE_FIXTURE' }
    chat:submit()
  ]]
  wait_for(
    [[return chat.current_request == nil and table.concat(vim.api.nvim_buf_get_lines(chat.bufnr,0,-1,false),'\n'):find('Fixture image received',1,true) ~= nil]],
    'Pasted image must be sent as an ACP image block, not just a text path'
  )
  exec [[
    chat:close()
    vim.api.nvim_set_current_win(require('marten.core.windows').ensure_file_window())
    vim.cmd.edit('first.lua')
    vim.cmd.vsplit()
    vim.cmd.enew()
    local tree_buf = vim.api.nvim_get_current_buf()
    vim.bo.buftype, vim.bo.filetype = 'nofile', 'NvimTree'
    controls.write(true)
    _G.tree_chat = controls.current_chat()
    assert(tree_chat.buffer_context.buftype == '' and tree_chat.buffer_context.filetype ~= 'NvimTree',
      'Tree launch must use an editable file, not sidebar text')
    vim.api.nvim_buf_delete(tree_buf, { force = true })
  ]]
  wait_for('return tree_chat.acp_connection and tree_chat.acp_connection.session_id ~= nil', 'Tree chat must connect')
  exec [[
    _G.closed_agent_pid = tree_chat.acp_connection._state.handle.pid
    tree_chat:close()
  ]]
  wait_for('return vim.uv.kill(closed_agent_pid, 0) == nil', 'Closing the chat must stop its ACP process')
  assert(exec 'return #fixture_errors == 0', exec 'return table.concat(fixture_errors, "\\n")')
end

local ok, err = xpcall(run, debug.traceback)
vim.fn.jobstop(child)
vim.fn.delete(artifacts, 'rf')
assert(ok, err)
print 'CodeCompanion ACP, chat, selection, layout, review, permissions and cancellation regressions passed'

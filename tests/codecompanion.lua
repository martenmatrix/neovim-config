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
    _G.fixture_root = directory
    vim.fn.writefile({ "return 'first'" }, 'first.lua')
    vim.fn.writefile({ "return 'second'" }, 'second.lua')
    local function git(...)
      local result = vim.system({ 'git', ... }, { cwd = directory, text = true }):wait()
      assert(result.code == 0, result.stderr)
      return vim.trim(result.stdout)
    end
    _G.fixture_git = git
    git('init', '-q')
    _G.definition_root = directory .. '/.git/definition-project'
    vim.fn.mkdir(definition_root, 'p')
    vim.fn.writefile({ "return 'definition target'" }, definition_root .. '/definition.lua')
    git('-C', definition_root, 'init', '-q')
    git('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.com', 'add', '.')
    git('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.com', 'commit', '-qm', 'chore(): fixture')
    _G.fixture_head = git('rev-parse', 'HEAD')
    vim.fn.writefile({ 'staged work' }, 'existing.txt')
    git('add', 'existing.txt')
    vim.fn.writefile({ 'unstaged work' }, 'existing.txt')
    _G.fixture_index = git('write-tree')
    vim.cmd.edit('first.lua')
    _G.fixture_editor = vim.api.nvim_get_current_win()
    dofile(repo .. '/lua/marten/plugins/everforest.lua').config()
    local blink = dofile(repo .. '/lua/marten/plugins/lsp/blink-cmp.lua')
    require('blink.cmp').setup(blink.opts)
    local renderer = dofile(repo .. '/lua/marten/plugins/render-markdown.lua')
    require('render-markdown').setup(renderer.opts)
    vim.cmd.runtime('plugin/render-markdown.lua')
    local images = dofile(repo .. '/lua/marten/plugins/img-clip.lua')
    require('img-clip').setup(images.opts)
    for _, mapping in ipairs(images.keys) do
      vim.keymap.set(mapping.mode or 'n', mapping[1], mapping[2])
    end
    local spec = dofile(repo .. '/lua/marten/plugins/codecompanion.lua')
    spec.opts.adapters.acp.extend.copilot_acp.commands.default = { 'python3', repo .. '/tests/fixtures/codecompanion-acp.py' }
    spec.opts.interactions.code_review.opts = { storage_dir = directory .. '/.git/reviews' }
    spec.opts.display.action_palette = { provider = 'default' }
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
    [[return other.current_request == nil and table.concat(vim.api.nvim_buf_get_lines(other.bufnr,0,-1,false),'\n'):find('Fixture command approvals received',1,true) ~= nil]],
    'A new YOLO chat must approve ACP commands, pipelines and command chains without prompting'
  )
  exec [[
    other:close()
    vim.cmd 'tabclose!'
    vim.api.nvim_set_current_win(fixture_editor)
    controls.write()
    assert(controls.current_chat() == chat, 'Returning to a tab must restore its chat')
    require('codecompanion.interactions.chat.tools.approvals'):set_mode(chat.bufnr, { mode = 'yolo' })
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
    _G.review_baseline = require('codecompanion.interactions.code_review.baseline').get(fixture_root)
    _G.review_accepted = require('codecompanion.interactions.code_review.store').accepted(fixture_root)
    _G.assert_unreviewed = function()
      local baseline = require 'codecompanion.interactions.code_review.baseline'
      local store = require 'codecompanion.interactions.code_review.store'
      assert(baseline.get(fixture_root) == review_baseline, 'Navigation must not advance the review baseline')
      assert(#baseline.diff(fixture_root) == 2, 'Both edited files must remain pending after navigation')
      assert(vim.deep_equal(store.accepted(fixture_root), review_accepted), 'Navigation must not accept any hunks')
      assert(fixture_git('rev-parse', 'HEAD') == fixture_head, 'Navigation must not move branch HEAD')
      assert(fixture_git('write-tree') == fixture_index, 'Navigation must preserve the real staging index')
    end
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(review_tab)) do
      if win ~= review_tree then _G.review_pane = win end
    end
    local namespace = vim.api.nvim_create_namespace('codecompanion.code_review.window')
    local function accessible_review()
      local function blue(color)
        return color and color % 256 > math.floor(color / 256) % 256
          and math.floor(color / 256) % 256 > math.floor(color / 65536)
      end
      local function amber(color)
        return color and math.floor(color / 65536) > math.floor(color / 256) % 256
          and math.floor(color / 256) % 256 > color % 256
      end
      local seen = {}
      for _, win in ipairs({ review_tree, review_pane }) do
        for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(
          vim.api.nvim_win_get_buf(win), namespace, 0, -1, { details = true }
        )) do
          local group = mark[4].line_hl_group or mark[4].hl_group
          if group then
            seen[group] = vim.api.nvim_get_hl(0, { name = group, link = false })
          end
        end
      end
      assert(seen.CodeCompanionDiffAdd and blue(seen.CodeCompanionDiffAdd.bg),
        'Rendered review additions must have blue backgrounds')
      assert(seen.CodeCompanionDiffDelete and amber(seen.CodeCompanionDiffDelete.bg)
        and seen.CodeCompanionDiffDelete.underline, 'Rendered deletions must be amber and underlined')
      assert(seen.CodeCompanionCodeReviewAdded and blue(seen.CodeCompanionCodeReviewAdded.fg)
        and seen.CodeCompanionCodeReviewRemoved and amber(seen.CodeCompanionCodeReviewRemoved.fg),
        'Rendered checklist counts must use the same accessible diff colors')
      local added_word = vim.api.nvim_get_hl(0, { name = 'CodeCompanionDiffText', link = false })
      local removed_word = vim.api.nvim_get_hl(0, { name = 'CodeCompanionDiffTextDelete', link = false })
      assert(blue(added_word.bg) and amber(removed_word.bg) and removed_word.underline,
        'Word changes must distinguish additions and deletions without red/green')
      assert(blue(vim.api.nvim_get_hl(0, { name = 'GitSignsAdd', link = false }).fg)
        and amber(vim.api.nvim_get_hl(0, { name = 'GitSignsDelete', link = false }).fg),
        'Git signs must use the same accessible diff colors')
    end
    accessible_review()
    local background = vim.o.background
    for _, value in ipairs({ 'light', 'dark', background }) do
      vim.o.background = value
      vim.cmd.colorscheme('everforest')
      accessible_review()
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
    vim.lsp.buf.definition = function()
      _G.definition_source = {
        win = vim.api.nvim_get_current_win(),
        path = vim.fn.expand('%:t'),
        buftype = vim.bo.buftype,
        chat_buf = vim.api.nvim_win_get_buf(fixture_chat_win),
        cursor = vim.api.nvim_win_get_cursor(0),
      }
      navigation.definition = vim.lsp.util.show_document({
        uri = vim.uri_from_fname(definition_root .. '/definition.lua'),
        range = { start = { line = 0, character = 0 }, ['end'] = { line = 0, character = 0 } },
      }, 'utf-8', { focus = true })
      vim.cmd.lcd(definition_root)
    end
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
  ]]
  keys '09;gd'
  wait_for('return navigation.definition', 'Definition shortcut must jump to its target')
  exec [[
    assert(navigation.definition, 'Definition must resolve from the real source position')
    assert(definition_source.win == fixture_editor and definition_source.path == 'first.lua'
      and definition_source.buftype == '' and definition_source.chat_buf == fixture_chat_buf
      and vim.deep_equal(definition_source.cursor, { 1, 9 }), 'Definition must navigate from the real source position')
    assert(vim.fn.expand('%:t') == 'definition.lua', 'Definition must actually jump to another file')
    assert_unreviewed()
  ]]
  wait_for('return vim.fn.mode() == "n"', 'LSP navigation must leave the source in Normal mode')
  exec [[
    vim.diagnostic.set(vim.api.nvim_create_namespace('review-navigation-fixture'), vim.fn.bufnr('first.lua'), {
      { lnum = 0, col = 0, severity = vim.diagnostic.severity.ERROR, message = 'Fixture diagnostic' },
    })
  ]]
  keys ' ar'
  wait_for(
    [[return vim.api.nvim_get_current_tabpage() == review_tab]],
    'Space ar must return to the review after a definition jump'
  )
  exec [[
    vim.api.nvim_win_call(fixture_editor, function()
      vim.cmd.lcd(fixture_root)
    end)
    vim.api.nvim_set_current_win(fixture_chat_win)
    controls.review()
    assert_unreviewed()
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
    assert_unreviewed()
  ]]
  keys ' arc'
  wait_for(
    [[return vim.api.nvim_get_current_tabpage() == review_tab]],
    'Space arc must reopen the current pending review'
  )
  exec [[
    assert_unreviewed()
    assert(table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(review_tree), 0, -1, false), '\n')
      :find('first.lua', 1, true), 'Returning from navigation must keep the changed files visible')
    require('codecompanion.interactions.code_review.window').close()
    controls.review()
    assert(vim.bo.filetype == 'codecompanion_code_review', 'Closing and reopening must retain pending review hunks')
    _G.review_tab = vim.api.nvim_get_current_tabpage()
    _G.review_tree = vim.api.nvim_get_current_win()
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(review_tab)) do
      if win ~= review_tree then _G.review_pane = win end
    end
    assert_unreviewed()
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
    fixture_git('branch', 'fixture-base', fixture_head)
    fixture_git('config', 'init.defaultBranch', 'fixture-base')
    vim.api.nvim_set_current_win(fixture_editor)
  ]]
  keys '<Esc> arb'
  wait_for([[return vim.bo.filetype == 'codecompanion_code_review']], 'Space arb must open the native branch review')
  exec [[
    _G.branch_review_tab = vim.api.nvim_get_current_tabpage()
    _G.branch_review_tree = vim.api.nvim_get_current_win()
    local text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
    assert(text:find('first.lua', 1, true) and text:find('second.lua', 1, true)
      and text:find('existing.txt', 1, true), 'Branch review must include changes outside the latest agent round')
    assert(require('codecompanion.interactions.code_review.baseline').get(fixture_root) == fixture_head,
      'Branch review must use the branch fork point')
    assert(fixture_git('rev-parse', 'HEAD') == fixture_head and fixture_git('write-tree') == fixture_index,
      'Branch review must not alter branch HEAD or staged work')
    vim.api.nvim_set_current_win(fixture_editor)
  ]]
  keys ' arc'
  wait_for(
    [[return vim.api.nvim_get_current_tabpage() == branch_review_tab]],
    'Space arc must focus the current pending review without resetting it'
  )
  exec [[
    assert(table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(branch_review_tree), 0, -1, false), '\n')
      :find('existing.txt', 1, true), 'Returning to the branch review must not discard pending changes')
    require('codecompanion.interactions.code_review.window').close()
    vim.api.nvim_set_current_win(fixture_chat_win)
  ]]
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
      assert(approved(kind) == 'allow', kind .. ' should be automatic in YOLO mode')
    end
    for _, command in ipairs({
      'printf full-auto-fixture',
      'git --no-pager status -sb | head',
      'cd /tmp && git --no-pager status -sb',
      'git status; git commit -am fixture',
      'git push',
    }) do
      assert(approved('execute', { command = command }) == 'allow', 'YOLO must approve without a command allowlist')
    end
    assert(approved('other', { tool = 'figma_write_fixture' }) == 'allow', 'YOLO must also approve MCP operations')
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
    cc.restore(chat.bufnr)
    _G.saved_select = vim.ui.select
    _G.palette_history = vim.api.nvim_buf_get_lines(chat.bufnr, 0, -1, false)
    _G.actions_opened = false
    _G.open_chat_selected = false
    vim.ui.select = function(items, opts, callback)
      for _, item in ipairs(items) do
        if opts.prompt == 'Select a chat' and item.bufnr == chat.bufnr then
          open_chat_selected = true
          callback(item)
          return
        elseif item.name and item.name:find('Open chats', 1, true) then
          actions_opened = true
          callback(item)
          return
        end
      end
      callback(nil)
    end
  ]]
  keys '<Esc> fa'
  wait_for('return actions_opened and open_chat_selected', 'Actions shortcut must offer open chats even inside chat')
  exec [[
    assert(vim.api.nvim_get_current_buf() == chat.bufnr, 'Open chats must restore the existing chat buffer')
    assert(vim.deep_equal(palette_history, vim.api.nvim_buf_get_lines(chat.bufnr, 0, -1, false)),
      'Switching through actions must preserve the conversation and draft')
    vim.ui.select = saved_select
    chat:close()
    vim.bo.modified = false
    _G.saved_select = vim.ui.select
    _G.resume_picker = false
    vim.ui.select = function(items, opts, callback)
      assert(opts.prompt == 'Resume Session', 'History shortcut must use native ACP resume')
      resume_picker = true
      callback(items[1], 1)
    end
  ]]
  keys ' ah'
  wait_for('return resume_picker', 'History shortcut must wait for ACP initialization, then show sessions')
  wait_for(
    [[return table.concat(vim.api.nvim_buf_get_lines(controls.current_chat().bufnr,0,-1,false),'\n'):find('Resumed fixture history',1,true) ~= nil]],
    'Native ACP resume must restore history into the new chat'
  )
  exec [[
    controls.current_chat():close()
    _G.saved_new_chat = controls.new_chat
    _G.resume_picker = false
    controls.new_chat = function()
      local fresh = saved_new_chat()
      _G.history_already_connected = vim.wait(5000, function()
        return fresh.acp_connection and fresh.acp_connection.session_id ~= nil
      end, 10)
      return fresh
    end
    controls.resume()
    controls.new_chat = saved_new_chat
    assert(history_already_connected, 'History regression must start with an initialized ACP session')
  ]]
  wait_for('return resume_picker', 'History must also open when ACP initializes before the shortcut subscribes')
  wait_for(
    [[return table.concat(vim.api.nvim_buf_get_lines(controls.current_chat().bufnr,0,-1,false),'\n'):find('Resumed fixture history',1,true) ~= nil]],
    'Already-initialized history must restore the selected session'
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
    local clipboard = require 'img-clip.clipboard'
    _G.saved_clipboard = {
      get_clip_cmd = clipboard.get_clip_cmd,
      content_is_image = clipboard.content_is_image,
      save_image = clipboard.save_image,
    }
    clipboard.get_clip_cmd = function() return 'fixture' end
    clipboard.content_is_image = function() return true end
    clipboard.save_image = function(target)
      _G.clipboard_image_saved = vim.uv.fs_copyfile(path, target) == true
      return clipboard_image_saved
    end
    chat:add_buf_message { role = 'user', content = 'IMAGE_FIXTURE' }
  ]]
  keys '<Esc> ip'
  wait_for(
    [[return clipboard_image_saved and table.concat(vim.api.nvim_buf_get_lines(chat.bufnr,0,-1,false),'\n'):find('[Image](',1,true) ~= nil]],
    'Space ip must paste a clipboard image into the chat'
  )
  exec [[
    for name, callback in pairs(saved_clipboard) do
      require('img-clip.clipboard')[name] = callback
    end
    assert(table.concat(vim.api.nvim_buf_get_lines(chat.bufnr,0,-1,false),'\n'):find('IMAGE_FIXTURE',1,true),
      'Pasting an image must preserve the existing draft')
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
  exec(
    [[
    local directory = ...
    local root = directory .. '/.git/branch-review'
    vim.fn.mkdir(root .. '/dependency', 'p')
    local function git(...)
      local result = vim.system({ 'git', '-C', root, ... }, { text = true }):wait()
      assert(result.code == 0, result.stderr)
      return vim.trim(result.stdout)
    end
    local function module_git(...)
      return git('-C', root .. '/dependency', ...)
    end
    git('init', '-q')
    module_git('init', '-q')
    vim.fn.writefile({ "return 'dependency'" }, root .. '/dependency/module.lua')
    module_git('add', '.')
    module_git('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.com',
      'commit', '-qm', 'chore(): dependency fixture')
    vim.fn.writefile({ "return 'original'" }, root .. '/main.lua')
    vim.fn.writefile({ 'original file' }, root .. '/replaced.txt')
    vim.fn.writefile({ 'deleted file' }, root .. '/deleted.txt')
    git('add', '.')
    git('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.com',
      'commit', '-qm', 'chore(): branch fixture')
    local head = git('rev-parse', 'HEAD')
    git('branch', 'fixture-base', head)
    git('config', 'init.defaultBranch', 'fixture-base')
    vim.fn.writefile({ "return 'updated dependency'" }, root .. '/dependency/module.lua')
    module_git('add', '.')
    module_git('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.com',
      'commit', '-qm', 'chore(): update dependency fixture')
    assert(vim.uv.fs_unlink(root .. '/replaced.txt'))
    vim.fn.mkdir(root .. '/replaced.txt')
    vim.fn.writefile({ "return 'nested'" }, root .. '/replaced.txt/nested.lua')
    assert(vim.uv.fs_unlink(root .. '/deleted.txt'))
    vim.fn.writefile({ "return 'staged'" }, root .. '/main.lua')
    git('add', 'main.lua')
    local index = git('write-tree')
    vim.fn.writefile({ "return 'working'" }, root .. '/main.lua')
    vim.api.nvim_set_current_win(require('marten.core.windows').ensure_file_window())
    vim.cmd.cd(root)
    vim.cmd.edit(root .. '/main.lua')
    vim.cmd.CodeCompanionCodeReview 'Branch'
    assert(vim.bo.filetype == 'codecompanion_code_review',
      'Branch review must open with changed gitlinks and files replaced by directories')
    local checklist = require 'codecompanion.interactions.code_review.checklist'
    local review = assert(checklist.build { root = root })
    assert(review.diffs['main.lua'] and review.diffs['main.lua'].to.lines[1] == "return 'working'",
      'Branch review must still read ordinary files from the worktree')
    assert(review.diffs['deleted.txt'] and #review.diffs['deleted.txt'].to.lines == 0
      and review.diffs['deleted.txt'].from.lines[1] == 'deleted file',
      'Branch review must retain deleted-file hunks')
    assert(review.diffs['replaced.txt'] and #review.diffs['replaced.txt'].to.lines == 0
      and review.diffs['replaced.txt'].from.lines[1] == 'original file',
      'A file replaced by a directory must remain reviewable as a deletion')
    assert(review.diffs['replaced.txt/nested.lua']
      and review.diffs['replaced.txt/nested.lua'].to.lines[1] == "return 'nested'",
      'Branch review must include files added inside a replacement directory')
    assert(not review.diffs.dependency, 'Gitlinks must not be read as text files')
    checklist.discard(review.diffs)
    assert(git('rev-parse', 'HEAD') == head and git('write-tree') == index,
      'Branch review with directories must preserve HEAD and the real staging index')
    require('codecompanion.interactions.code_review.window').close()
    vim.cmd.cd(directory)
  ]],
    artifacts
  )
  assert(exec 'return #fixture_errors == 0', exec 'return table.concat(fixture_errors, "\\n")')
end

local ok, err = xpcall(run, debug.traceback)
vim.fn.jobstop(child)
vim.fn.delete(artifacts, 'rf')
assert(ok, err)
print 'CodeCompanion ACP, chat, selection, layout, review, permissions and cancellation regressions passed'

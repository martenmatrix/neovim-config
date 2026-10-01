local child = vim.fn.jobstart({ vim.v.progpath, '--embed', '--headless', '-u', 'NONE', '-n' }, { rpc = true })
assert(child > 0, 'Could not start Neovim for layout tests')

local function exec(code, ...)
  return vim.rpcrequest(child, 'nvim_exec_lua', code, { ... })
end

local function settle()
  vim.wait(20, function()
    return false
  end)
end

local function command(cmd)
  local win = exec('vim.cmd(...); return vim.api.nvim_get_current_win()', cmd)
  settle()
  return win
end

local function focus(win)
  vim.rpcrequest(child, 'nvim_set_current_win', win)
end

local function current_win()
  return vim.rpcrequest(child, 'nvim_get_current_win')
end

local function close(win)
  vim.rpcrequest(child, 'nvim_win_close', win, true)
  settle()
end

local function open_terminal()
  local terminal = exec [[
    vim.fn.maparg('<leader>tT', 'n', false, true).callback()
    return {
      win = vim.api.nvim_get_current_win(),
      buf = vim.api.nvim_get_current_buf(),
      height = vim.api.nvim_win_get_height(0),
    }
  ]]
  settle()
  assert(current_win() == terminal.win, 'Opening a terminal must keep focus')
  return terminal
end

local function assert_equal(expected, actual, message)
  assert(
    vim.deep_equal(expected, actual),
    message .. '\nexpected: ' .. vim.inspect(expected) .. '\nactual: ' .. vim.inspect(actual)
  )
end

local function assert_terminal(terminal)
  local state = exec(
    [[
      local win, buf = ...
      return {
        height = vim.api.nvim_win_get_height(win),
        buf = vim.api.nvim_win_get_buf(win),
        job = vim.fn.jobwait({ vim.bo[buf].channel }, 0)[1],
      }
    ]],
    terminal.win,
    terminal.buf
  )
  assert_equal(terminal.height, state.height, 'Terminal height must stay unchanged')
  assert_equal(terminal.buf, state.buf, 'Terminal buffer must stay unchanged')
  assert_equal(-1, state.job, 'Terminal shell must still be running')
end

local function assert_file_column(terminal, editor)
  assert_terminal(terminal)
  local state = exec(
    [[
    local terminal, editor = ...
    return {
      terminal_pos = vim.api.nvim_win_get_position(terminal),
      editor_pos = vim.api.nvim_win_get_position(editor),
      terminal_width = vim.api.nvim_win_get_width(terminal),
      editor_width = vim.api.nvim_win_get_width(editor),
    }
  ]],
    terminal.win,
    editor
  )
  assert_equal(state.editor_pos[2], state.terminal_pos[2], 'Terminal must stay in the file column')
  assert_equal(state.editor_width, state.terminal_width, 'Terminal must match the file pane width')
  assert(state.terminal_pos[1] > state.editor_pos[1], 'Terminal must open below the file pane')
end

local function protect(win, filetype)
  exec(
    [[
    local win, filetype = ...
    local buf = vim.api.nvim_win_get_buf(win)
    vim.bo[buf].buftype = 'nofile'
    vim.bo[buf].filetype = filetype
    vim.wo[win].winfixbuf = true
    vim.wo[win].winfixwidth = true
    vim.wo[win].winfixheight = true
  ]],
    win,
    filetype
  )
end

local function run_tests()
  vim.rpcrequest(child, 'nvim_ui_attach', 160, 60, { rgb = true })
  exec(
    [[
    vim.opt.runtimepath:prepend(...)
    vim.o.shell = '/bin/sh'
    vim.o.splitright = true
    vim.o.splitbelow = true
    require 'marten.core.terminal'
  ]],
    vim.fn.getcwd()
  )

  local editor = current_win()
  local terminal = open_terminal()
  assert_equal(15, terminal.height, 'Terminal must open with the requested height')
  assert_file_column(terminal, editor)
  assert(exec('return vim.wo[...].winfixheight', terminal.win), 'Mapped terminal must keep its height')
  assert(not exec('return vim.wo[...].winfixwidth', terminal.win), 'Mapped terminal must not lock its width')
  assert(
    exec(
      [[
    return not vim.wo[...].number and not vim.wo[...].relativenumber
  ]],
      terminal.win
    ),
    'Terminal must hide line numbers'
  )
  assert(exec [[return vim.fn.maparg('<Esc><Esc>', 't') ~= '']], 'Terminal escape mapping must remain available')

  focus(editor)
  local left = command 'topleft 20vnew'
  protect(left, 'NvimTree')
  assert_file_column(terminal, editor)
  assert_equal(left, current_win(), 'Opening a sidebar must not lose focus')
  assert_equal(20, exec('return vim.api.nvim_win_get_width(...)', left), 'Sidebar width must stay unchanged')

  local right = command 'botright 20vnew'
  protect(right, 'Avante')
  assert_file_column(terminal, editor)
  assert_equal(right, current_win(), 'Opening a right sidebar must not lose focus')
  assert_equal(20, exec('return vim.api.nvim_win_get_width(...)', right), 'Right sidebar width must stay unchanged')
  local sidebar_terminal = open_terminal()
  assert_file_column(sidebar_terminal, editor)
  assert_equal(
    'Avante',
    exec('return vim.bo[vim.api.nvim_win_get_buf(...)].filetype', right),
    'Sidebar must not be replaced'
  )
  close(sidebar_terminal.win)

  focus(editor)
  command 'vsplit'
  assert_terminal(terminal)
  command 'split'
  assert_terminal(terminal)

  local layout = vim.rpcrequest(child, 'nvim_call_function', 'winlayout', {})
  local floating = exec [[
    return vim.api.nvim_open_win(vim.api.nvim_create_buf(false, true), true, {
      relative = 'editor', row = 1, col = 1, width = 20, height = 3,
    })
  ]]
  settle()
  assert_equal(
    layout,
    vim.rpcrequest(child, 'nvim_call_function', 'winlayout', {}),
    'Floating windows must not change the split layout'
  )
  assert_equal(floating, current_win(), 'Floating window must keep focus')
  close(floating)

  focus(editor)
  command 'tabnew'
  local other_editor = current_win()
  command 'vsplit'
  assert_equal(
    'row',
    vim.rpcrequest(child, 'nvim_call_function', 'winlayout', {})[1],
    'Tabs without a mapped terminal must keep their layout'
  )
  local other_column = current_win()
  local other_terminal = open_terminal()
  assert_file_column(other_terminal, other_column)
  focus(other_editor)
  local other_sidebar = command 'topleft 20vnew'
  protect(other_sidebar, 'NvimTree')
  assert_file_column(other_terminal, other_column)
  command 'tabprevious'
  assert_terminal(terminal)
  command 'tabnext'
  assert_file_column(other_terminal, other_column)
  command 'tabclose!'

  focus(editor)
  command 'split | term'
  local unrelated = current_win()
  assert(not exec('return vim.wo[...].winfixheight', unrelated), 'Other terminals must not inherit a height lock')
  assert(not exec('return vim.wo[...].winfixwidth', unrelated), 'Other terminals must not inherit a width lock')
  assert_terminal(terminal)
  close(unrelated)

  focus(terminal.win)
  command 'resize 12'
  terminal.height = 12
  local new_editor = command 'vnew'
  assert_terminal(terminal)
  assert_equal(new_editor, current_win(), 'Splitting from the terminal must keep new-window focus')

  focus(editor)
  local second = open_terminal()
  assert_file_column(second, editor)
  assert_terminal(terminal)
  focus(editor)
  local extra_sidebar = command 'topleft 10vnew'
  protect(extra_sidebar, 'fixture')
  assert_file_column(second, editor)
  assert_terminal(terminal)

  close(second.win)
  close(terminal.win)
  focus(editor)
  command 'vsplit'
  assert_equal(
    'row',
    vim.rpcrequest(child, 'nvim_call_function', 'winlayout', {})[1],
    'Closing mapped terminals must leave ordinary splits unchanged'
  )

  for _, case in ipairs { 'tree', 'sidebar', 'tree-sidebar' } do
    command 'tabnew'
    local original = current_win()
    protect(original, case == 'sidebar' and 'Avante' or 'NvimTree')
    local sidebar = original
    if case == 'tree-sidebar' then
      sidebar = command 'botright 48vnew'
      protect(sidebar, 'Avante')
    end
    local empty_terminal = open_terminal()
    local empty_editor = exec [[return require('marten.core.windows').ensure_file_window()]]
    assert_file_column(empty_terminal, empty_editor)
    assert_equal(
      '',
      exec('return vim.bo[vim.api.nvim_win_get_buf(...)].buftype', empty_editor),
      'An empty file pane must be created'
    )
    assert(not exec('return vim.wo[...].winfixbuf', empty_editor), 'New file pane must allow editing')
    local count = exec 'return #vim.api.nvim_tabpage_list_wins(0)'
    assert_equal(
      empty_editor,
      exec [[return require('marten.core.windows').ensure_file_window()]],
      'Existing empty pane must be reused'
    )
    assert_equal(count, exec 'return #vim.api.nvim_tabpage_list_wins(0)', 'Reusing a file pane must not create a split')
    local positions = exec(
      [[
      local original, editor, sidebar = ...
      return {
        original = vim.api.nvim_win_get_position(original)[2],
        editor = vim.api.nvim_win_get_position(editor)[2],
        sidebar = vim.api.nvim_win_get_position(sidebar)[2],
      }
    ]],
      original,
      empty_editor,
      sidebar
    )
    if case ~= 'sidebar' then
      assert(positions.original < positions.editor, 'Tree must stay left of the file pane')
    end
    if case ~= 'tree' then
      assert(positions.sidebar > positions.editor, 'Avante must stay right of the file pane')
    end
    command 'tabclose!'
  end
end

local ok, err = xpcall(run_tests, debug.traceback)
vim.fn.jobstop(child)
assert(ok, err)
print 'Terminal layout regression tests passed'

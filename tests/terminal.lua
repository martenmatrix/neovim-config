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

local function assert_docked(terminals)
  local layout = vim.rpcrequest(child, 'nvim_call_function', 'winlayout', {})
  assert_equal('col', layout[1], 'Terminal dock must be a full-width row')
  for i, terminal in ipairs(terminals) do
    assert_equal(
      { 'leaf', terminal.win },
      layout[2][#layout[2] - #terminals + i],
      'Terminals must stay at the bottom in opening order'
    )
    local state = exec(
      [[
      local win, buf = ...
      return {
        height = vim.api.nvim_win_get_height(win),
        width = vim.api.nvim_win_get_width(win),
        columns = vim.o.columns,
        col = vim.api.nvim_win_get_position(win)[2],
        buf = vim.api.nvim_win_get_buf(win),
        job = vim.fn.jobwait({ vim.bo[buf].channel }, 0)[1],
      }
    ]],
      terminal.win,
      terminal.buf
    )
    assert_equal(terminal.height, state.height, 'Terminal height must stay unchanged')
    assert_equal(state.columns, state.width, 'Terminal must span the full screen width')
    assert_equal(0, state.col, 'Terminal must stay at the left edge')
    assert_equal(terminal.buf, state.buf, 'Terminal buffer must stay unchanged')
    assert_equal(-1, state.job, 'Terminal shell must still be running')
  end
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
  assert_docked { terminal }
  assert(exec('return vim.wo[...].winfixheight', terminal.win), 'Docked terminal must keep its height')
  assert(not exec('return vim.wo[...].winfixwidth', terminal.win), 'Docked terminal must not lock its width')
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
  assert_docked { terminal }
  assert_equal(left, current_win(), 'Opening a sidebar must not lose focus')
  assert_equal(20, exec('return vim.api.nvim_win_get_width(...)', left), 'Sidebar width must stay unchanged')

  local right = command 'botright 20vnew'
  assert_docked { terminal }
  assert_equal(right, current_win(), 'Opening a right sidebar must not lose focus')
  assert_equal(20, exec('return vim.api.nvim_win_get_width(...)', right), 'Right sidebar width must stay unchanged')

  focus(editor)
  command 'vsplit'
  assert_docked { terminal }
  command 'split'
  assert_docked { terminal }
  command 'wincmd ='
  assert_docked { terminal }
  local quickfix = command 'botright copen'
  assert_docked { terminal }
  assert_equal(quickfix, current_win(), 'Quickfix window must keep focus')
  close(quickfix)

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
    'Floating windows must not change the dock'
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
    'Tabs without a dock must keep their layout'
  )
  local other_terminal = open_terminal()
  assert_docked { other_terminal }
  focus(other_editor)
  command 'topleft 20vnew'
  assert_docked { other_terminal }
  command 'tabprevious'
  assert_docked { terminal }
  command 'tabnext'
  assert_docked { other_terminal }
  command 'tabclose!'

  focus(editor)
  command 'split | term'
  local unrelated = current_win()
  assert(not exec('return vim.wo[...].winfixheight', unrelated), 'Other terminals must not inherit a height lock')
  assert(not exec('return vim.wo[...].winfixwidth', unrelated), 'Other terminals must not inherit a width lock')
  assert_docked { terminal }
  close(unrelated)

  focus(terminal.win)
  command 'resize 12'
  terminal.height = 12
  local new_editor = command 'vnew'
  assert_docked { terminal }
  assert_equal(new_editor, current_win(), 'Splitting from the terminal must keep new-window focus')

  focus(editor)
  local second = open_terminal()
  assert_docked { terminal, second }
  focus(editor)
  command 'topleft 10vnew'
  assert_docked { terminal, second }

  close(second.win)
  close(terminal.win)
  focus(editor)
  command 'vsplit'
  assert_equal(
    'row',
    vim.rpcrequest(child, 'nvim_call_function', 'winlayout', {})[1],
    'Closing managed terminals must stop docking'
  )
end

local ok, err = xpcall(run_tests, debug.traceback)
vim.fn.jobstop(child)
assert(ok, err)
print 'Terminal layout regression tests passed'

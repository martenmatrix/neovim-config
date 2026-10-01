vim.keymap.set('t', '<Esc><Esc>', [[<C-\><C-n>]], { desc = 'Exit terminal mode' })

local group = vim.api.nvim_create_augroup('custom-term-open', { clear = true })
local terminals = {}
local pending = false

local function restore_layout()
  local tab = vim.api.nvim_get_current_tabpage()
  local dock = {}
  for i = #terminals, 1, -1 do
    local terminal = terminals[i]
    if not vim.api.nvim_win_is_valid(terminal.win) or vim.api.nvim_win_get_buf(terminal.win) ~= terminal.buf then
      table.remove(terminals, i)
    elseif vim.api.nvim_win_get_tabpage(terminal.win) == tab then
      table.insert(dock, 1, terminal)
    end
  end

  if #dock == 0 then
    return
  end

  local layout = vim.fn.winlayout()
  if layout[1] == 'leaf' then
    return
  end
  local anchored = layout[1] == 'col'
  for i, terminal in ipairs(dock) do
    local child = layout[2][#layout[2] - #dock + i]
    anchored = anchored and child ~= nil and child[1] == 'leaf' and child[2] == terminal.win
  end
  if anchored then
    return
  end

  for _, terminal in ipairs(dock) do
    vim.api.nvim_win_call(terminal.win, function()
      vim.cmd 'noautocmd wincmd J'
    end)
  end
  for _, terminal in ipairs(dock) do
    vim.api.nvim_win_set_height(terminal.win, terminal.height)
  end
end

vim.api.nvim_create_autocmd({ 'WinNew', 'TabEnter' }, {
  group = group,
  callback = function()
    if pending then
      return
    end
    pending = true
    -- Let plugins finish creating their windows before repairing the split tree.
    vim.schedule(function()
      pending = false
      restore_layout()
    end)
  end,
})

vim.api.nvim_create_autocmd('WinResized', {
  group = group,
  callback = function()
    if pending then
      return
    end
    for _, terminal in ipairs(terminals) do
      if vim.api.nvim_win_is_valid(terminal.win) then
        terminal.height = vim.api.nvim_win_get_height(terminal.win)
      end
    end
  end,
})

vim.api.nvim_create_autocmd('TermOpen', {
  group = group,
  callback = function()
    vim.opt_local.number = false
    vim.opt_local.relativenumber = false
  end,
})

vim.keymap.set('n', '<leader>tT', function()
  vim.cmd 'botright 15split | term'
  vim.opt_local.winfixheight = true
  table.insert(terminals, {
    win = vim.api.nvim_get_current_win(),
    buf = vim.api.nvim_get_current_buf(),
    height = vim.api.nvim_win_get_height(0),
  })
end, { desc = 'Open terminal' })

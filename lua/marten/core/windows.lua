local M = {}

function M.ensure_file_window()
  local current = vim.api.nvim_get_current_win()
  local windows = { current }
  local tree_win
  vim.list_extend(windows, vim.api.nvim_tabpage_list_wins(0))
  for _, win in ipairs(windows) do
    local config = vim.api.nvim_win_get_config(win)
    local buf = vim.api.nvim_win_get_buf(win)
    if config.relative == '' and not config.external and vim.bo[buf].buftype == '' and not vim.wo[win].winfixbuf then
      return win
    end
    if config.relative == '' and not config.external and vim.bo[buf].filetype == 'NvimTree' then
      tree_win = win
    end
  end
  if tree_win then
    vim.api.nvim_set_current_win(tree_win)
    vim.cmd 'rightbelow vnew'
  else
    vim.cmd 'topleft vnew'
  end
  return vim.api.nvim_get_current_win()
end

return M

local M = {}

function M.setup(pending_files, restore)
  local Config = require 'avante.config'
  local Diff = require 'avante.diff'
  pending_files = pending_files or {}
  local restoring = false
  local review_group = vim.api.nvim_create_augroup('marten_avante_review', { clear = true })
  local function track(tabpage, bufnr)
    local files = pending_files[tabpage] or {}
    if not vim.tbl_contains(files, bufnr) then
      files[#files + 1] = bufnr
    end
    pending_files[tabpage] = files
  end
  local function marker_line(bufnr)
    if not vim.api.nvim_buf_is_loaded(bufnr) or vim.bo[bufnr].buftype ~= '' then
      return
    end
    for index, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
      if line:match '^<<<<<<<' or line:match '^=======$' or line:match '^>>>>>>>' then
        return index
      end
    end
  end
  local function review_list()
    local allowed, items, seen = {}, {}, {}
    for _, bufnr in ipairs(pending_files[vim.api.nvim_get_current_tabpage()] or {}) do
      allowed[bufnr] = true
    end
    Diff.conflicts_to_qf_items(function(native_items)
      for _, item in ipairs(native_items) do
        local bufnr = vim.fn.bufnr(item.filename)
        local line = allowed[bufnr] and marker_line(bufnr)
        if line and not seen[bufnr] then
          seen[bufnr] = true
          items[#items + 1] = { bufnr = bufnr, lnum = line, col = 1, text = 'Pending Avante changes' }
        end
      end
    end)
    -- Incomplete markers are not represented in Avante's parsed conflict inventory.
    for bufnr in pairs(allowed) do
      local line = not seen[bufnr] and marker_line(bufnr)
      if line then
        items[#items + 1] = { bufnr = bufnr, lnum = line, col = 1, text = 'Unparsed conflict markers remain' }
      end
    end
    table.sort(items, function(a, b)
      return vim.api.nvim_buf_get_name(a.bufnr) < vim.api.nvim_buf_get_name(b.bufnr)
    end)
    vim.fn.setqflist({}, ' ', { title = 'Avante pending files', items = items })
    if #items == 0 then
      vim.notify('No pending Avante conflict markers remain in this tab.', vim.log.levels.INFO, { title = 'Avante' })
    end
    return items
  end
  local function open_pending()
    if marker_line(vim.api.nvim_get_current_buf()) then
      vim.notify(
        'This file still has conflict markers; resolve them before moving to the next review file.',
        vim.log.levels.WARN,
        { title = 'Avante' }
      )
      return
    end
    if #review_list() > 0 then
      vim.api.nvim_set_current_win(require('marten.core.windows').ensure_file_window())
      vim.cmd.cfirst { mods = { hide = true } }
    end
  end
  vim.api.nvim_create_autocmd('User', {
    group = review_group,
    pattern = 'AvanteConflictDetected',
    callback = function(event)
      if restoring or Config.mode ~= 'legacy' or Diff.conflict_count(event.buf) == 0 then
        return
      end
      track(vim.api.nvim_get_current_tabpage(), event.buf)
    end,
  })
  vim.api.nvim_create_autocmd('TabClosed', {
    group = review_group,
    callback = function()
      for tabpage in pairs(pending_files) do
        if not vim.api.nvim_tabpage_is_valid(tabpage) then
          pending_files[tabpage] = nil
        end
      end
    end,
  })
  vim.api.nvim_create_user_command('AvanteReviewReload', function()
    dofile(vim.fn.stdpath 'config' .. '/lua/marten/core/avante-review.lua').setup(pending_files, true)
  end, { desc = 'Reload Avante review hooks and restore existing conflict controls', force = true })
  vim.api.nvim_create_user_command('AvanteReviewNext', open_pending, {
    desc = 'Open the next file with pending Avante review conflicts',
    force = true,
  })
  vim.api.nvim_create_user_command('AvanteReviewList', function()
    if #review_list() > 0 then
      vim.cmd.copen()
    end
  end, { desc = "List this tab's pending Avante files in native quickfix", force = true })
  vim.keymap.set('n', '<leader>a]', '<Cmd>AvanteReviewNext<CR>', { desc = 'avante: next pending review file' })
  vim.keymap.set('n', '<leader>aq', '<Cmd>AvanteReviewList<CR>', { desc = 'avante: pending review files' })

  if not restore then
    return
  end
  local candidates, owners = {}, {}
  for tabpage, files in pairs(pending_files) do
    if vim.api.nvim_tabpage_is_valid(tabpage) then
      for _, bufnr in ipairs(files) do
        candidates[bufnr] = true
        owners[bufnr] = tabpage
      end
    end
  end
  Diff.conflicts_to_qf_items(function(items)
    for _, item in ipairs(items) do
      local bufnr = vim.fn.bufnr(item.filename)
      if bufnr > 0 then
        candidates[bufnr] = true
      end
    end
  end)
  candidates[vim.api.nvim_get_current_buf()] = true
  local tabs = vim.api.nvim_list_tabpages()
  local restored, ambiguous, incomplete = 0, 0, 0
  restoring = true
  for bufnr in pairs(candidates) do
    if
      vim.api.nvim_buf_is_loaded(bufnr)
      and vim.bo[bufnr].buftype == ''
      and vim.iter(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)):any(function(line)
        return line:match '^<<<<<<<'
      end)
    then
      local owner = owners[bufnr]
      if not owner then
        for _, tabpage in ipairs(tabs) do
          for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
            if vim.api.nvim_win_get_buf(winid) == bufnr then
              owner = tabpage
              break
            end
          end
          if owner then
            break
          end
        end
      end
      if not owner and #tabs == 1 then
        owner = tabs[1]
      end
      if owner then
        vim.api.nvim_buf_call(bufnr, function()
          Diff.add_visited_buffer(bufnr)
          Diff.process(bufnr)
          track(owner, bufnr)
          if Diff.conflict_count(bufnr) > 0 then
            for _, lhs in pairs(Config.mappings.diff) do
              if vim.fn.maparg(lhs, 'n', false, true).buffer ~= 1 then
                -- Processing may skip unchanged buffers whose mappings were lost.
                vim.api.nvim_exec_autocmds('User', { pattern = 'AvanteConflictDetected' })
                break
              end
            end
            restored = restored + 1
          else
            incomplete = incomplete + 1
          end
        end)
      else
        ambiguous = ambiguous + 1
      end
    end
  end
  restoring = false
  vim.notify(
    ('Avante review reloaded: %d pending files; no edits applied or saved.'):format(restored),
    vim.log.levels.INFO,
    { title = 'Avante' }
  )
  if ambiguous > 0 then
    vim.notify(
      ('%d hidden review buffers have no known chat tab; open them in their review tab and run :AvanteReviewReload again.'):format(
        ambiguous
      ),
      vim.log.levels.WARN,
      { title = 'Avante' }
    )
  end
  if incomplete > 0 then
    vim.notify(
      ('%d files contain incomplete conflict markers; restore complete hunks with undo or review the markers manually.'):format(
        incomplete
      ),
      vim.log.levels.WARN,
      { title = 'Avante' }
    )
  end
end

return M

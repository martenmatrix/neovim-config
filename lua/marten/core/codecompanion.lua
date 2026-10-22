local M = {}

local function notify(message)
  vim.notify(message, vim.log.levels.INFO, { title = 'CodeCompanion' })
end

function M.current_chat()
  local cc = require 'codecompanion'
  return cc.buf_get_chat(0) or (vim.t.codecompanion_chat and cc.buf_get_chat(vim.t.codecompanion_chat))
end

function M.write(attach_file)
  local cc = require 'codecompanion'
  local chat = M.current_chat()
  local context = require('codecompanion.utils.context').get()
  if chat and chat.current_request then
    cc.restore(chat.bufnr)
    notify 'Request running. Space aS stops it before you write or attach more code.'
    return
  end
  if context.is_visual and context.buftype ~= '' then
    notify 'Select code in an editable file first.'
    return
  end
  if context.is_visual then
    vim.cmd.normal { args = { vim.api.nvim_replace_termcodes('<Esc>', true, false, true) }, bang = true }
  elseif context.buftype ~= '' and not cc.buf_get_chat(0) then
    vim.api.nvim_set_current_win(require('marten.core.windows').ensure_file_window())
    context = require('codecompanion.utils.context').get()
  end

  chat = chat or cc.chat { stop_context_insertion = true, context = context }
  if not chat then
    vim.notify('Could not create an ACP chat.', vim.log.levels.ERROR, { title = 'CodeCompanion' })
    return
  end
  if context.buftype == '' then
    chat.buffer_context = context
  end
  if context.is_visual then
    chat:add_buf_message {
      role = 'user',
      content = ('Selected code from %s (lines %d-%d):\n%s\n'):format(
        context.path,
        context.start_line,
        context.end_line,
        require('codecompanion.utils.markdown').form_codeblock(table.concat(context.lines, '\n'), {
          ft = context.filetype,
        })
      ),
    }
  elseif attach_file and context.buftype == '' and context.path ~= '' then
    local buffer = require('codecompanion.interactions.chat.helpers').format_buffer_for_llm(context.bufnr, context.path)
    chat:add_context(
      { content = buffer.content },
      'codecompanion.interactions.shared.editor_context.buffer',
      buffer.id,
      {
        bufnr = context.bufnr,
        path = context.path,
        context_opts = { sync_diff = true },
      }
    )
  end
  cc.restore(chat.bufnr)
  vim.cmd.normal { args = { 'G$' }, bang = true }
  vim.cmd.startinsert { bang = true }
end

function M.new_chat()
  vim.api.nvim_set_current_win(require('marten.core.windows').ensure_file_window())
  return require('codecompanion').chat { stop_context_insertion = true }
end

function M.toggle()
  local chat = M.current_chat()
  if chat and chat.ui:is_visible() then
    chat.ui:hide()
  else
    M.write()
  end
end

function M.switch()
  if require('codecompanion').buf_get_chat(0) then
    vim.api.nvim_set_current_win(require('marten.core.windows').ensure_file_window())
  else
    M.write()
  end
end

function M.stop()
  local chat = M.current_chat()
  if chat and chat.current_request then
    chat:stop()
  else
    notify 'No request is running in this tab.'
  end
end

function M.model()
  M.write()
  local chat = M.current_chat()
  if chat and not chat.current_request then
    vim.cmd.stopinsert()
    if not chat.acp_connection or not chat.acp_connection.session_id then
      notify 'Agent is still connecting. Try Space a? once connected.'
      return
    end
    require('codecompanion.interactions.chat.keymaps.change_adapter').select_model(chat)
  end
end

function M.resume()
  local chat = M.new_chat()
  if chat then
    local pending = vim.api.nvim_create_autocmd('User', {
      pattern = 'CodeCompanionACPSessionPost',
      callback = function(event)
        if chat.acp_connection and chat.acp_connection.session_id == event.data.session_id then
          if vim.api.nvim_get_current_buf() == chat.bufnr then
            require('codecompanion.interactions.chat.slash_commands').new():execute(
              { label = 'resume', config = require('codecompanion.config').interactions.chat.slash_commands.resume },
              chat
            )
          else
            notify 'Chat connected. Use /resume there before sending a message.'
          end
          return true
        end
      end,
    })
    vim.defer_fn(function()
      for _, autocmd in ipairs(vim.api.nvim_get_autocmds { event = 'User', pattern = 'CodeCompanionACPSessionPost' }) do
        if autocmd.id == pending then
          vim.api.nvim_del_autocmd(pending)
          if vim.api.nvim_buf_is_valid(chat.bufnr) then
            notify 'Session picker did not connect. Check :messages; use /resume in the fresh chat once connected.'
          end
        end
      end
    end, 30000)
  end
end

function M.review()
  local root = vim.fs.root(vim.fn.getcwd(), '.git')
  for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
      if
        vim.bo[vim.api.nvim_win_get_buf(win)].filetype == 'codecompanion_code_review'
        and vim.fs.root(vim.fn.getcwd(-1, vim.api.nvim_tabpage_get_number(tab)), '.git') == root
      then
        vim.api.nvim_set_current_win(win)
        return
      end
    end
  end
  vim.api.nvim_set_current_win(require('marten.core.windows').ensure_file_window())
  vim.cmd.CodeCompanionCodeReview()
end

function M.review_goto(method)
  local win = vim.api.nvim_get_current_win()
  if not vim.wo[win].statuscolumn:find('codecompanion.interactions.code_review.window', 1, true) then
    notify 'Focus the diff code pane to navigate a symbol.'
    return
  end
  local cursor = vim.api.nvim_win_get_cursor(win)
  local source_line = tonumber(vim.api.nvim_eval_statusline(vim.wo[win].statuscolumn, {
    winid = win,
    use_statuscol_lnum = cursor[1],
  }).str)
  if not source_line then
    notify 'Deleted lines have no location in the current source file.'
    return
  end
  local text = vim.api.nvim_get_current_line()
  -- Let the native review action resolve the source path and leave its scratch buffers intact.
  vim.fn.maparg('i', 'n', false, true).callback()
  vim.cmd.stopinsert()
  local source_win, source_buf = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
  if
    not vim.bo[source_buf].modified
    and not vim.deep_equal(
      vim.api.nvim_buf_get_lines(source_buf, 0, -1, false),
      vim.fn.readfile(vim.api.nvim_buf_get_name(source_buf))
    )
  then
    vim.api.nvim_buf_call(source_buf, function()
      vim.cmd 'silent edit!'
    end)
  end
  if vim.api.nvim_buf_get_lines(source_buf, source_line - 1, source_line, false)[1] ~= text then
    notify 'The source changed since this review was drawn. Refresh the review before navigating.'
    return
  end
  vim.api.nvim_win_set_cursor(source_win, { source_line, cursor[2] })
  local position = vim.api.nvim_win_get_cursor(source_win)
  local function at_source()
    return vim.api.nvim_get_current_win() == source_win
      and vim.api.nvim_get_current_buf() == source_buf
      and vim.deep_equal(vim.api.nvim_win_get_cursor(source_win), position)
  end
  local lsp_method = 'textDocument/' .. method
  if #vim.lsp.get_clients { bufnr = source_buf, method = lsp_method } > 0 then
    vim.lsp.buf[method]()
    return
  end
  local pending
  pending = vim.api.nvim_create_autocmd('LspAttach', {
    buffer = source_buf,
    callback = function()
      if #vim.lsp.get_clients { bufnr = source_buf, method = lsp_method } == 0 then
        return
      end
      if at_source() then
        vim.lsp.buf[method]()
      end
      pending = nil
      return true
    end,
  })
  vim.defer_fn(function()
    if pending and vim.api.nvim_buf_is_valid(source_buf) then
      vim.api.nvim_del_autocmd(pending)
      if at_source() then
        notify 'No attached language server supports this navigation.'
      end
    end
  end, 5000)
end

function M.setup()
  local group = vim.api.nvim_create_augroup('marten_codecompanion', { clear = true })
  vim.api.nvim_create_autocmd('User', {
    group = group,
    pattern = 'CodeCompanionChatCreated',
    callback = function(event)
      local chat = require('codecompanion').buf_get_chat(event.data.bufnr)
      chat:add_callback('on_before_submit', function()
        local baseline = require 'codecompanion.interactions.code_review.baseline'
        local store = require 'codecompanion.interactions.code_review.store'
        local root = baseline.get_root()
        if not root or store.round_open(root) or #store.comments(root) > 0 then
          return
        end
        -- The native submitted event fires after ACP dispatch, which can miss fast edits.
        if not baseline.snapshot(root) then
          vim.notify('Could not snapshot the worktree for review.', vim.log.levels.ERROR, { title = 'CodeCompanion' })
          return false
        end
        store.begin_round(root)
      end)
      chat:add_callback('on_submitted', function()
        local baseline = require 'codecompanion.interactions.code_review.baseline'
        local root = baseline.get_root()
        -- Parsing review feedback closes its round before ACP dispatch.
        if root and baseline.get(root) then
          require('codecompanion.interactions.code_review.store').begin_round(root)
        end
      end)
    end,
  })
  vim.api.nvim_create_autocmd('User', {
    group = group,
    pattern = 'CodeCompanionChatOpened',
    callback = function(event)
      vim.t.codecompanion_chat = event.data.bufnr
    end,
  })
  vim.api.nvim_create_autocmd('FileType', {
    group = group,
    pattern = { 'codecompanion', 'codecompanion_code_review' },
    callback = function(event)
      for lhs, mapping in pairs(require 'marten.core.navigation') do
        vim.keymap.set('n', lhs, mapping.rhs, { buffer = event.buf, expr = mapping.expr, desc = mapping.desc })
      end
    end,
  })
end

return M

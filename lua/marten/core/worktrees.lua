local M = {}
local creating = {}
local chats = {}

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.ERROR, { title = 'AI worktrees' })
end

local function git(root, args)
  local result = vim.system(vim.list_extend({ 'git', '-C', root }, args), { text = true }):wait()
  if result.code ~= 0 then
    notify(vim.trim(result.stderr))
    return
  end
  return vim.trim(result.stdout)
end

local function root()
  local directory = vim.t.ai_worktree or vim.fs.root(vim.fn.getcwd(), '.git')
  if not directory then
    notify 'Open a Git project before creating or selecting a worktree.'
    return
  end
  return vim.uv.fs_realpath(directory) or directory
end

local function source_file(directory)
  local buffers = { vim.api.nvim_get_current_buf() }
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    table.insert(buffers, vim.api.nvim_win_get_buf(win))
  end
  for _, buffer in ipairs(buffers) do
    local path = vim.api.nvim_buf_get_name(buffer)
    if vim.bo[buffer].buftype == '' and path:sub(1, #directory + 1) == directory .. '/' then
      return path:sub(#directory + 2)
    end
  end
end

function M.open(path, file)
  path = vim.uv.fs_realpath(path)
  if not path or vim.fs.root(path, '.git') ~= path then
    notify 'The selected worktree is missing or is not a Git checkout.'
    return
  end
  local controls = require 'marten.core.codecompanion'
  local cc = require 'codecompanion'
  local destination
  for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
    local owner = vim.t[tab].ai_worktree
    if
      owner == path
      or (not owner and vim.uv.fs_realpath(vim.fn.getcwd(-1, vim.api.nvim_tabpage_get_number(tab))) == path)
    then
      destination = tab
      break
    end
  end
  if destination then
    vim.api.nvim_set_current_tabpage(destination)
  else
    vim.cmd.tabnew()
    vim.cmd.tcd(vim.fn.fnameescape(path))
    vim.t.ai_worktree = path
    if file and vim.fn.filereadable(path .. '/' .. file) == 1 then
      vim.cmd.edit(vim.fn.fnameescape(path .. '/' .. file))
    end
    vim.b.ai_worktree = path
  end
  vim.cmd.tcd(vim.fn.fnameescape(path))
  local existing = chats[path] and cc.buf_get_chat(chats[path])
  if existing then
    cc.restore(existing.bufnr)
  end
  controls.write()
  local chat = controls.current_chat()
  if chat then
    chats[path] = chat.bufnr
    vim.b[chat.bufnr].ai_worktree = path
  end
end

function M.new()
  local directory = root()
  if not directory then
    return
  end
  local info = git(directory, { 'rev-parse', '--path-format=absolute', '--git-common-dir', 'HEAD' })
  if not info then
    return
  end
  local common, base = info:match '^(.-)\n([%x]+)$'
  if not common then
    notify 'Could not determine the repository and starting commit.'
    return
  end
  local name =
    vim.fs.basename(vim.fs.basename(common) == '.git' and vim.fs.dirname(common) or common):gsub('%.git$', '')
  local parent = vim.fn.stdpath 'data'
    .. '/worktrees/'
    .. name:gsub('[^%w._-]', '-')
    .. '-'
    .. vim.fn.sha256(common):sub(1, 8)
  local file = source_file(directory)
  vim.ui.input({ prompt = 'New AI task (from HEAD; uncommitted edits stay here): ' }, function(task)
    if not task or task == '' then
      return
    end
    if not task:match '^[%w][%w_-]*$' then
      notify 'Use a task name containing letters, numbers, hyphens, or underscores.'
      return
    end
    local path = parent .. '/' .. task
    if creating[path] or vim.uv.fs_stat(path) then
      notify 'That task directory already exists or is being created. Space ww opens existing worktrees.'
      return
    end
    vim.fn.mkdir(parent, 'p')
    -- Use the manager's job without its asynchronous cwd-changing create/switch chain.
    local job = require('git-worktree.git').create_worktree_job(path, 'ai/' .. task, false, nil, false)
    job.args = vim.list_extend({ '-C', directory }, job.args)
    table.insert(job.args, base)
    creating[path] = true
    job:after(vim.schedule_wrap(function(completed, code)
      creating[path] = nil
      if code ~= 0 then
        notify(table.concat(completed:stderr_result(), '\n'))
        return
      end
      M.open(path, file)
    end))
    job:start()
  end)
end

function M.pick()
  local directory = root()
  if not directory then
    return
  end
  local result = vim
    .system({ 'git', '-C', directory, 'worktree', 'list', '--porcelain', '-z' }, { text = false })
    :wait()
  if result.code ~= 0 then
    notify(vim.trim(result.stderr))
    return
  end
  local entries = {}
  for record in result.stdout:gmatch '(.-)%z%z' do
    local path = record:match '^worktree ([^%z]+)'
    if path and not record:find('\0bare', 1, true) then
      table.insert(entries, {
        path = path,
        branch = record:match '%zbranch refs/heads/([^%z]+)' or '(detached)',
      })
    end
  end
  local file = source_file(directory)
  local actions = require 'telescope.actions'
  local state = require 'telescope.actions.state'
  require('telescope.pickers')
    .new({}, {
      prompt_title = 'AI worktrees',
      finder = require('telescope.finders').new_table {
        results = entries,
        entry_maker = function(entry)
          local label = entry.branch .. '  ' .. vim.fn.fnamemodify(entry.path, ':~')
          return { value = entry, display = label, ordinal = label }
        end,
      },
      sorter = require('telescope.config').values.generic_sorter {},
      attach_mappings = function(buffer)
        actions.select_default:replace(function()
          local selected = state.get_selected_entry()
          actions.close(buffer)
          if selected then
            vim.schedule(function()
              M.open(selected.value.path, file)
            end)
          end
        end)
        return true
      end,
    })
    :find()
end

return M

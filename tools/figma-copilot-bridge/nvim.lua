local M = {}
local root = vim.fs.dirname(debug.getinfo(1, 'S').source:sub(2))
local pending = {}
local images = {}
local next_id = 0
local job
local children = {}
local stderr = ''
local stopping = false
local timeout_ms = 75000
local tool_timeout_ms = 375000
local approvals = {}
local active_approval
local show_next_approval

local function updated()
  if M.hub then
    M.hub:fire_servers_updated()
  end
end

local function answer_approval(approval, action)
  if approval.finished then
    return
  end
  approval.finished = true
  if approval.win and vim.api.nvim_win_is_valid(approval.win) then
    vim.api.nvim_win_close(approval.win, true)
  end
  if job == approval.job then
    local result = { action = action }
    if action == 'accept' then
      result.content = { approved = true }
    end
    if
      vim.fn.chansend(job, vim.json.encode {
        jsonrpc = '2.0',
        id = approval.id,
        result = result,
      } .. '\n') == 0
    then
      M.stop 'Could not deliver the Figma approval response.'
      vim.notify('Figma bridge: could not deliver the approval response.', vim.log.levels.ERROR)
    end
  end
  if active_approval == approval then
    active_approval = nil
    vim.schedule(function()
      show_next_approval()
    end)
  end
end

local function cancel_approvals(request_id)
  for index = #approvals, 1, -1 do
    local approval = approvals[index]
    if not request_id or approval.request_id == request_id then
      table.remove(approvals, index)
      answer_approval(approval, 'cancel')
    end
  end
  if active_approval and (not request_id or active_approval.request_id == request_id) then
    answer_approval(active_approval, 'cancel')
  end
end

show_next_approval = function()
  if stopping or active_approval or not job or #approvals == 0 then
    return
  end
  local approval = table.remove(approvals, 1)
  if approval.job ~= job or not pending[approval.request_id] then
    answer_approval(approval, 'cancel')
    vim.schedule(show_next_approval)
    return
  end
  active_approval = approval
  local lines = { 'a: Allow once    r/Enter: Reject    q/Esc: Cancel', '' }
  vim.list_extend(lines, vim.split(approval.message, '\n', { plain = true }))
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.api.nvim_buf_set_name(buf, 'figma-copilot://approval/' .. tostring(approval.id))
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = 'markdown'
  local width = math.min(100, math.max(1, vim.o.columns - 4))
  local height = math.min(math.max(1, vim.o.lines - 4), math.max(6, #lines))
  approval.win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = math.max(0, math.floor((vim.o.lines - height - 2) / 2)),
    col = math.max(0, math.floor((vim.o.columns - width - 2) / 2)),
    style = 'minimal',
    border = 'rounded',
    title = ' Figma approval ',
    title_pos = 'center',
  })
  vim.wo[approval.win].wrap = true
  vim.wo[approval.win].linebreak = true
  for key, action in pairs {
    a = 'accept',
    r = 'decline',
    ['<CR>'] = 'decline',
    q = 'cancel',
    ['<Esc>'] = 'cancel',
    ['<C-c>'] = 'cancel',
  } do
    vim.keymap.set('n', key, function()
      answer_approval(approval, action)
    end, { buffer = buf, nowait = true, silent = true })
  end
  vim.api.nvim_create_autocmd('BufWipeout', {
    buffer = buf,
    once = true,
    callback = function()
      answer_approval(approval, 'cancel')
    end,
  })
end

local function receive_approval(message)
  local params = message.params
  local schema = type(params) == 'table' and params.requestedSchema
  local parent = type(params) == 'table' and type(params._meta) == 'table' and params._meta['figma-copilot/requestId']
  if
    type(params) ~= 'table'
    or params.mode ~= 'form'
    or type(params.message) ~= 'string'
    or type(schema) ~= 'table'
    or type(schema.properties) ~= 'table'
    or type(schema.properties.approved) ~= 'table'
    or schema.properties.approved.type ~= 'boolean'
    or not pending[parent]
  then
    vim.fn.chansend(job, vim.json.encode {
      jsonrpc = '2.0',
      id = message.id,
      error = { code = -32602, message = 'Invalid or expired Figma approval request.' },
    } .. '\n')
    vim.notify('Figma bridge: invalid or expired approval request.', vim.log.levels.ERROR)
    return
  end
  table.insert(approvals, { id = message.id, request_id = parent, job = job, message = params.message })
  show_next_approval()
end

local function finish(id, result, err)
  local request = pending[id]
  if not request then
    return
  end
  pending[id] = nil
  cancel_approvals(id)
  if not request.timer:is_closing() then
    request.timer:stop()
    request.timer:close()
  end
  request.callback(result, err)
end

local function restore_images()
  for sidebar, state in pairs(images) do
    if sidebar.add_history_messages == state.wrapper then
      sidebar.add_history_messages = state.original
    end
  end
  images = {}
end

function M.stop(reason)
  stopping = true
  cancel_approvals()
  if job then
    local stopped_job = job
    vim.fn.chanclose(stopped_job, 'stdin')
    vim.defer_fn(function()
      if vim.fn.jobwait({ stopped_job }, 0)[1] == -1 then
        vim.fn.jobstop(stopped_job)
      end
    end, 9000)
    job = nil
  end
  local ids = vim.tbl_keys(pending)
  for _, id in ipairs(ids) do
    finish(id, nil, reason or 'Figma bridge stopped.')
  end
  restore_images()
  if M.server then
    M.server.status = 'disconnected'
    M.server.capabilities.tools = {}
    updated()
  end
  return true
end

local function fail(err)
  M.stop(err)
  if M.server then
    M.server.error = err
    updated()
  end
  vim.notify('Figma bridge: ' .. err, vim.log.levels.ERROR)
end

local function request(method, params, callback)
  if not job then
    callback(nil, 'Figma bridge is not running. Use :FigmaBridgeRestart.')
    return
  end
  next_id = next_id + 1
  local id = next_id
  pending[id] = {
    callback = callback,
    timer = vim.defer_fn(function()
      if pending[id] then
        fail(method .. ' timed out. Use :FigmaBridgeRestart.')
      end
    end, method == 'tools/call' and tool_timeout_ms or timeout_ms),
  }
  local sent = vim.fn.chansend(job, vim.json.encode {
    jsonrpc = '2.0',
    id = id,
    method = method,
    params = params,
  } .. '\n')
  if sent == 0 then
    fail 'Could not send a request to the Figma bridge.'
  end
end

local function queue_images(sidebar, result)
  if result.isError then
    return
  end
  local blocks = {}
  for _, content in ipairs(result.content or {}) do
    if content.type == 'image' then
      table.insert(blocks, {
        type = 'image',
        source = { type = 'base64', media_type = content.mimeType, data = content.data },
      })
    end
  end
  if #blocks == 0 then
    return
  end
  local state = images[sidebar]
  if not state then
    state = { original = sidebar.add_history_messages, history = sidebar.chat_history, blocks = {} }
    -- MCPHub's Avante extension drops images. Append them after the complete tool-result batch.
    state.wrapper = function(self, messages, opts)
      state.original(self, messages, opts)
      for _, message in ipairs(messages) do
        local content = message.message and message.message.content
        if type(content) == 'table' and content[1] and content[1].type == 'tool_result' then
          self.add_history_messages = state.original
          images[self] = nil
          if self.chat_history ~= state.history then
            vim.notify('Figma bridge: chat changed before images could be attached.', vim.log.levels.ERROR)
            return
          end
          local image_message = require('avante.history.message'):new('user', {
            type = 'text',
            text = 'Figma images returned by the preceding tool calls.',
          }, { visible = false })
          vim.list_extend(image_message.message.content, state.blocks)
          state.original(self, { image_message }, opts)
          return
        end
      end
    end
    images[sidebar] = state
    sidebar.add_history_messages = state.wrapper
  end
  vim.list_extend(state.blocks, blocks)
end

local function register_tools(result)
  assert(type(result.tools) == 'table' and #result.tools > 0, 'No Figma tools returned.')
  local tools = {}
  for _, tool in ipairs(result.tools) do
    assert(
      type(tool.name) == 'string' and type(tool.inputSchema) == 'table' and tool.inputSchema.type == 'object',
      'Invalid Figma tool schema.'
    )
    table.insert(tools, {
      name = tool.name,
      title = tool.title,
      description = tool.description,
      inputSchema = tool.inputSchema,
      annotations = tool.annotations,
      needs_confirmation_window = false,
      handler = function(req, res)
        request('tools/call', {
          name = tool.name,
          arguments = next(req.params or {}) and req.params or vim.empty_dict(),
        }, function(response, err)
          if err then
            res:error(err)
            return
          end
          if type(response.content) ~= 'table' then
            res:error 'Invalid Figma tool result: content is missing.'
            return
          end
          if req.caller and req.caller.type == 'avante' then
            local ok, image_error = pcall(queue_images, req.caller.avante, response)
            if not ok then
              res:error('Could not attach Figma images: ' .. tostring(image_error))
              return
            end
          end
          res:send(response)
        end)
      end,
    })
  end
  M.server.capabilities.tools = tools
  M.server.status = 'connected'
  M.server.error = nil
  updated()
end

function M.start()
  M.stop 'Figma bridge restarted.'
  stopping = false
  stderr = ''
  local command = M.command
  if not command then
    local node = vim.fn.exepath 'node'
    local entry = root .. '/dist/src/index.js'
    if node == '' or vim.fn.filereadable(entry) ~= 1 then
      fail 'Install and build tools/figma-copilot-bridge first; see its README. Disable with vim.g.figma_copilot_bridge = false.'
      return false
    end
    command = { node, entry }
  end
  local partial = ''
  local started_job
  started_job = vim.fn.jobstart(command, {
    cwd = root,
    on_stdout = function(_, data)
      if job ~= started_job then
        return
      end
      data[1] = partial .. data[1]
      partial = data[#data]
      for index = 1, #data - 1 do
        if data[index] ~= '' then
          local ok, message = pcall(vim.json.decode, data[index])
          if not ok or type(message) ~= 'table' or message.jsonrpc ~= '2.0' then
            fail 'Invalid JSON-RPC response from the bridge.'
            return
          end
          if message.id and message.method then
            if message.method == 'elicitation/create' then
              receive_approval(message)
            else
              vim.fn.chansend(job, vim.json.encode {
                jsonrpc = '2.0',
                id = message.id,
                error = { code = -32601, message = 'Unsupported bridge request: ' .. tostring(message.method) },
              } .. '\n')
            end
          elseif message.id and pending[message.id] then
            if message.error then
              if type(message.error) ~= 'table' or type(message.error.message) ~= 'string' then
                fail 'Invalid JSON-RPC error from the bridge.'
                return
              end
              finish(message.id, nil, message.error.message)
            elseif type(message.result) == 'table' then
              finish(message.id, message.result)
            else
              fail 'Invalid JSON-RPC result from the bridge.'
              return
            end
          end
        end
      end
    end,
    on_stderr = function(_, data)
      if job == started_job then
        stderr = (stderr .. table.concat(data, '\n')):sub(-4000)
      end
    end,
    on_exit = function(_, code)
      children[started_job] = nil
      if job == started_job then
        job = nil
        if not stopping then
          fail('Process exited with code ' .. code .. (stderr ~= '' and (': ' .. stderr) or ''))
        end
      end
    end,
  })
  if started_job <= 0 then
    fail 'Could not start the Figma bridge process.'
    return false
  end
  job = started_job
  children[started_job] = true
  M.server.status = 'connecting'
  updated()
  request('initialize', {
    protocolVersion = '2025-11-25',
    capabilities = { elicitation = { form = vim.empty_dict() } },
    clientInfo = { name = 'mcphub-figma-bridge', version = '0.1.0' },
  }, function(_, err)
    if stopping then
      return
    end
    if err then
      fail(err)
      return
    end
    vim.fn.chansend(job, vim.json.encode {
      jsonrpc = '2.0',
      method = 'notifications/initialized',
    } .. '\n')
    request('tools/list', vim.empty_dict(), function(result, list_error)
      if stopping then
        return
      end
      if list_error then
        fail(list_error)
      else
        local ok, registration_error = pcall(register_tools, result)
        if not ok then
          fail('Invalid Figma tool list: ' .. tostring(registration_error))
        end
      end
    end)
  end)
  return true
end

function M.setup(hub, opts)
  M.hub = hub
  if M.server and require('mcphub.native').is_native_server 'figma-copilot' == M.server then
    updated()
    return
  end
  if M.server then
    M.stop 'Figma bridge hub reinitialized.'
  end
  opts = opts or {}
  M.command = opts.command
  timeout_ms = opts.timeout_ms or timeout_ms
  tool_timeout_ms = opts.timeout_ms or tool_timeout_ms
  M.server = require('mcphub').add_server('figma-copilot', {
    displayName = 'Figma via Copilot',
    description = 'All remote Figma tools through the authenticated Copilot SDK. Non-audited operations require per-call approval. No extra model turns.',
  })
  if not M.server then
    fail 'Could not register the native MCPHub server.'
    return
  end
  local enabled = M.server.status ~= 'disabled'
  M.server.start = function()
    return M.start()
  end
  M.server.stop = function()
    return M.stop()
  end
  vim.api.nvim_create_user_command('FigmaBridgeRestart', M.start, {})
  vim.api.nvim_create_user_command('FigmaBridgeStop', function()
    M.stop()
  end, {})
  vim.api.nvim_create_autocmd('VimLeavePre', {
    group = vim.api.nvim_create_augroup('FigmaCopilotBridge', { clear = true }),
    callback = function()
      M.stop()
      local jobs = vim.tbl_keys(children)
      local statuses = vim.fn.jobwait(jobs, 8500)
      for index, status in ipairs(statuses) do
        if status == -1 then
          vim.fn.jobstop(jobs[index])
        end
      end
    end,
  })
  if enabled then
    M.start()
  end
end

package.loaded['figma-copilot-bridge'] = M
return M

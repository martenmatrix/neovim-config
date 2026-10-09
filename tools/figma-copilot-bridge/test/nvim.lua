local root = vim.fn.getcwd() .. '/tools/figma-copilot-bridge'
local live = os.getenv 'FIGMA_BRIDGE_LIVE' == '1'
vim.opt.runtimepath:prepend(vim.fn.getcwd())
for _, path in ipairs(vim.fn.glob(vim.fn.stdpath 'data' .. '/lazy/*', false, true)) do
  vim.opt.runtimepath:append(path)
end

local notifications = {}
vim.notify = function(message, level)
  if level == vim.log.levels.ERROR then
    table.insert(notifications, tostring(message))
  end
end
local config = vim.fn.tempname()
vim.fn.writefile({ '{"mcpServers":{}}' }, config)
local State = require 'mcphub.state'
State.config = require('mcphub.config').setup { config = config, auto_approve = true }
assert(require('mcphub.utils.config_manager').load_config(config))
local updates = 0
local hub = {
  mcp_request_timeout = 75000,
  fire_servers_updated = function()
    updates = updates + 1
  end,
}
setmetatable(hub, { __index = require 'mcphub.hub' })
local bridge = dofile(root .. '/nvim.lua')
local command = { vim.fn.exepath 'node', root .. (live and '/dist/src/index.js' or '/dist/test/fixture-server.js') }
local ok, err = xpcall(function()
  local hook = dofile(vim.fn.getcwd() .. '/lua/marten/plugins/mcphub.lua').opts.on_ready
  local cached = package.loaded['figma-copilot-bridge']
  local setups = 0
  package.loaded['figma-copilot-bridge'] = {
    setup = function()
      setups = setups + 1
    end,
  }
  vim.g.figma_copilot_bridge = false
  hook(hub)
  assert(setups == 0, 'Disabled bridge must not start')
  vim.g.figma_copilot_bridge = nil
  hook(hub)
  assert(setups == 1, 'Installed bridge must activate through the real plugin hook')
  local readable = vim.fn.filereadable
  vim.fn.filereadable = function()
    return 0
  end
  hook(hub)
  vim.fn.filereadable = readable
  assert(setups == 1, 'Removing the optional bridge directory must leave MCPHub usable')
  package.loaded['figma-copilot-bridge'] = cached
  bridge.setup(hub, { command = command, timeout_ms = live and 75000 or 3000 })
  assert(
    vim.wait(live and 75000 or 5000, function()
      return bridge.server.status == 'connected'
    end),
    table.concat(notifications, '\n')
  )
  assert(live and #bridge.server.capabilities.tools > 7 or not live and #bridge.server.capabilities.tools == 6)
  local tool_names = {}
  for _, tool in ipairs(bridge.server.capabilities.tools) do
    tool_names[tool.name] = true
    if tool.name == 'create_new_file' then
      assert(not tool.annotations or not tool.annotations.readOnlyHint, 'Writes must not be labelled read-only')
    end
  end
  assert(
    tool_names.get_libraries and tool_names.create_new_file,
    'Full tool coverage must include new reads and writes'
  )
  local prompt = require('mcphub.utils.prompt').get_active_servers_prompt({ bridge.server }, false, false)
  assert(prompt:find 'figma%-copilot', 'Native server must appear in model-facing metadata')
  assert(prompt:find 'get_screenshot', 'Figma tool schemas must appear in the model prompt')
  assert(updates > 0)

  local function call(name, arguments, caller)
    local done, result, error
    hub:call_tool('figma-copilot', name, arguments, {
      caller = caller,
      callback = function(value, failure)
        result, error, done = value, failure, true
      end,
    })
    assert(
      vim.wait(live and 75000 or 5000, function()
        return done
      end),
      'Native tool request did not finish'
    )
    return result, error
  end

  local result, error = call('whoami', {})
  assert(not error, error)
  if live then
    assert(not result.result.isError, 'Live Figma whoami failed')
    assert(#result.result.content > 0)
    return
  end
  assert(result.result.content[1].text == '{}', 'Empty arguments must remain a JSON object')
  local function begin_call(name, arguments)
    local state = {}
    hub:call_tool('figma-copilot', name, arguments, {
      callback = function(value, failure)
        state.result, state.error, state.done = value, failure, true
      end,
    })
    return state
  end
  local function approval_window()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.api.nvim_buf_get_name(buf):match '^figma%-copilot://approval/' then
        return win, buf
      end
    end
  end
  local function answer(key)
    assert(
      vim.wait(2000, function()
        return approval_window() ~= nil
      end),
      'Approval window was not shown'
    )
    local win, buf = approval_window()
    vim.api.nvim_set_current_win(win)
    local mapping = vim.fn.maparg(key, 'n', false, true)
    assert(type(mapping.callback) == 'function', 'Missing approval keymap: ' .. key)
    mapping.callback()
    return buf
  end
  local function wait_call(state)
    assert(
      vim.wait(2000, function()
        return state.done
      end),
      'Approved tool call did not finish'
    )
    assert(not state.error, state.error)
    return state.result.result
  end
  local rejected = begin_call('create_new_file', { name = 'Fixture' })
  answer '<CR>'
  assert(wait_call(rejected).isError, 'Enter must reject instead of approving')
  local inspected = call('whoami', { inspect = true })
  assert(inspected.result.content[1].text == '[]', 'Rejected tools must not execute')

  local args = { name = 'Fixture', code = 'line1\n' .. string.rep('x', 8192) .. '\nline3' }
  local approved = begin_call('create_new_file', args)
  assert(vim.wait(2000, function()
    return approval_window() ~= nil
  end))
  local _, review_buf = approval_window()
  local review = table.concat(vim.api.nvim_buf_get_lines(review_buf, 0, -1, false), '\n')
  assert(review:find(string.rep('x', 8192), 1, true), 'Approval must show complete arguments without truncation')
  answer 'a'
  assert(not wait_call(approved).isError)
  inspected = call('whoami', { inspect = true })
  assert(
    vim.deep_equal(
      vim.json.decode(inspected.result.content[1].text),
      { { name = 'create_new_file', arguments = args } }
    )
  )

  local again = begin_call('create_new_file', args)
  answer 'q'
  assert(wait_call(again).isError, 'Allow once must not approve a subsequent call')
  local first = begin_call('get_libraries', {})
  local second = begin_call('future_tool', {})
  answer 'a'
  answer 'r'
  assert(not wait_call(first).isError, 'New read tools must work after confirmation')
  assert(wait_call(second).isError, 'Queued requests must have independent decisions')
  assert(not approval_window(), 'Completed approvals must close their windows')

  local dismissed = begin_call('future_tool', {})
  assert(vim.wait(2000, function()
    return approval_window() ~= nil
  end))
  vim.api.nvim_win_close(approval_window(), true)
  assert(wait_call(dismissed).isError, 'Closing the review window must cancel instead of approving')

  local interrupted = begin_call('create_new_file', {})
  assert(vim.wait(2000, function()
    return approval_window() ~= nil
  end))
  bridge.stop()
  assert(wait_call(interrupted).isError)
  assert(not approval_window(), 'Stopping the bridge must close unanswered approvals')
  bridge.start()
  assert(vim.wait(5000, function()
    return bridge.server.status == 'connected'
  end))
  local long = call('get_metadata', { nodeId = 'long' })
  assert(#long.result.content[1].text == 131072, 'Fragmented stdout must preserve the complete result')

  local history = {}
  local sidebar = setmetatable({
    chat_history = { messages = history, title = 'Fixture' },
    save_history = function() end,
    throttled_update_content = function() end,
  }, { __index = require 'avante.sidebar' })
  local original = sidebar.add_history_messages
  local image = call('get_screenshot', {}, { type = 'avante', avante = sidebar })
  assert(image.result.content[1].type == 'image')
  assert(#history == 0, 'Images must not be inserted before tool results')
  local tool_result = require('avante.history.message'):new('user', {
    type = 'tool_result',
    tool_use_id = 'test-call',
    content = 'Screenshot fetched',
  })
  sidebar:add_history_messages { tool_result }
  assert(#history == 2)
  assert(history[1] == tool_result, 'Tool results must precede supplemental images')
  assert(#history[2].message.content == 1, 'Avante history requires one content block per message')
  assert(history[2].message.content[1].source.data == 'aW1hZ2U=')
  assert(sidebar.add_history_messages == original, 'The temporary image hook must restore itself')

  local spec = dofile(vim.fn.getcwd() .. '/lua/marten/plugins/avante.lua')
  require('avante.config').setup(spec.opts)
  local provider = require('avante.providers').copilot
  local messages = require('avante.providers.openai').parse_messages(provider, {
    system_prompt = 'Test',
    messages = {
      {
        role = 'assistant',
        content = {
          { type = 'tool_use', name = 'use_mcp_tool', id = 'test-call', input = {} },
        },
      },
      history[1].message,
      history[2].message,
    },
  })
  local last = messages[#messages]
  assert(last.role == 'user')
  assert(
    last.content[1].image_url.url == 'data:image/png;base64,aW1hZ2U=',
    'Screenshot must reach the Copilot model request'
  )

  local count = #history
  call('get_screenshot', {}, { type = 'avante', avante = sidebar })
  call('get_screenshot', {}, { type = 'avante', avante = sidebar })
  assert(#history == count, 'Multiple images must wait for the complete tool-result batch')
  local batch = {}
  for _, id in ipairs { 'screenshot-2', 'screenshot-3' } do
    batch[#batch + 1] = require('avante.history.message'):new('user', {
      type = 'tool_result',
      tool_use_id = id,
      content = 'Screenshot fetched',
    })
  end
  sidebar:add_history_messages(batch)
  assert(#history == count + 4, 'Every screenshot in a batch must have its own history message')
  assert(history[count + 1] == batch[1] and history[count + 2] == batch[2], 'All tool results must precede images')
  for index = count + 3, #history do
    assert(#history[index].message.content == 1, 'Multiple images must not share a history message')
    assert(history[index].message.content[1].type == 'image')
  end
  require('avante.history').get_pending_tools(history)
  assert(sidebar.add_history_messages == original, 'Batched image insertion must restore the hook')

  call('get_screenshot', {}, { type = 'avante', avante = sidebar })
  assert(sidebar.add_history_messages ~= original)
  bridge.server:stop()
  assert(sidebar.add_history_messages == original, 'Stop must remove pending image hooks')
  assert(bridge.server.status == 'disconnected')
  assert(#bridge.server.capabilities.tools == 0)
  assert(#notifications == 0, table.concat(notifications, '\n'))

  bridge.start()
  assert(vim.wait(5000, function()
    return bridge.server.status == 'connected'
  end))
  local crashed = call('get_metadata', { nodeId = 'crash' })
  assert(crashed.result.isError)
  assert(crashed.result.content[1].text:match 'exited with code 12')
  assert(bridge.server.status == 'disconnected')
  assert(#notifications == 1)
  notifications = {}

  bridge.command = { command[1], command[2], '--invalid-json' }
  bridge.start()
  assert(vim.wait(5000, function()
    return #notifications > 0
  end))
  assert(notifications[1]:match 'Invalid JSON%-RPC')
  notifications = {}
  bridge.command = command
  bridge.start()
  assert(vim.wait(5000, function()
    return bridge.server.status == 'connected'
  end))
  local hanging = call('get_metadata', { nodeId = 'hang' })
  assert(hanging.result.isError)
  assert(hanging.result.content[1].text:match 'timed out')
end, debug.traceback)
bridge.stop()
vim.fn.delete(config)
assert(ok, err)
print(live and 'Live Figma bridge Neovim check passed' or 'Figma bridge Neovim integration tests passed')

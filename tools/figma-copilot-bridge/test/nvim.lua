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
State.config = require('mcphub.config').setup { config = config }
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
  assert(#bridge.server.capabilities.tools == (live and 7 or 3))
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
  local long = call('get_metadata', { nodeId = 'long' })
  assert(#long.result.content[1].text == 131072, 'Fragmented stdout must preserve the complete result')

  local history = {}
  local sidebar = {
    chat_history = history,
    add_history_messages = function(_, messages)
      vim.list_extend(history, messages)
    end,
  }
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
  assert(history[2].message.content[2].source.data == 'aW1hZ2U=')
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
    last.content[2].image_url.url == 'data:image/png;base64,aW1hZ2U=',
    'Screenshot must reach the Copilot model request'
  )

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

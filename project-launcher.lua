local source = debug.getinfo(1, "S").source
if source:sub(1, 1) == "@" then
  source = source:sub(2)
end

local script_dir = source:match("^(.*)/[^/]+$") or "."
package.path = script_dir .. "/lua/?.lua;" .. script_dir .. "/lua/?/init.lua;" .. package.path

local action_executor = require("workstation.action_executor")
local command = require("workstation.command")
local generic_adapter = require("workstation.adapters.generic")
local launcher_cli = require("workstation.project_launcher_cli")
local omarchy_adapter = require("workstation.adapters.omarchy")
local project_actions = require("workstation.project_actions")
local project_cache = require("workstation.project_cache")
local project_config = require("workstation.project_config")
local project_discovery = require("workstation.project_discovery")
local project_search = require("workstation.project_search")
local project_state = require("workstation.project_state")
local project_types = require("workstation.project_types")
local protocol = require("workstation.launcher_protocol")

local home = assert(os.getenv("HOME"), "HOME is not set")

local context = {}
local loaded_config = nil

function context.load_config()
  local config, warning = project_config.load({ home = home })
  loaded_config = config
  return config, warning
end

function context.discover(config)
  return project_discovery.discover(config)
end

function context.cache_read()
  return project_cache.read({ home = home })
end

function context.cache_write(projects)
  return project_cache.write(projects, { home = home })
end

function context.load_state()
  return project_state.load({ home = home })
end

function context.save_state(state)
  return project_state.save(state, { home = home })
end

function context.rank(projects, query, state)
  return project_search.rank(projects, query, state)
end

local function current_config()
  if loaded_config then
    return loaded_config
  end
  local config = project_config.load({ home = home })
  loaded_config = config
  return config
end

local function select_adapter(config)
  return omarchy_adapter.detect(config) or generic_adapter.detect(config)
end

function context.resolve_actions(project, state)
  local config = current_config()
  local adapter = select_adapter(config)
  local capabilities = adapter.capabilities()
  capabilities.is_favorite = state.favorites[project.id] == true

  local types = project_types.detect(project)
  return project_actions.resolve(project, types, config, capabilities)
end

function context.execute(project, action, confirmed)
  local config = current_config()
  local adapter = select_adapter(config)
  return action_executor.run(project, action, adapter, nil, {
    confirmed = confirmed,
  })
end

function context.toggle_favorite(state, project_id)
  return project_state.toggle_favorite(state, project_id)
end

function context.mark_recent(state, project_id, now)
  return project_state.mark_recent(state, project_id, now)
end

function context.now()
  return os.time()
end

local args = {}
for index = 1, #arg do
  args[index] = arg[index]
end

local ok, result = pcall(launcher_cli.run, args, context)
if not ok then
  io.write(protocol.encode(protocol.failure("internal launcher error: " .. tostring(result))), "\n")
  os.exit(1)
end

io.write(protocol.encode(result), "\n")

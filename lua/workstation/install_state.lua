local paths = require("workstation.paths")
local command = require("workstation.command")

local M = {}

local function encode(value)
  return (tostring(value):gsub("([^%w%._%-%/])", function(char)
    return string.format("%%%02X", string.byte(char))
  end))
end

local function decode(value)
  return (value:gsub("%%(%x%x)", function(hex)
    return string.char(tonumber(hex, 16))
  end))
end

local function bool_field(value)
  return value and "1" or "0"
end

function M.write(path, state)
  assert(command.mkdir_p(paths.dirname(path)), "failed to create state directory")

  local version = state.version or 1
  local file = assert(io.open(path, "w"))
  local fields = {
    { "version", version },
    { "repo_root", state.repo_root },
    { "backup_dir", state.backup_dir or "" },
    { "preserved_bindings", bool_field(state.preserved_bindings) },
    { "preserved_workstation", bool_field(state.preserved_workstation) },
  }

  if version >= 2 then
    fields[#fields + 1] = { "launcher", bool_field(state.launcher) }
    fields[#fields + 1] = { "omarchy_hud", bool_field(state.omarchy_hud) }
    fields[#fields + 1] = { "omarchy_system_monitor", bool_field(state.omarchy_system_monitor) }
  end
  if version >= 3 then
    fields[#fields + 1] = { "workspace_overview", bool_field(state.workspace_overview) }
  end

  for _, item in ipairs(fields) do
    file:write(item[1], "=", encode(item[2]), "\n")
  end
  file:close()
  return true
end

function M.read(path)
  local file = io.open(path, "r")
  if not file then
    return nil
  end

  local state = {}
  for line in file:lines() do
    local key, value = line:match("^([^=]+)=(.*)$")
    if key then
      state[key] = decode(value)
    end
  end
  file:close()

  if state.repo_root == nil then
    return nil, "invalid install state"
  end

  state.version = tonumber(state.version or "1")
  if state.version == nil or state.version < 1 or state.version > 3 then
    return nil, "unsupported install state version"
  end

  state.preserved_bindings = state.preserved_bindings == "1"
  state.preserved_workstation = state.preserved_workstation == "1"

  if state.version >= 2 then
    state.launcher = state.launcher == "1"
    state.omarchy_hud = state.omarchy_hud == "1"
    state.omarchy_system_monitor = state.omarchy_system_monitor == "1"
    state.workspace_overview = state.version >= 3 and state.workspace_overview == "1" or false
  else
    -- v1 predates component ownership flags. Keep them unknown so the
    -- installer can derive ownership from repository-owned targets before
    -- migrating state to v2.
    state.launcher = nil
    state.omarchy_hud = nil
    state.omarchy_system_monitor = nil
    state.workspace_overview = nil
  end

  return state
end

return M

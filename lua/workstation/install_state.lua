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

function M.write(path, state)
  assert(command.mkdir_p(paths.dirname(path)), "failed to create state directory")

  local file = assert(io.open(path, "w"))
  local fields = {
    { "version", state.version or 1 },
    { "repo_root", state.repo_root },
    { "backup_dir", state.backup_dir or "" },
    { "preserved_bindings", state.preserved_bindings and "1" or "0" },
    { "preserved_workstation", state.preserved_workstation and "1" or "0" },
  }

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
  state.preserved_bindings = state.preserved_bindings == "1"
  state.preserved_workstation = state.preserved_workstation == "1"
  return state
end

return M

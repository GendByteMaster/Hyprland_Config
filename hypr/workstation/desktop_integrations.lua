local M = {}

local ORBIT_ID = "io.github.rohan-patnaik.window-switcher"
local CLIPBOARD_ID = "io.github.vuhuy.clipboard-manager"
local AGENT_ID = "meviusisback.agent-orchestr"

local function default_file_exists(path)
  local file = io.open(path, "r")
  if not file then
    return false
  end
  file:close()
  return true
end

local function default_command_exists(name)
  local ok = os.execute("command -v " .. tostring(name) .. " >/dev/null 2>&1")
  if type(ok) == "number" then
    return ok == 0
  end
  return ok == true
end

local function register_exec(hl, keys, command, description)
  if type(hl.unbind) == "function" then
    hl.unbind(keys)
  end

  hl.bind(keys, hl.dsp.exec_cmd(command), {
    description = description,
  })
end

function M.register(hl, _o, options)
  options = options or {}

  assert(type(hl) == "table", "Hyprland API is required")
  assert(type(hl.bind) == "function", "Hyprland bind API is required")
  assert(type(hl.dsp) == "table" and type(hl.dsp.exec_cmd) == "function", "Hyprland exec dispatcher is required")

  local home = options.home or os.getenv("HOME") or ""
  local file_exists = options.file_exists or default_file_exists
  local command_exists = options.command_exists or default_command_exists
  local load_file = options.load_file or dofile
  local plugin_root = home .. "/.config/omarchy/plugins"
  local result = {
    orbit = false,
    clipboard = false,
    agent_orchestrator = false,
    amneziavpn = false,
  }

  local orbit_bindings = plugin_root .. "/" .. ORBIT_ID .. "/bindings.lua"
  if file_exists(orbit_bindings) then
    local ok, err = pcall(load_file, orbit_bindings)
    result.orbit = ok
    if not ok then
      result.orbit_error = tostring(err)
    end
  end

  local clipboard_manifest = plugin_root .. "/" .. CLIPBOARD_ID .. "/manifest.json"
  if file_exists(clipboard_manifest) then
    register_exec(
      hl,
      "SUPER + V",
      "omarchy-shell shell toggle " .. CLIPBOARD_ID,
      "Clipboard Manager"
    )
    result.clipboard = true
  end

  local agent_manifest = plugin_root .. "/" .. AGENT_ID .. "/manifest.json"
  if file_exists(agent_manifest) then
    register_exec(
      hl,
      "SUPER + A",
      "omarchy shell " .. AGENT_ID .. " toggle",
      "Agent Orchestrator"
    )
    result.agent_orchestrator = true
  end

  if command_exists("AmneziaVPN") then
    register_exec(
      hl,
      "SUPER + ALT + V",
      "AmneziaVPN",
      "AmneziaVPN"
    )
    result.amneziavpn = true
  end

  return result
end

return M

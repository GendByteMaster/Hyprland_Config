local spatial_hud_module = require("hypr.workstation.spatial_hud")

local M = {}

local SPATIAL_ZOOM_PERCENT = 74

local DEFAULT_INSTALL_RELATIVE = ".local/lib/gendbyte-spatial"
local CURRENT_PATH_FILENAME = "current-path"
local LEGACY_PLUGIN_FILENAME = "gendbyte-spatial.so"

local function plugin_api(hl)
  if type(hl) ~= "table" or type(hl.plugin) ~= "table" then
    return nil
  end

  local api = hl.plugin.gendbyte_spatial
  if type(api) ~= "table" then
    return nil
  end

  if type(api.enabled) ~= "function"
      or type(api.toggle) ~= "function"
      or type(api.pan) ~= "function"
      or type(api.nudge) ~= "function"
      or type(api.brake) ~= "function"
      or type(api.reset) ~= "function" then
    return nil
  end

  return api
end

local function file_exists(path)
  local file = io.open(path, "rb")
  if not file then
    return false
  end

  file:close()
  return true
end

local function read_first_line(path)
  local file = io.open(path, "r")
  if not file then
    return nil
  end

  local line = file:read("*l")
  file:close()

  if type(line) ~= "string" or line == "" then
    return nil
  end

  return line
end

local function resolve_plugin_path(options)
  options = options or {}

  if type(options.plugin_path) == "string" and options.plugin_path ~= "" then
    return options.plugin_path
  end

  local env_path = os.getenv("GENDBYTE_SPATIAL_PLUGIN")
  if type(env_path) == "string" and env_path ~= "" then
    return env_path
  end

  local home = os.getenv("HOME")
  if type(home) ~= "string" or home == "" then
    return nil
  end

  local install_dir = home .. "/" .. DEFAULT_INSTALL_RELATIVE
  local pointer_file = install_dir .. "/" .. CURRENT_PATH_FILENAME

  local read_path = options.read_path or read_first_line
  if type(read_path) == "function" then
    local current = read_path(pointer_file)
    if type(current) == "string" and current:sub(1, 1) == "/" then
      return current
    end
  end

  -- Migration fallback for installs created before versioned plugin paths.
  return install_dir .. "/" .. LEGACY_PLUGIN_FILENAME
end

local function declare_plugin(hl, options)
  if type(hl) ~= "table"
      or type(hl.plugin) ~= "table"
      or type(hl.plugin.load) ~= "function" then
    return false, "Hyprland plugin.load API is unavailable"
  end

  local path = resolve_plugin_path(options)
  if not path then
    return false, "gendbyte-spatial plugin path could not be resolved"
  end

  local exists = options and options.file_exists or file_exists
  if type(exists) ~= "function" or not exists(path) then
    return false, "gendbyte-spatial plugin is not installed: " .. path
  end

  local ok, err = pcall(hl.plugin.load, path)
  if not ok then
    return false, tostring(err)
  end

  return true, path
end

local function invoke(hl, name, ...)
  local api = plugin_api(hl)
  if not api then
    return false, "gendbyte-spatial plugin is unavailable"
  end

  local fn = api[name]
  if type(fn) ~= "function" then
    return false, "gendbyte-spatial function is unavailable: " .. tostring(name)
  end

  local ok, result = pcall(fn, ...)
  if not ok then
    return false, tostring(result)
  end

  return true, result
end

function M.available(hl)
  return plugin_api(hl) ~= nil
end

function M.plugin_path(options)
  return resolve_plugin_path(options)
end

function M.enabled(hl)
  local ok, enabled = invoke(hl, "enabled")
  if not ok then
    return false, enabled
  end
  return true, enabled == true
end

function M.toggle(hl)
  return invoke(hl, "toggle")
end

function M.pan(hl, dx, dy)
  return invoke(hl, "pan", dx, dy)
end

function M.nudge(hl, xDirection, yDirection)
  return invoke(hl, "nudge", xDirection, yDirection)
end

function M.brake(hl)
  return invoke(hl, "brake")
end

function M.reset(hl)
  return invoke(hl, "reset")
end

local function register_binding(hl, keys, callback, description)
  if type(hl.unbind) == "function" then
    hl.unbind(keys)
  end

  return hl.bind(keys, callback, {
    description = description,
  })
end

local function register_motion_binding(hl, keys, xDirection, yDirection, description)
  if type(hl.unbind) == "function" then
    hl.unbind(keys)
  end

  local press = hl.bind(keys, function()
    M.nudge(hl, xDirection, yDirection)
  end, {
    description = description,
  })

  local release = hl.bind(keys, function()
    M.brake(hl)
  end, {
    release = true,
  })

  return press, release
end

local function set_handles_enabled(handles, enabled)
  for _, handle in ipairs(handles) do
    if handle and type(handle.set_enabled) == "function" then
      handle:set_enabled(enabled)
    end
  end
end

function M.register(hl, o, options)
  options = options or {}
  o = o or {}

  assert(type(hl) == "table", "Hyprland API is required")
  assert(type(hl.bind) == "function", "Hyprland bind API is required")

  -- Always declare the installed plugin on every config evaluation. Hyprland
  -- loads it after the first pass and performs a second reload where the
  -- hl.plugin.gendbyte_spatial namespace becomes available.
  local declared, declare_error = declare_plugin(hl, options)

  if not M.available(hl) then
    return false, declared and "gendbyte-spatial load scheduled" or declare_error
  end

  local hud = options.hud or spatial_hud_module.new(hl, o)
  local input_handles = {}

  local function track(handle)
    if handle then
      input_handles[#input_handles + 1] = handle
    end
    return handle
  end

  local function track_motion(keys, xDirection, yDirection, description)
    local press, release = register_motion_binding(hl, keys, xDirection, yDirection, description)
    track(press)
    track(release)
  end

  local function sync_input_mode(enabled)
    set_handles_enabled(input_handles, enabled == true)
  end

  local function show_spatial_hud(enabled, action)
    if hud and type(hud.show) == "function" then
      pcall(hud.show, enabled == true, SPATIAL_ZOOM_PERCENT, action)
    end
  end

  local function toggle_and_sync()
    local ok, enabled = M.toggle(hl)
    if ok then
      sync_input_mode(enabled == true)
      show_spatial_hud(enabled == true, "toggle")
    end
    return { ok = ok }
  end

  local function reset_and_notify()
    local ok = M.reset(hl)
    if ok then
      show_spatial_hud(true, "reset")
    end
    return { ok = ok }
  end

  register_binding(
    hl,
    "SUPER + ALT + G",
    toggle_and_sync,
    "Toggle Spatial Desktop"
  )

  register_binding(
    hl,
    "SUPER + F12",
    toggle_and_sync,
    "Toggle Spatial Desktop (Try Omarchy)"
  )

  -- Camera controls are real mode-scoped bindings: they only consume input
  -- while Spatial is enabled. Outside Spatial, arrows and 0 pass through to
  -- the focused application normally.
  track_motion("SUPER + ALT + LEFT", -1, 0, "Spatial Camera Left")
  track_motion("SUPER + ALT + RIGHT", 1, 0, "Spatial Camera Right")
  track_motion("SUPER + ALT + UP", 0, -1, "Spatial Camera Up")
  track_motion("SUPER + ALT + DOWN", 0, 1, "Spatial Camera Down")

  track_motion("LEFT", -1, 0, "Spatial Camera Left (Mode)")
  track_motion("RIGHT", 1, 0, "Spatial Camera Right (Mode)")
  track_motion("UP", 0, -1, "Spatial Camera Up (Mode)")
  track_motion("DOWN", 0, 1, "Spatial Camera Down (Mode)")

  track(register_binding(
    hl,
    "SUPER + ALT + 0",
    reset_and_notify,
    "Reset Spatial Camera"
  ))

  track(register_binding(
    hl,
    "0",
    reset_and_notify,
    "Reset Spatial Camera (Mode)"
  ))

  local state_ok, spatial_enabled = M.enabled(hl)
  sync_input_mode(state_ok and spatial_enabled)

  return true
end

return M

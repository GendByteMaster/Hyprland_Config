local M = {}

local DEFAULT_STEP = 160
local DEFAULT_INSTALL_RELATIVE = ".local/lib/gendbyte-spatial/gendbyte-spatial.so"

local function plugin_api(hl)
  if type(hl) ~= "table" or type(hl.plugin) ~= "table" then
    return nil
  end

  local api = hl.plugin.gendbyte_spatial
  if type(api) ~= "table" then
    return nil
  end

  if type(api.toggle) ~= "function"
      or type(api.pan) ~= "function"
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

  return home .. "/" .. DEFAULT_INSTALL_RELATIVE
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

function M.toggle(hl)
  return invoke(hl, "toggle")
end

function M.pan(hl, dx, dy)
  return invoke(hl, "pan", dx, dy)
end

function M.reset(hl)
  return invoke(hl, "reset")
end

local function register_binding(hl, keys, callback, description, repeating)
  if type(hl.unbind) == "function" then
    hl.unbind(keys)
  end

  hl.bind(keys, callback, {
    description = description,
    repeating = repeating == true,
  })
end

function M.register(hl, _o, options)
  options = options or {}

  assert(type(hl) == "table", "Hyprland API is required")
  assert(type(hl.bind) == "function", "Hyprland bind API is required")

  -- Always declare the installed plugin on every config evaluation. Hyprland
  -- loads it after the first pass and performs a second reload where the
  -- hl.plugin.gendbyte_spatial namespace becomes available.
  local declared, declare_error = declare_plugin(hl, options)

  if not M.available(hl) then
    return false, declared and "gendbyte-spatial load scheduled" or declare_error
  end

  local step = tonumber(options.step) or DEFAULT_STEP
  assert(step > 0 and step < 1000000, "spatial pan step must be a positive bounded number")

  register_binding(
    hl,
    "CTRL + SUPER + G",
    function()
      M.toggle(hl)
    end,
    "Toggle Spatial Desktop",
    false
  )

  register_binding(
    hl,
    "SUPER + ALT + LEFT",
    function()
      M.pan(hl, -step, 0)
    end,
    "Spatial Camera Left",
    true
  )

  register_binding(
    hl,
    "SUPER + ALT + RIGHT",
    function()
      M.pan(hl, step, 0)
    end,
    "Spatial Camera Right",
    true
  )

  register_binding(
    hl,
    "SUPER + ALT + UP",
    function()
      M.pan(hl, 0, -step)
    end,
    "Spatial Camera Up",
    true
  )

  register_binding(
    hl,
    "SUPER + ALT + DOWN",
    function()
      M.pan(hl, 0, step)
    end,
    "Spatial Camera Down",
    true
  )

  register_binding(
    hl,
    "SUPER + ALT + 0",
    function()
      M.reset(hl)
    end,
    "Reset Spatial Camera",
    false
  )

  return true
end

return M

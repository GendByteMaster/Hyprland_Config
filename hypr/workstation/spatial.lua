local M = {}

local DEFAULT_STEP = 160

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

  if not M.available(hl) then
    return false
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

local compat = require("hypr.workstation.compat")

local M = {}


local function overview_path(options)
  if options and type(options.launcher) == "string" and options.launcher ~= "" then
    return options.launcher
  end

  local home = os.getenv("HOME") or ""
  return home .. "/.local/bin/hyprland-workspace-overview"
end

local function default_exists(path)
  local file = io.open(path, "r")
  if not file then
    return false
  end
  file:close()
  return true
end

local function register_binding(hl, keys, command, description)
  if type(hl.unbind) == "function" then
    hl.unbind(keys)
  end

  hl.bind(keys, hl.dsp.exec_cmd(command), {
    description = description,
  })
end

local function register_dispatcher_binding(hl, keys, dispatcher, description)
  if type(hl.unbind) == "function" then
    hl.unbind(keys)
  end

  hl.bind(keys, dispatcher, {
    description = description,
  })
end

function M.register(hl, _o, options)
  options = options or {}

  assert(type(hl) == "table", "Hyprland API is required")
  assert(type(hl.bind) == "function", "Hyprland bind API is required")
  assert(type(hl.dsp) == "table" and type(hl.dsp.exec_cmd) == "function", "Hyprland exec dispatcher is required")
  assert(type(hl.dsp.focus) == "function", "Hyprland focus dispatcher is required")

  local command = overview_path(options)
  local exists = options.exists or default_exists

  if not exists(command) then
    return false
  end

  register_binding(hl, "SUPER + TAB", command, "Workspace Overview")

  -- Windows-style physical monitor cycling.
  register_dispatcher_binding(
    hl,
    "CTRL + ALT + TAB",
    hl.dsp.focus({ monitor = "+1" }),
    "Focus Next Monitor"
  )
  register_dispatcher_binding(
    hl,
    "CTRL + ALT + SHIFT + TAB",
    hl.dsp.focus({ monitor = "-1" }),
    "Focus Previous Monitor"
  )

  -- Keep the persistent all-monitor task switcher available without
  -- occupying the monitor-cycling chords.
  register_binding(
    hl,
    "SUPER + F10",
    command .. " task-switcher",
    "All-Monitor Window Switcher"
  )

  -- Try Omarchy may lose host-owned chords before they reach Hyprland.
  if compat.is_try_omarchy(options) then
    register_binding(hl, "SUPER + F9", command, "Workspace Overview (Try Omarchy)")
  end

  return true
end

return M

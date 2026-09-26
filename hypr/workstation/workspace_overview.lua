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

function M.register(hl, _o, options)
  options = options or {}

  assert(type(hl) == "table", "Hyprland API is required")
  assert(type(hl.bind) == "function", "Hyprland bind API is required")
  assert(type(hl.dsp) == "table" and type(hl.dsp.exec_cmd) == "function", "Hyprland exec dispatcher is required")

  local command = overview_path(options)
  local exists = options.exists or default_exists

  if not exists(command) then
    return false
  end

  -- Super+Tab is exclusively owned by Spatial Overview. The legacy UI keeps
  -- only explicit migration/fallback chords so two overview implementations
  -- can never be opened by one key press.
  -- Windows Ctrl+Alt+Tab semantics: open a persistent task switcher that
  -- stays visible after the chord is released.
  register_binding(
    hl,
    "CTRL + ALT + TAB",
    command .. " task-switcher",
    "Legacy Persistent Window Switcher"
  )

  -- Keep the explicit launcher chord as an additional accessibility path.
  register_binding(
    hl,
    "SUPER + F10",
    command .. " task-switcher",
    "Legacy All-Monitor Window Switcher"
  )

  -- Try Omarchy may lose host-owned chords before they reach Hyprland.
  if compat.is_try_omarchy(options) then
    register_binding(hl, "SUPER + F9", command, "Legacy Workspace Overview (Try Omarchy)")
  end

  return true
end

return M

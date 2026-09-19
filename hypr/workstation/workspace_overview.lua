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

  register_binding(hl, "SUPER + TAB", command, "Workspace Overview")
  register_binding(
    hl,
    "CTRL + ALT + TAB",
    command .. " task-switcher",
    "All-Monitor Window Switcher"
  )

  -- Try Omarchy may lose host-owned chords before they reach Hyprland.
  -- Super+Home is the accessibility-oriented alternate requested for the
  -- persistent task switcher. Windows may also own Win+Home unless QEMU raw
  -- keyboard grab is active, so this is a convenience fallback, not a
  -- guaranteed host-bypass shortcut.
  if compat.is_try_omarchy(options) then
    register_binding(hl, "SUPER + F9", command, "Workspace Overview (Try Omarchy)")
    register_binding(
      hl,
      "SUPER + HOME",
      command .. " task-switcher",
      "All-Monitor Window Switcher (Try Omarchy)"
    )
  end

  return true
end

return M

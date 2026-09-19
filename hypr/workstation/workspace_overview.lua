local compat = require("hypr.workstation.compat")

local M = {}

local OPENING_GUARD_SUBMAP = "gendbyte-workspace-overview-opening-guard"

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

local function register_super_binding(hl, keys, command, description)
  if type(hl.unbind) == "function" then
    hl.unbind(keys)
  end

  if type(hl.dispatch) == "function" then
    hl.bind(keys, function()
      -- Enter the guard before launching the UI so the release event is
      -- consumed even on a cold Quickshell start.
      hl.dispatch(hl.dsp.submap(OPENING_GUARD_SUBMAP))
      hl.dispatch(hl.dsp.exec_cmd(command))
    end, {
      description = description,
    })
  else
    hl.bind(keys, hl.dsp.exec_cmd(command), {
      description = description,
    })
  end
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

  if type(hl.define_submap) == "function" then
    hl.define_submap(OPENING_GUARD_SUBMAP, function()
      -- Consume only the Super release that belongs to the opening chord,
      -- then immediately return to the normal Omarchy keymap.
      hl.bind("Super_L", hl.dsp.submap("reset"), {
        release = true,
        description = "Finish Workspace Overview opening guard",
      })
      hl.bind("Super_R", hl.dsp.submap("reset"), {
        release = true,
        description = "Finish Workspace Overview opening guard",
      })
      hl.bind("Escape", hl.dsp.submap("reset"), {
        description = "Cancel Workspace Overview opening guard",
      })
    end)
  end

  register_super_binding(hl, "SUPER + TAB", command, "Workspace Overview")
  register_binding(
    hl,
    "CTRL + ALT + TAB",
    command .. " task-switcher",
    "All-Monitor Window Switcher"
  )

  -- Try Omarchy may lose host-owned chords before they reach Hyprland.
  -- Keep two-key accessibility fallbacks that do not collide with documented
  -- Omarchy window-management bindings.
  if compat.is_try_omarchy(options) then
    register_super_binding(hl, "SUPER + F9", command, "Workspace Overview (Try Omarchy)")
    register_super_binding(
      hl,
      "SUPER + F10",
      command .. " task-switcher",
      "All-Monitor Window Switcher (Try Omarchy)"
    )
  end

  return true
end

return M

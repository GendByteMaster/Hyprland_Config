local M = {}

local function register_binding(hl, keys, dispatcher, description)
  if type(hl.unbind) == "function" then
    hl.unbind(keys)
  end

  hl.bind(keys, dispatcher, {
    description = description,
  })
end

function M.register(hl, _o, _options)
  assert(type(hl) == "table", "Hyprland API is required")
  assert(type(hl.bind) == "function", "Hyprland bind API is required")
  assert(type(hl.dsp) == "table", "Hyprland dispatcher API is required")
  assert(type(hl.dsp.window) == "table", "Hyprland window dispatcher API is required")
  assert(type(hl.dsp.window.cycle_next) == "function", "Hyprland window cycle dispatcher is required")
  assert(type(hl.dsp.window.move) == "function", "Hyprland window move dispatcher is required")
  assert(type(hl.dsp.focus) == "function", "Hyprland focus dispatcher is required")

  register_binding(
    hl,
    "ALT + TAB",
    hl.dsp.window.cycle_next({ next = true }),
    "Next Window"
  )
  register_binding(
    hl,
    "ALT + SHIFT + TAB",
    hl.dsp.window.cycle_next({ next = false }),
    "Previous Window"
  )

  register_binding(
    hl,
    "SUPER + SHIFT + LEFT",
    hl.dsp.window.move({ monitor = "l" }),
    "Move Active Window to Left Monitor"
  )
  register_binding(
    hl,
    "SUPER + SHIFT + RIGHT",
    hl.dsp.window.move({ monitor = "r" }),
    "Move Active Window to Right Monitor"
  )

  register_binding(
    hl,
    "CTRL + SUPER + LEFT",
    hl.dsp.focus({ workspace = "m-1" }),
    "Previous Workspace"
  )
  register_binding(
    hl,
    "CTRL + SUPER + RIGHT",
    hl.dsp.focus({ workspace = "m+1" }),
    "Next Workspace"
  )

  return true
end

return M

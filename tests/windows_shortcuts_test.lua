local t = require("tests.testlib")
local shortcuts = require("hypr.workstation.windows_shortcuts")

local function fake_hyprland()
  local calls = {
    binds = {},
    unbinds = {},
  }

  local hl = {
    dsp = {
      window = {},
    },
  }

  function hl.dsp.window.cycle_next(options)
    return {
      kind = "cycle_next",
      next = options == nil or options.next ~= false,
    }
  end

  function hl.dsp.window.move(options)
    return {
      kind = "window_move",
      monitor = options and options.monitor or nil,
    }
  end

  function hl.dsp.focus(options)
    return {
      kind = "focus",
      workspace = options and options.workspace or nil,
    }
  end

  function hl.bind(keys, dispatcher, options)
    calls.binds[#calls.binds + 1] = {
      keys = keys,
      dispatcher = dispatcher,
      options = options or {},
    }
  end

  function hl.unbind(keys)
    calls.unbinds[#calls.unbinds + 1] = keys
  end

  return hl, calls
end

t.test("Windows shortcut layer registers only its owned bindings", function()
  local hl, calls = fake_hyprland()

  local registered = shortcuts.register(hl, {})

  t.eq(registered, true)
  t.eq(#calls.unbinds, 6)
  t.eq(#calls.binds, 6)

  t.eq(calls.unbinds[1], "ALT + TAB")
  t.eq(calls.unbinds[2], "ALT + SHIFT + TAB")
  t.eq(calls.unbinds[3], "SUPER + SHIFT + LEFT")
  t.eq(calls.unbinds[4], "SUPER + SHIFT + RIGHT")
  t.eq(calls.unbinds[5], "CTRL + SUPER + LEFT")
  t.eq(calls.unbinds[6], "CTRL + SUPER + RIGHT")
end)

t.test("Windows shortcut layer cycles windows forward and backward", function()
  local hl, calls = fake_hyprland()

  shortcuts.register(hl, {})

  t.eq(calls.binds[1].keys, "ALT + TAB")
  t.eq(calls.binds[1].dispatcher.kind, "cycle_next")
  t.eq(calls.binds[1].dispatcher.next, true)
  t.eq(calls.binds[1].options.description, "Next Window")

  t.eq(calls.binds[2].keys, "ALT + SHIFT + TAB")
  t.eq(calls.binds[2].dispatcher.kind, "cycle_next")
  t.eq(calls.binds[2].dispatcher.next, false)
  t.eq(calls.binds[2].options.description, "Previous Window")
end)

t.test("Windows shortcut layer moves the active window between physical monitors", function()
  local hl, calls = fake_hyprland()

  shortcuts.register(hl, {})

  t.eq(calls.binds[3].keys, "SUPER + SHIFT + LEFT")
  t.eq(calls.binds[3].dispatcher.kind, "window_move")
  t.eq(calls.binds[3].dispatcher.monitor, "l")
  t.eq(calls.binds[3].options.description, "Move Active Window to Left Monitor")

  t.eq(calls.binds[4].keys, "SUPER + SHIFT + RIGHT")
  t.eq(calls.binds[4].dispatcher.kind, "window_move")
  t.eq(calls.binds[4].dispatcher.monitor, "r")
  t.eq(calls.binds[4].options.description, "Move Active Window to Right Monitor")
end)

t.test("Windows shortcut layer switches existing workspaces on the current monitor", function()
  local hl, calls = fake_hyprland()

  shortcuts.register(hl, {})

  t.eq(calls.binds[5].keys, "CTRL + SUPER + LEFT")
  t.eq(calls.binds[5].dispatcher.kind, "focus")
  t.eq(calls.binds[5].dispatcher.workspace, "m-1")
  t.eq(calls.binds[5].options.description, "Previous Workspace")

  t.eq(calls.binds[6].keys, "CTRL + SUPER + RIGHT")
  t.eq(calls.binds[6].dispatcher.kind, "focus")
  t.eq(calls.binds[6].dispatcher.workspace, "m+1")
  t.eq(calls.binds[6].options.description, "Next Workspace")
end)

t.test("bindings loads Windows shortcut layer before Workspace Overview", function()
  local file = assert(io.open("hypr/bindings.lua", "r"))
  local source = file:read("*a")
  file:close()

  local windows_index = assert(source:find('require("hypr.workstation.windows_shortcuts")', 1, true))
  local overview_index = assert(source:find('require("hypr.workstation.workspace_overview")', 1, true))

  t.truthy(windows_index < overview_index)
end)

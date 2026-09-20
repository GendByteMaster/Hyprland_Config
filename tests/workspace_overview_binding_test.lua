local t = require("tests.testlib")
local overview = require("hypr.workstation.workspace_overview")

local function fake_hyprland()
  local calls = {
    binds = {},
    unbinds = {},
  }

  local hl = { dsp = { window = {} } }

  function hl.dsp.exec_cmd(command)
    return {
      kind = "exec",
      command = command,
    }
  end

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

t.test("workspace UI owns Windows-style switching bindings when installed", function()
  local hl, calls = fake_hyprland()

  local registered = overview.register(hl, {}, {
    launcher = "/home/test/.local/bin/hyprland-workspace-overview",
    exists = function(path)
      return path == "/home/test/.local/bin/hyprland-workspace-overview"
    end,
  })

  t.eq(registered, true)
  t.eq(#calls.unbinds, 7)
  t.eq(calls.unbinds[1], "SUPER + TAB")
  t.eq(calls.unbinds[2], "ALT + TAB")
  t.eq(calls.unbinds[3], "ALT + SHIFT + TAB")
  t.eq(calls.unbinds[4], "SUPER + SHIFT + LEFT")
  t.eq(calls.unbinds[5], "SUPER + SHIFT + RIGHT")
  t.eq(calls.unbinds[6], "CTRL + ALT + TAB")
  t.eq(calls.unbinds[7], "SUPER + F10")

  t.eq(#calls.binds, 7)

  t.eq(calls.binds[1].keys, "SUPER + TAB")
  t.eq(calls.binds[1].dispatcher.kind, "exec")
  t.eq(calls.binds[1].options.description, "Workspace Overview")

  t.eq(calls.binds[2].keys, "ALT + TAB")
  t.eq(calls.binds[2].dispatcher.kind, "cycle_next")
  t.eq(calls.binds[2].dispatcher.next, true)

  t.eq(calls.binds[3].keys, "ALT + SHIFT + TAB")
  t.eq(calls.binds[3].dispatcher.kind, "cycle_next")
  t.eq(calls.binds[3].dispatcher.next, false)

  t.eq(calls.binds[4].keys, "SUPER + SHIFT + LEFT")
  t.eq(calls.binds[4].dispatcher.kind, "window_move")
  t.eq(calls.binds[4].dispatcher.monitor, "l")
  t.eq(calls.binds[4].options.description, "Move Active Window to Left Monitor")

  t.eq(calls.binds[5].keys, "SUPER + SHIFT + RIGHT")
  t.eq(calls.binds[5].dispatcher.kind, "window_move")
  t.eq(calls.binds[5].dispatcher.monitor, "r")
  t.eq(calls.binds[5].options.description, "Move Active Window to Right Monitor")

  t.eq(calls.binds[6].keys, "CTRL + ALT + TAB")
  t.eq(calls.binds[6].dispatcher.kind, "exec")
  t.eq(
    calls.binds[6].dispatcher.command,
    "/home/test/.local/bin/hyprland-workspace-overview task-switcher"
  )

  t.eq(calls.binds[7].keys, "SUPER + F10")
  t.eq(calls.binds[7].dispatcher.kind, "exec")
  t.eq(
    calls.binds[7].dispatcher.command,
    "/home/test/.local/bin/hyprland-workspace-overview task-switcher"
  )
end)

t.test("workspace UI adds only the Try Omarchy overview fallback", function()
  local hl, calls = fake_hyprland()

  local registered = overview.register(hl, {}, {
    launcher = "/home/test/.local/bin/hyprland-workspace-overview",
    exists = function() return true end,
    kernel_cmdline = "quiet splash omarchy.qemu=1",
  })

  t.eq(registered, true)
  t.eq(#calls.unbinds, 8)
  t.eq(calls.unbinds[8], "SUPER + F9")

  t.eq(#calls.binds, 8)
  t.eq(calls.binds[8].keys, "SUPER + F9")
  t.eq(calls.binds[8].dispatcher.kind, "exec")
  t.eq(
    calls.binds[8].dispatcher.command,
    "/home/test/.local/bin/hyprland-workspace-overview"
  )
end)

t.test("workspace overview leaves Super Tab untouched before install", function()
  local hl, calls = fake_hyprland()

  local registered = overview.register(hl, {}, {
    launcher = "/home/test/.local/bin/hyprland-workspace-overview",
    exists = function() return false end,
  })

  t.eq(registered, false)
  t.eq(#calls.unbinds, 0)
  t.eq(#calls.binds, 0)
end)

t.test("bindings loads workspace overview after project launcher", function()
  local file = assert(io.open("hypr/bindings.lua", "r"))
  local source = file:read("*a")
  file:close()

  local launcher = assert(source:find('require("hypr.workstation.project_launcher")', 1, true))
  local overview_index = assert(source:find('require("hypr.workstation.workspace_overview")', 1, true))

  t.truthy(launcher < overview_index)
end)

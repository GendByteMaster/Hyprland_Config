local t = require("tests.testlib")
local overview = require("hypr.workstation.workspace_overview")

local function fake_hyprland()
  local calls = {
    binds = {},
    unbinds = {},
  }

  local hl = { dsp = {} }

  function hl.dsp.exec_cmd(command)
    return {
      kind = "exec",
      command = command,
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

t.test("workspace UI owns overview and all-monitor switcher bindings when installed", function()
  local hl, calls = fake_hyprland()

  local registered = overview.register(hl, {}, {
    launcher = "/home/test/.local/bin/hyprland-workspace-overview",
    exists = function(path)
      return path == "/home/test/.local/bin/hyprland-workspace-overview"
    end,
  })

  t.eq(registered, true)
  t.eq(#calls.unbinds, 2)
  t.eq(calls.unbinds[1], "SUPER + TAB")
  t.eq(calls.unbinds[2], "CTRL + ALT + TAB")
  t.eq(#calls.binds, 2)
  t.eq(calls.binds[1].keys, "SUPER + TAB")
  t.eq(calls.binds[1].dispatcher.kind, "exec")
  t.eq(
    calls.binds[1].dispatcher.command,
    "/home/test/.local/bin/hyprland-workspace-overview"
  )
  t.eq(calls.binds[1].options.description, "Workspace Overview")
  t.eq(calls.binds[2].keys, "CTRL + ALT + TAB")
  t.eq(
    calls.binds[2].dispatcher.command,
    "/home/test/.local/bin/hyprland-workspace-overview task-switcher"
  )
  t.eq(calls.binds[2].options.description, "All-Monitor Window Switcher")
end)

t.test("workspace UI adds Try Omarchy overview and Super F10 switcher fallbacks", function()
  local hl, calls = fake_hyprland()

  local registered = overview.register(hl, {}, {
    launcher = "/home/test/.local/bin/hyprland-workspace-overview",
    exists = function() return true end,
    kernel_cmdline = "quiet splash omarchy.qemu=1",
  })

  t.eq(registered, true)
  t.eq(#calls.unbinds, 4)
  t.eq(calls.unbinds[1], "SUPER + TAB")
  t.eq(calls.unbinds[2], "CTRL + ALT + TAB")
  t.eq(calls.unbinds[3], "SUPER + F9")
  t.eq(calls.unbinds[4], "SUPER + F10")
  t.eq(#calls.binds, 4)
  t.eq(calls.binds[1].keys, "SUPER + TAB")
  t.eq(calls.binds[2].keys, "CTRL + ALT + TAB")
  t.eq(calls.binds[3].keys, "SUPER + F9")
  t.eq(calls.binds[4].keys, "SUPER + F10")
  t.eq(
    calls.binds[3].dispatcher.command,
    "/home/test/.local/bin/hyprland-workspace-overview"
  )
  t.eq(
    calls.binds[4].dispatcher.command,
    "/home/test/.local/bin/hyprland-workspace-overview task-switcher"
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

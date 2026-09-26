local t = require("tests.testlib")
local overview = require("hypr.workstation.workspace_overview")

local function fake_hyprland(with_spatial)
  local calls = {
    binds = {},
    unbinds = {},
  }

  local hl = {
    dsp = {},
    plugin = {},
  }

  if with_spatial then
    hl.plugin.gendbyte_spatial = {
      enabled = function() return false end,
      toggle = function() return false end,
      pan = function() end,
      nudge = function() end,
      brake = function() end,
      reset = function() end,
      select = function() return false end,
    }
  end

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

t.test("legacy workspace UI never owns Super Tab", function()
  local hl, calls = fake_hyprland()

  local registered = overview.register(hl, {}, {
    launcher = "/home/test/.local/bin/hyprland-workspace-overview",
    exists = function(path)
      return path == "/home/test/.local/bin/hyprland-workspace-overview"
    end,
  })

  t.eq(registered, true)
  t.eq(#calls.unbinds, 2)
  t.eq(calls.unbinds[1], "CTRL + ALT + TAB")
  t.eq(calls.unbinds[2], "SUPER + F10")

  t.eq(#calls.binds, 2)

  t.eq(calls.binds[1].keys, "CTRL + ALT + TAB")
  t.eq(calls.binds[1].dispatcher.kind, "exec")
  t.eq(
    calls.binds[1].dispatcher.command,
    "/home/test/.local/bin/hyprland-workspace-overview task-switcher"
  )
  t.eq(calls.binds[1].options.description, "Legacy Persistent Window Switcher")

  t.eq(calls.binds[2].keys, "SUPER + F10")
  t.eq(calls.binds[2].dispatcher.kind, "exec")
  t.eq(
    calls.binds[2].dispatcher.command,
    "/home/test/.local/bin/hyprland-workspace-overview task-switcher"
  )
  t.eq(calls.binds[2].options.description, "Legacy All-Monitor Window Switcher")
end)

t.test("workspace UI adds only the Try Omarchy overview fallback", function()
  local hl, calls = fake_hyprland()

  local registered = overview.register(hl, {}, {
    launcher = "/home/test/.local/bin/hyprland-workspace-overview",
    exists = function() return true end,
    kernel_cmdline = "quiet splash omarchy.qemu=1",
  })

  t.eq(registered, true)
  t.eq(#calls.unbinds, 3)
  t.eq(calls.unbinds[3], "SUPER + F9")

  t.eq(#calls.binds, 3)
  t.eq(calls.binds[3].keys, "SUPER + F9")
  t.eq(calls.binds[3].dispatcher.kind, "exec")
  t.eq(calls.binds[3].options.description, "Legacy Workspace Overview (Try Omarchy)")
  t.eq(
    calls.binds[3].dispatcher.command,
    "/home/test/.local/bin/hyprland-workspace-overview"
  )
end)

t.test("workspace overview leaves bindings untouched before install", function()
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

local t = require("tests.testlib")
local overview = require("hypr.workstation.workspace_overview")

local function fake_hyprland()
  local calls = {
    binds = {},
    submap_binds = {},
    unbinds = {},
    submaps = {},
  }

  local active_submap = nil
  local hl = { dsp = {} }

  function hl.dsp.submap(name)
    return {
      kind = "submap",
      name = name,
    }
  end

  function hl.dsp.exec_cmd(command)
    return {
      kind = "exec",
      command = command,
    }
  end

  function hl.dispatch(dispatcher)
    calls.dispatched = calls.dispatched or {}
    calls.dispatched[#calls.dispatched + 1] = dispatcher
  end

  function hl.bind(keys, dispatcher, options)
    local item = {
      keys = keys,
      dispatcher = dispatcher,
      options = options or {},
    }

    if active_submap then
      item.submap = active_submap
      calls.submap_binds[#calls.submap_binds + 1] = item
    else
      calls.binds[#calls.binds + 1] = item
    end
  end

  function hl.unbind(keys)
    calls.unbinds[#calls.unbinds + 1] = keys
  end

  function hl.define_submap(name, callback)
    calls.submaps[#calls.submaps + 1] = name
    if callback then
      active_submap = name
      callback()
      active_submap = nil
    end
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
  t.eq(#calls.submaps, 1)
  t.eq(calls.submaps[1], "gendbyte-workspace-overview-opening-guard")
  t.eq(#calls.submap_binds, 3)
  t.eq(calls.submap_binds[1].keys, "Super_L")
  t.eq(calls.submap_binds[1].options.release, true)
  t.eq(calls.submap_binds[1].dispatcher.kind, "submap")
  t.eq(calls.submap_binds[1].dispatcher.name, "reset")
  t.eq(calls.submap_binds[2].keys, "Super_R")
  t.eq(calls.submap_binds[2].options.release, true)
  t.eq(calls.submap_binds[2].dispatcher.name, "reset")
  t.eq(calls.submap_binds[3].keys, "Escape")
  t.eq(calls.submap_binds[3].dispatcher.name, "reset")
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
  t.eq(#calls.submaps, 0)
  t.eq(#calls.submap_binds, 0)
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

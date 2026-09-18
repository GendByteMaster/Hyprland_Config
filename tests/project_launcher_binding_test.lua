local t = require("tests.testlib")

local function fake_hyprland()
  local calls = {
    binds = {},
    unbinds = {},
    rules = {},
  }

  local hl = {
    dsp = {},
  }

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
    return {
      set_enabled = function() end,
    }
  end

  function hl.unbind(keys)
    calls.unbinds[#calls.unbinds + 1] = keys
  end

  function hl.window_rule(rule)
    calls.rules[#calls.rules + 1] = rule
  end

  return hl, calls
end

local function read_file(path)
  local file = assert(io.open(path, "r"), "missing file: " .. path)
  local content = file:read("*a")
  file:close()
  return content
end

t.test("project launcher owns Super R and dispatches only wrapper exec", function()
  local launcher = require("hypr.workstation.project_launcher")
  local hl, calls = fake_hyprland()

  launcher.register(hl, {}, {
    launcher = "/home/test/.local/bin/hyprland-workstation-launcher",
    kernel_cmdline = "quiet splash",
  })

  t.eq(#calls.unbinds, 1)
  t.eq(calls.unbinds[1], "SUPER + R")
  t.eq(#calls.binds, 1)
  t.eq(calls.binds[1].keys, "SUPER + R")
  t.eq(calls.binds[1].dispatcher.kind, "exec")
  t.eq(
    calls.binds[1].dispatcher.command,
    "/home/test/.local/bin/hyprland-workstation-launcher"
  )
  t.eq(calls.binds[1].options.description, "Project Launcher")
end)

t.test("project launcher registers narrow centered floating rule", function()
  local launcher = require("hypr.workstation.project_launcher")
  local hl, calls = fake_hyprland()

  launcher.register(hl, {}, {
    launcher = "/home/test/.local/bin/hyprland-workstation-launcher",
    kernel_cmdline = "quiet splash",
  })

  t.eq(#calls.rules, 1)
  t.eq(calls.rules[1].name, "gendbyte-project-launcher")
  t.eq(calls.rules[1].match.class, "^gendbyte-project-launcher$")
  t.eq(calls.rules[1].float, true)
  t.eq(calls.rules[1].center, true)
end)

t.test("project launcher falls back when unbind API is absent", function()
  local launcher = require("hypr.workstation.project_launcher")
  local hl, calls = fake_hyprland()
  hl.unbind = nil

  local ok = pcall(function()
    launcher.register(hl, {}, {
      launcher = "/home/test/.local/bin/hyprland-workstation-launcher",
    kernel_cmdline = "quiet splash",
    })
  end)

  t.eq(ok, true)
  t.eq(#calls.binds, 1)
  t.eq(calls.binds[1].keys, "SUPER + R")
end)

t.test("project launcher source never claims Super H or scans projects", function()
  local source = read_file("hypr/workstation/project_launcher.lua")
  t.eq(source:find("SUPER + H", 1, true), nil)
  t.eq(source:find("SUPER,H", 1, true), nil)
  t.eq(source:find("project_discovery", 1, true), nil)
  t.eq(source:find("project_types", 1, true), nil)
  t.eq(source:find("find ", 1, true), nil)
end)

t.test("bindings entrypoint registers project launcher after existing layers", function()
  local source = read_file("hypr/bindings.lua")
  local compat = assert(source:find('require("hypr.workstation.compat")', 1, true))
  local mouse = assert(source:find('require("hypr.workstation.mouse")', 1, true))
  local launcher = assert(source:find('require("hypr.workstation.project_launcher")', 1, true))

  t.truthy(compat < mouse)
  t.truthy(mouse < launcher)
end)

t.test("project launcher wrapper tolerates slow cold start and serializes startup", function()
  local source = read_file("bin/hyprland-workstation-launcher")

  t.truthy(source:find("STARTUP_ATTEMPTS=100", 1, true))
  t.truthy(source:find("STARTUP_DELAY=0.05", 1, true))
  t.truthy(source:find("acquire_start_lock", 1, true))
  t.truthy(source:find("wait_for_ipc", 1, true))
  t.truthy(source:find("project-launcher.log", 1, true))
  t.eq(source:find("seq 1 20", 1, true), nil)
end)

t.test("Try Omarchy gets a no-Super launcher fallback", function()
  local launcher = require("hypr.workstation.project_launcher")
  local hl, calls = fake_hyprland()

  launcher.register(hl, {}, {
    launcher = "/home/test/.local/bin/hyprland-workstation-launcher",
    kernel_cmdline = "quiet omarchy.qemu=1 tryomarchy.render=cpu",
  })

  t.eq(#calls.unbinds, 2)
  t.eq(calls.unbinds[1], "SUPER + R")
  t.eq(calls.unbinds[2], "CTRL + ALT + R")
  t.eq(#calls.binds, 2)
  t.eq(calls.binds[1].keys, "SUPER + R")
  t.eq(calls.binds[2].keys, "CTRL + ALT + R")
  t.eq(calls.binds[2].dispatcher.command, "/home/test/.local/bin/hyprland-workstation-launcher")
  t.eq(calls.binds[2].options.description, "Project Launcher (Try Omarchy fallback)")
end)

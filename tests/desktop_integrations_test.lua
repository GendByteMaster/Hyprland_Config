local t = require("tests.testlib")
local integrations = require("hypr.workstation.desktop_integrations")

local function fake_hyprland()
  local calls = {
    binds = {},
    unbinds = {},
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
  end

  function hl.unbind(keys)
    calls.unbinds[#calls.unbinds + 1] = keys
  end

  return hl, calls
end

t.test("desktop integrations do not reserve shortcuts when components are unavailable", function()
  local hl, calls = fake_hyprland()

  local result = integrations.register(hl, {}, {
    home = "/home/test",
    file_exists = function() return false end,
    command_exists = function() return false end,
  })

  t.eq(#calls.binds, 0)
  t.eq(#calls.unbinds, 0)
  t.eq(result.orbit, false)
  t.eq(result.clipboard, false)
  t.eq(result.agent_orchestrator, false)
  t.eq(result.amneziavpn, false)
end)

t.test("desktop integrations load Orbit and register managed plugin and VPN shortcuts", function()
  local hl, calls = fake_hyprland()
  local loaded
  local files = {
    ["/home/test/.config/omarchy/plugins/io.github.rohan-patnaik.window-switcher/bindings.lua"] = true,
    ["/home/test/.config/omarchy/plugins/io.github.vuhuy.clipboard-manager/manifest.json"] = true,
    ["/home/test/.config/omarchy/plugins/meviusisback.agent-orchestr/manifest.json"] = true,
  }

  local result = integrations.register(hl, {}, {
    home = "/home/test",
    file_exists = function(path) return files[path] == true end,
    command_exists = function(name) return name == "AmneziaVPN" end,
    load_file = function(path)
      loaded = path
    end,
  })

  t.eq(loaded, "/home/test/.config/omarchy/plugins/io.github.rohan-patnaik.window-switcher/bindings.lua")
  t.eq(result.orbit, true)
  t.eq(#calls.binds, 3)
  t.eq(#calls.unbinds, 3)

  t.eq(calls.binds[1].keys, "SUPER + V")
  t.eq(calls.binds[1].dispatcher.command, "omarchy-shell shell toggle io.github.vuhuy.clipboard-manager")
  t.eq(calls.binds[1].options.description, "Clipboard Manager")

  t.eq(calls.binds[2].keys, "SUPER + A")
  t.eq(calls.binds[2].dispatcher.command, "omarchy shell meviusisback.agent-orchestr toggle")
  t.eq(calls.binds[2].options.description, "Agent Orchestrator")

  t.eq(calls.binds[3].keys, "SUPER + ALT + V")
  t.eq(calls.binds[3].dispatcher.command, "AmneziaVPN")
  t.eq(calls.binds[3].options.description, "AmneziaVPN")
end)

t.test("Orbit loader failure is reported without blocking other desktop integrations", function()
  local hl, calls = fake_hyprland()

  local result = integrations.register(hl, {}, {
    home = "/home/test",
    file_exists = function(path)
      return path:match("window%-switcher/bindings%.lua$") ~= nil
        or path:match("clipboard%-manager/manifest%.json$") ~= nil
    end,
    command_exists = function() return false end,
    load_file = function()
      error("broken Orbit bindings")
    end,
  })

  t.eq(result.orbit, false)
  t.truthy(result.orbit_error:match("broken Orbit bindings"))
  t.eq(result.clipboard, true)
  t.eq(#calls.binds, 1)
  t.eq(calls.binds[1].keys, "SUPER + V")
end)

t.test("desktop integrations load after Windows fallback shortcuts and before Workspace Overview", function()
  local file = assert(io.open("hypr/bindings.lua", "r"))
  local source = file:read("*a")
  file:close()

  local windows_index = assert(source:find('require("hypr.workstation.windows_shortcuts")', 1, true))
  local integrations_index = assert(source:find('require("hypr.workstation.desktop_integrations")', 1, true))
  local overview_index = assert(source:find('require("hypr.workstation.workspace_overview")', 1, true))

  t.truthy(windows_index < integrations_index)
  t.truthy(integrations_index < overview_index)
end)

local t = require("tests.testlib")
local spatial = require("hypr.workstation.spatial")

local function fake_hyprland(with_plugin)
  local calls = {
    binds = {},
    unbinds = {},
    plugin = {},
    loads = {},
  }

  local hl = {
    plugin = {},
  }

  function hl.plugin.load(path)
    calls.loads[#calls.loads + 1] = path
  end

  if with_plugin then
    hl.plugin.gendbyte_spatial = {}

    function hl.plugin.gendbyte_spatial.toggle()
      calls.plugin[#calls.plugin + 1] = {
        name = "toggle",
      }
    end

    function hl.plugin.gendbyte_spatial.pan(dx, dy)
      calls.plugin[#calls.plugin + 1] = {
        name = "pan",
        dx = dx,
        dy = dy,
      }
    end

    function hl.plugin.gendbyte_spatial.nudge(xDirection, yDirection)
      calls.plugin[#calls.plugin + 1] = {
        name = "nudge",
        dx = xDirection,
        dy = yDirection,
      }
    end

    function hl.plugin.gendbyte_spatial.brake()
      calls.plugin[#calls.plugin + 1] = {
        name = "brake",
      }
    end

    function hl.plugin.gendbyte_spatial.reset()
      calls.plugin[#calls.plugin + 1] = {
        name = "reset",
      }
    end
  end

  function hl.bind(keys, callback, options)
    calls.binds[#calls.binds + 1] = {
      keys = keys,
      callback = callback,
      options = options or {},
    }
  end

  function hl.unbind(keys)
    calls.unbinds[#calls.unbinds + 1] = keys
  end

  return hl, calls
end

local INSTALLED_OPTIONS = {
  plugin_path = "/tmp/gendbyte-spatial.so",
  file_exists = function()
    return true
  end,
}

t.test("spatial plugin resolver prefers current-path pointer", function()
  local path = spatial.plugin_path({
    read_path = function(pointer)
      t.truthy(pointer:find("/.local/lib/gendbyte-spatial/current-path", 1, true) ~= nil)
      return "/tmp/gendbyte-spatial-deadbeef.so"
    end,
  })

  t.eq(path, "/tmp/gendbyte-spatial-deadbeef.so")
end)

t.test("spatial plugin resolver rejects relative pointer entries", function()
  local path = spatial.plugin_path({
    read_path = function()
      return "relative/gendbyte-spatial.so"
    end,
  })

  local home = os.getenv("HOME")
  t.eq(path, home .. "/.local/lib/gendbyte-spatial/gendbyte-spatial.so")
end)

t.test("spatial bindings preserve normal Hyprland when plugin install is unavailable", function()
  local hl, calls = fake_hyprland(false)

  local registered = spatial.register(hl, {}, {
    plugin_path = "/tmp/missing-gendbyte-spatial.so",
    file_exists = function()
      return false
    end,
  })

  t.eq(registered, false)
  t.eq(#calls.loads, 0)
  t.eq(#calls.unbinds, 0)
  t.eq(#calls.binds, 0)
  t.eq(spatial.available(hl), false)
end)

t.test("spatial config schedules installed plugin load before API becomes available", function()
  local hl, calls = fake_hyprland(false)

  local registered, status = spatial.register(hl, {}, INSTALLED_OPTIONS)

  t.eq(registered, false)
  t.eq(status, "gendbyte-spatial load scheduled")
  t.eq(#calls.loads, 1)
  t.eq(calls.loads[1], "/tmp/gendbyte-spatial.so")
  t.eq(#calls.unbinds, 0)
  t.eq(#calls.binds, 0)
end)

t.test("spatial config keeps installed plugin declared when API is already available", function()
  local hl, calls = fake_hyprland(true)

  local registered = spatial.register(hl, {}, INSTALLED_OPTIONS)

  t.eq(registered, true)
  t.eq(#calls.loads, 1)
  t.eq(calls.loads[1], "/tmp/gendbyte-spatial.so")
  t.eq(#calls.unbinds, 7)
  t.eq(#calls.binds, 11)
end)

t.test("spatial bindings own only their explicit chords when plugin is available", function()
  local hl, calls = fake_hyprland(true)

  local registered = spatial.register(hl, {}, INSTALLED_OPTIONS)

  t.eq(registered, true)
  t.eq(#calls.unbinds, 7)
  t.eq(#calls.binds, 11)

  t.eq(calls.binds[1].keys, "SUPER + ALT + G")
  t.eq(calls.binds[2].keys, "CTRL + SUPER + G")
  t.eq(calls.binds[3].keys, "SUPER + ALT + LEFT")
  t.eq(calls.binds[4].keys, "SUPER + ALT + LEFT")
  t.eq(calls.binds[5].keys, "SUPER + ALT + RIGHT")
  t.eq(calls.binds[6].keys, "SUPER + ALT + RIGHT")
  t.eq(calls.binds[7].keys, "SUPER + ALT + UP")
  t.eq(calls.binds[8].keys, "SUPER + ALT + UP")
  t.eq(calls.binds[9].keys, "SUPER + ALT + DOWN")
  t.eq(calls.binds[10].keys, "SUPER + ALT + DOWN")
  t.eq(calls.binds[11].keys, "SUPER + ALT + 0")

  t.eq(calls.binds[1].options.description, "Toggle Spatial Desktop")
  t.eq(calls.binds[2].options.description, "Toggle Spatial Desktop (Windows fallback)")
  t.eq(calls.binds[4].options.release, true)
  t.eq(calls.binds[6].options.release, true)
  t.eq(calls.binds[8].options.release, true)
  t.eq(calls.binds[10].options.release, true)
end)

t.test("spatial binding callbacks call direct plugin Lua functions", function()
  local hl, calls = fake_hyprland(true)

  spatial.register(hl, {}, INSTALLED_OPTIONS)

  for index = 1, #calls.binds do
    calls.binds[index].callback()
  end

  t.eq(#calls.plugin, 11)
  t.eq(calls.plugin[1].name, "toggle")
  t.eq(calls.plugin[2].name, "toggle")

  t.eq(calls.plugin[3].name, "nudge")
  t.eq(calls.plugin[3].dx, -1)
  t.eq(calls.plugin[3].dy, 0)
  t.eq(calls.plugin[4].name, "brake")

  t.eq(calls.plugin[5].name, "nudge")
  t.eq(calls.plugin[5].dx, 1)
  t.eq(calls.plugin[5].dy, 0)
  t.eq(calls.plugin[6].name, "brake")

  t.eq(calls.plugin[7].name, "nudge")
  t.eq(calls.plugin[7].dx, 0)
  t.eq(calls.plugin[7].dy, -1)
  t.eq(calls.plugin[8].name, "brake")

  t.eq(calls.plugin[9].name, "nudge")
  t.eq(calls.plugin[9].dx, 0)
  t.eq(calls.plugin[9].dy, 1)
  t.eq(calls.plugin[10].name, "brake")

  t.eq(calls.plugin[11].name, "reset")
end)

t.test("spatial exact pan remains available for deterministic control", function()
  local hl, calls = fake_hyprland(true)

  local ok = spatial.pan(hl, 123, -45)

  t.eq(ok, true)
  t.eq(#calls.plugin, 1)
  t.eq(calls.plugin[1].name, "pan")
  t.eq(calls.plugin[1].dx, 123)
  t.eq(calls.plugin[1].dy, -45)
end)

t.test("spatial wrapper contains plugin callback failures", function()
  local hl = {
    plugin = {
      gendbyte_spatial = {
        toggle = function()
          error("simulated plugin error")
        end,
        pan = function() end,
        nudge = function() end,
        brake = function() end,
        reset = function() end,
      },
    },
  }

  local ok, err = spatial.toggle(hl)

  t.eq(ok, false)
  t.truthy(type(err) == "string")
  t.truthy(err:find("simulated plugin error", 1, true) ~= nil)
end)

t.test("bindings entrypoint registers spatial layer before workspace overview", function()
  local file = assert(io.open("hypr/bindings.lua", "r"))
  local source = file:read("*a")
  file:close()

  local spatial_index = assert(source:find('require("hypr.workstation.spatial")', 1, true))
  local overview_index = assert(source:find('require("hypr.workstation.workspace_overview")', 1, true))

  t.truthy(spatial_index < overview_index)
end)

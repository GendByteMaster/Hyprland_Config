local t = require("tests.testlib")
local spatial = require("hypr.workstation.spatial")

local function fake_hyprland(with_plugin)
  local calls = {
    binds = {},
    unbinds = {},
    plugin = {},
    loads = {},
  }

  local enabled_state = false

  local hl = {
    plugin = {},
  }

  function hl.plugin.load(path)
    calls.loads[#calls.loads + 1] = path
  end

  if with_plugin then
    hl.plugin.gendbyte_spatial = {}

    function hl.plugin.gendbyte_spatial.enabled()
      return enabled_state
    end

    function hl.plugin.gendbyte_spatial.toggle()
      enabled_state = not enabled_state
      calls.plugin[#calls.plugin + 1] = {
        name = "toggle",
        enabled = enabled_state,
      }
      return enabled_state
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

    function hl.plugin.gendbyte_spatial.select()
      local selected = enabled_state
      if selected then
        enabled_state = false
      end
      calls.plugin[#calls.plugin + 1] = {
        name = "select",
        selected = selected,
      }
      return selected
    end
  end

  function hl.bind(keys, callback, options)
    local handle = {
      enabled = true,
    }

    function handle:set_enabled(enabled)
      self.enabled = enabled == true
    end

    calls.binds[#calls.binds + 1] = {
      keys = keys,
      callback = callback,
      options = options or {},
      handle = handle,
    }

    return handle
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
  t.eq(#calls.unbinds, 14)
  t.eq(#calls.binds, 22)
end)

t.test("spatial bindings register native and Try Omarchy chords", function()
  local hl, calls = fake_hyprland(true)

  local registered = spatial.register(hl, {}, INSTALLED_OPTIONS)

  t.eq(registered, true)
  t.eq(#calls.unbinds, 14)
  t.eq(#calls.binds, 22)

  local expected = {
    "SUPER + ALT + G",
    "SUPER + F12",
    "SUPER + TAB",
    "SUPER + ALT + LEFT",
    "SUPER + ALT + LEFT",
    "SUPER + ALT + RIGHT",
    "SUPER + ALT + RIGHT",
    "SUPER + ALT + UP",
    "SUPER + ALT + UP",
    "SUPER + ALT + DOWN",
    "SUPER + ALT + DOWN",
    "LEFT",
    "LEFT",
    "RIGHT",
    "RIGHT",
    "UP",
    "UP",
    "DOWN",
    "DOWN",
    "SUPER + ALT + 0",
    "0",
    "mouse:272",
  }

  for index, keys in ipairs(expected) do
    t.eq(calls.binds[index].keys, keys)
  end

  t.eq(calls.binds[1].options.description, "Toggle Spatial Desktop")
  t.eq(calls.binds[2].options.description, "Toggle Spatial Desktop (Try Omarchy)")
  t.eq(calls.binds[3].options.description, "Spatial Window Overview")
  t.eq(calls.binds[22].options.description, "Select Spatial Window")
  t.eq(calls.binds[22].options.mouse, nil)

  -- Toggle bindings stay active; camera/reset/mouse-selection bindings are
  -- enabled only while Spatial mode is active.
  t.eq(calls.binds[1].handle.enabled, true)
  t.eq(calls.binds[2].handle.enabled, true)
  t.eq(calls.binds[3].handle.enabled, true)
  for index = 4, 22 do
    t.eq(calls.binds[index].handle.enabled, false)
  end

  for _, index in ipairs({5, 7, 9, 11, 13, 15, 17, 19}) do
    t.eq(calls.binds[index].options.release, true)
  end
end)

t.test("spatial toggle, selection, and HUD synchronize mode-scoped input", function()
  local hl, calls = fake_hyprland(true)
  local hud_calls = {}

  spatial.register(hl, {}, {
    plugin_path = INSTALLED_OPTIONS.plugin_path,
    file_exists = INSTALLED_OPTIONS.file_exists,
    hud = {
      show = function(enabled, zoom_percent, action)
        hud_calls[#hud_calls + 1] = {
          enabled = enabled,
          zoom_percent = zoom_percent,
          action = action,
        }
        return true
      end,
    },
  })

  t.eq(calls.binds[4].handle.enabled, false)
  calls.binds[3].callback()

  t.eq(calls.plugin[1].name, "toggle")
  t.eq(calls.plugin[1].enabled, true)
  t.eq(#hud_calls, 1)
  t.eq(hud_calls[1].enabled, true)
  t.eq(hud_calls[1].zoom_percent, 74)
  t.eq(hud_calls[1].action, "toggle")
  for index = 4, 22 do
    t.eq(calls.binds[index].handle.enabled, true)
  end

  calls.binds[12].callback()
  calls.binds[13].callback()
  t.eq(calls.plugin[2].name, "nudge")
  t.eq(calls.plugin[2].dx, -1)
  t.eq(calls.plugin[2].dy, 0)
  t.eq(calls.plugin[3].name, "brake")
  t.eq(#hud_calls, 1)

  calls.binds[21].callback()
  t.eq(calls.plugin[4].name, "reset")
  t.eq(#hud_calls, 2)
  t.eq(hud_calls[2].enabled, true)
  t.eq(hud_calls[2].action, "reset")

  local result = calls.binds[22].callback()
  t.eq(result.ok, true)
  t.eq(calls.plugin[5].name, "select")
  t.eq(calls.plugin[5].selected, true)
  t.eq(#hud_calls, 3)
  t.eq(hud_calls[3].enabled, false)
  t.eq(hud_calls[3].action, "toggle")
  for index = 4, 22 do
    t.eq(calls.binds[index].handle.enabled, false)
  end
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
        enabled = function()
          return false
        end,
        toggle = function()
          error("simulated plugin error")
        end,
        pan = function() end,
        nudge = function() end,
        brake = function() end,
        reset = function() end,
        select = function() end,
      },
    },
  }

  local ok, err = spatial.toggle(hl)

  t.eq(ok, false)
  t.truthy(type(err) == "string")
  t.truthy(err:find("simulated plugin error", 1, true) ~= nil)
end)

t.test("Spatial owns Super+Tab while legacy overview remains an explicit fallback", function()
  local file = assert(io.open("hypr/workstation/workspace_overview.lua", "r"))
  local source = file:read("*a")
  file:close()

  t.truthy(source:find('if not spatial.available(hl) then', 1, true) ~= nil)
  t.truthy(source:find('"SUPER + TAB"', 1, true) ~= nil)
  t.truthy(source:find('"Legacy Persistent Window Switcher"', 1, true) ~= nil)
end)

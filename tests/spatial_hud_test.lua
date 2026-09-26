local t = require("tests.testlib")
local hud = require("hypr.workstation.spatial_hud")

t.test("Spatial HUD sends dedicated Omarchy plugin payload", function()
  local commands = {}
  local hl = {}

  function hl.exec_cmd(command)
    table.insert(commands, command)
  end

  local client = hud.new(hl, {})
  t.truthy(client.show(true, 74, "toggle"))
  t.truthy(client.show(true, 74, "reset"))
  t.truthy(client.show(false, 74, "toggle"))

  t.eq(#commands, 3)
  t.eq(commands[1], "omarchy-shell shell summon gendbyte.spatial-hud '{\"enabled\":true,\"zoomPercent\":74,\"action\":\"toggle\"}'")
  t.eq(commands[2], "omarchy-shell shell summon gendbyte.spatial-hud '{\"enabled\":true,\"zoomPercent\":74,\"action\":\"reset\"}'")
  t.eq(commands[3], "omarchy-shell shell summon gendbyte.spatial-hud '{\"enabled\":false,\"zoomPercent\":74,\"action\":\"toggle\"}'")
end)

t.test("Spatial HUD quotes payload with provided shell helper", function()
  local commands = {}
  local hl = {}
  local o = {}

  function hl.exec_cmd(command)
    table.insert(commands, command)
  end

  function o.shell_quote(value)
    return "<" .. value .. ">"
  end

  local client = hud.new(hl, o)
  t.truthy(client.show(true, 74, "toggle"))
  t.eq(
    commands[1],
    "omarchy-shell shell summon gendbyte.spatial-hud <{\"enabled\":true,\"zoomPercent\":74,\"action\":\"toggle\"}>"
  )
end)

t.test("Spatial HUD rejects invalid payloads", function()
  local hl = { exec_cmd = function() error("must not execute") end }
  local client = hud.new(hl, {})

  t.eq(client.show("yes", 74, "toggle"), false)
  t.eq(client.show(true, 0, "toggle"), false)
  t.eq(client.show(true, 401, "toggle"), false)
  t.eq(client.show(true, 74, "other"), false)
end)

local t = require("tests.testlib")
local hud = require("hypr.workstation.hud")

t.test("HUD sends canonical Omarchy shell summon command", function()
  local commands = {}
  local hl = {}
  local o = {}

  function hl.exec_cmd(command)
    table.insert(commands, command)
  end

  function o.shell_quote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
  end

  local client = hud.new(hl, o)
  t.truthy(client.show("mouse", "RMB"))
  t.eq(#commands, 1)
  t.eq(commands[1], "omarchy-shell shell summon gendbyte.mouse-hud '{\"mode\":\"mouse\",\"button\":\"RMB\"}'")
end)

t.test("HUD quotes payload when Omarchy shell_quote helper is unavailable", function()
  local commands = {}
  local hl = {}

  function hl.exec_cmd(command)
    table.insert(commands, command)
  end

  local client = hud.new(hl, {})
  t.truthy(client.show("mouse", "LMB"))
  t.eq(#commands, 1)
  t.eq(commands[1], "omarchy-shell shell summon gendbyte.mouse-hud '{\"mode\":\"mouse\",\"button\":\"LMB\"}'")
end)

t.test("HUD rejects unsupported mode and button values", function()
  local hl = { exec_cmd = function() error("must not execute") end }
  local o = { shell_quote = function(value) return value end }
  local client = hud.new(hl, o)

  t.eq(client.show("other", "LMB"), false)
  t.eq(client.show("mouse", "OTHER"), false)
end)

t.test("HUD sends Spatial Desktop status payload", function()
  local commands = {}
  local hl = {}

  function hl.exec_cmd(command)
    table.insert(commands, command)
  end

  local client = hud.new(hl, {})
  t.truthy(client.show_spatial(true, 74, "toggle"))
  t.truthy(client.show_spatial(true, 74, "reset"))
  t.truthy(client.show_spatial(false, 74, "toggle"))

  t.eq(#commands, 3)
  t.eq(commands[1], "omarchy-shell shell summon gendbyte.mouse-hud '{\"mode\":\"spatial\",\"enabled\":true,\"zoomPercent\":74,\"action\":\"toggle\"}'")
  t.eq(commands[2], "omarchy-shell shell summon gendbyte.mouse-hud '{\"mode\":\"spatial\",\"enabled\":true,\"zoomPercent\":74,\"action\":\"reset\"}'")
  t.eq(commands[3], "omarchy-shell shell summon gendbyte.mouse-hud '{\"mode\":\"spatial\",\"enabled\":false,\"zoomPercent\":74,\"action\":\"toggle\"}'")
end)

t.test("HUD rejects invalid Spatial Desktop payloads", function()
  local hl = { exec_cmd = function() error("must not execute") end }
  local client = hud.new(hl, {})

  t.eq(client.show_spatial("yes", 74, "toggle"), false)
  t.eq(client.show_spatial(true, 0, "toggle"), false)
  t.eq(client.show_spatial(true, 74, "other"), false)
end)

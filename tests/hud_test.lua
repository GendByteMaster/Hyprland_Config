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

t.test("HUD rejects unsupported mode and button values", function()
  local hl = { exec_cmd = function() error("must not execute") end }
  local o = { shell_quote = function(value) return value end }
  local client = hud.new(hl, o)

  t.eq(client.show("other", "LMB"), false)
  t.eq(client.show("mouse", "OTHER"), false)
end)

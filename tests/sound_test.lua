local t = require("tests.testlib")
local sound = require("hypr.workstation.sound")

local function fake_hl()
  local calls = {}
  local hl = {}

  function hl.exec_cmd(command)
    table.insert(calls, command)
  end

  return hl, calls
end

t.test("Mouse Mode feedback maps on and off to distinct local UI SFX files", function()
  local hl, calls = fake_hl()
  local client = sound.new(hl, { home = "/home/test-user" })

  t.truthy(client.play_mouse_mode(true))
  t.truthy(client.play_mouse_mode(false))
  t.eq(#calls, 2)
  t.truthy(calls[1]:find("pw%-play"))
  t.truthy(calls[1]:find("toggle%-on%.ogg"))
  t.truthy(calls[2]:find("toggle%-off%.ogg"))
  t.truthy(calls[1]:find("&"))
  t.truthy(calls[2]:find("&"))
end)

t.test("sound feedback is best effort when command execution is unavailable", function()
  local client = sound.new({}, { home = "/home/test-user" })
  t.eq(client.play_mouse_mode(true), false)
end)

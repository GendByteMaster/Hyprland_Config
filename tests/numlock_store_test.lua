local t = require("tests.testlib")
local numlock_store = require("hypr.workstation.numlock_store")

local function temp_path(name)
  return "/tmp/hyprland-config-" .. name .. "-" .. tostring(os.time()) .. "-" .. tostring(math.random(100000, 999999))
end

t.test("Num Lock store builds a session-scoped runtime path", function()
  t.eq(
    numlock_store.default_path("/run/user/1000", "instance-123"),
    "/run/user/1000/hyprland-config-numlock-instance-123.state"
  )
  t.eq(numlock_store.default_path(nil, "instance-123"), nil)
  t.eq(numlock_store.default_path("/run/user/1000", nil), nil)
end)

t.test("Num Lock store saves loads and clears state", function()
  local path = temp_path("numlock")
  local store = numlock_store.new(path)

  t.eq(store.load(), nil)
  store.save(false)
  t.eq(store.load(), false)
  store.save(true)
  t.eq(store.load(), true)
  store.clear()
  t.eq(store.load(), nil)

  os.remove(path)
end)

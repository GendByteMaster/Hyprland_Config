local t = require("tests.testlib")
local mouse_state = require("hypr.workstation.mouse_state")

t.test("acceleration advances through bounded stages", function()
  local state = mouse_state.new()
  local expected = { 3, 3, 6, 6, 6, 12, 12, 12, 12, 12, 24, 24 }

  for index, step in ipairs(expected) do
    t.eq(mouse_state.next_step(state, "up"), step, "step " .. index)
  end
end)

t.test("direction counters are independent", function()
  local state = mouse_state.new()

  t.eq(mouse_state.next_step(state, "up"), 3)
  t.eq(mouse_state.next_step(state, "up"), 3)
  t.eq(mouse_state.next_step(state, "up"), 6)
  t.eq(mouse_state.next_step(state, "left"), 3)
end)

t.test("release resets only one direction", function()
  local state = mouse_state.new()

  mouse_state.next_step(state, "up")
  mouse_state.next_step(state, "up")
  mouse_state.next_step(state, "up")
  mouse_state.next_step(state, "left")
  mouse_state.next_step(state, "left")
  mouse_state.next_step(state, "left")

  mouse_state.release(state, "up")

  t.eq(mouse_state.next_step(state, "up"), 3)
  t.eq(mouse_state.next_step(state, "left"), 6)
end)

t.test("reset clears every direction", function()
  local state = mouse_state.new()

  for _ = 1, 8 do
    mouse_state.next_step(state, "up")
    mouse_state.next_step(state, "left")
  end

  mouse_state.reset(state)

  t.eq(mouse_state.next_step(state, "up"), 3)
  t.eq(mouse_state.next_step(state, "left"), 3)
end)

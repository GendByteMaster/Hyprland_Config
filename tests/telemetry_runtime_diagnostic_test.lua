local t = require("tests.testlib")

local function first_line(command)
  local pipe = assert(io.popen(command))
  local line = pipe:read("*l")
  pipe:close()
  return line
end

t.test("live collector starts and emits protocol output", function()
  local first = first_line("timeout 5s lua5.1 telemetry-collector.lua 2>&1")
  if not first or not first:match("^v1\t") then
    error("collector startup output: " .. tostring(first))
  end
end)

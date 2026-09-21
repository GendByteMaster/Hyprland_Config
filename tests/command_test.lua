local testlib = require("tests.testlib")
local test = testlib.test

test("silent argv execution redirects stdout and stderr away from protocol output", function()
  local command = require("workstation.command")
  local original_execute = os.execute
  local observed

  os.execute = function(value)
    observed = value
    return 0
  end

  local ok, err = pcall(function()
    testlib.eq(command.run_argv_silent({ "hyprctl", "dispatch", "ok" }), true)
  end)

  os.execute = original_execute
  if not ok then
    error(err)
  end

  testlib.eq(
    observed,
    "'hyprctl' 'dispatch' 'ok' >/dev/null 2>&1"
  )
end)

test("silent argv execution rejects empty argv", function()
  local command = require("workstation.command")
  testlib.eq(command.run_argv_silent({}), false)
end)

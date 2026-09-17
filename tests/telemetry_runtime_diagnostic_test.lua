local t = require("tests.testlib")

local function first_line(command)
  local pipe = assert(io.popen(command))
  local line = pipe:read("*l")
  pipe:close()
  return line
end

local function timed_status(command)
  local pipe = assert(io.popen("timeout 2s sh -c " .. string.format("%q", command) .. " >/dev/null 2>&1; printf '%s' $?"))
  local value = pipe:read("*a") or ""
  pipe:close()
  return tonumber(value)
end

local function assert_discovery_finishes(label, command)
  local status = timed_status(command)
  if status == 124 then
    error(label .. " discovery timed out")
  end
end

t.test("bounded cpu frequency discovery finishes quickly", function()
  assert_discovery_finishes(
    "cpu frequency",
    "for path in /sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_cur_freq; do [ -r \"$path\" ] && printf '%s\\n' \"$path\"; done"
  )
end)

t.test("bounded drm gpu discovery finishes quickly", function()
  assert_discovery_finishes(
    "drm gpu",
    "for path in /sys/class/drm/card[0-9]*/device/gpu_busy_percent; do [ -r \"$path\" ] && printf '%s\\n' \"$path\"; done"
  )
end)

t.test("bounded hwmon discovery finishes quickly", function()
  assert_discovery_finishes(
    "hwmon",
    "for path in /sys/class/hwmon/hwmon*/temp*_input; do [ -r \"$path\" ] && printf '%s\\n' \"$path\"; done"
  )
end)

t.test("bounded thermal discovery finishes quickly", function()
  assert_discovery_finishes(
    "thermal",
    "for path in /sys/class/thermal/thermal_zone*/temp; do [ -r \"$path\" ] && printf '%s\\n' \"$path\"; done"
  )
end)

t.test("live collector starts and emits protocol output", function()
  local first = first_line("timeout 5s lua5.1 telemetry-collector.lua 2>&1")
  if not first or not first:match("^v1\t") then
    error("collector startup output: " .. tostring(first))
  end
end)

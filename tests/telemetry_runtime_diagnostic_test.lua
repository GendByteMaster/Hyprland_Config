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
  if status ~= 0 then
    error(label .. " discovery status: " .. tostring(status))
  end
end

t.test("cpu frequency sysfs discovery finishes quickly", function()
  assert_discovery_finishes(
    "cpu frequency",
    "find -L /sys/devices/system/cpu -path '*/cpufreq/scaling_cur_freq' -type f -print"
  )
end)

t.test("drm gpu sysfs discovery finishes quickly", function()
  assert_discovery_finishes(
    "drm gpu",
    "find -L /sys/class/drm -path '*/device/gpu_busy_percent' -type f -print"
  )
end)

t.test("hwmon sysfs discovery finishes quickly", function()
  assert_discovery_finishes(
    "hwmon",
    "find -L /sys/class/hwmon -maxdepth 2 -type f -name 'temp*_input' -print"
  )
end)

t.test("thermal sysfs discovery finishes quickly", function()
  assert_discovery_finishes(
    "thermal",
    "find -L /sys/class/thermal -maxdepth 2 -type f -name temp -print"
  )
end)

t.test("live collector starts and emits protocol output", function()
  local first = first_line("timeout 5s lua5.1 telemetry-collector.lua 2>&1")
  if not first or not first:match("^v1\t") then
    error("collector startup output: " .. tostring(first))
  end
end)

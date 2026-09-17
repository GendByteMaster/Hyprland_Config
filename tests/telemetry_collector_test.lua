local t = require("tests.testlib")
local collector = require("workstation.telemetry_collector")

local function fake_io(files, candidates)
  return {
    read = function(path)
      return files[path]
    end,
    temperature_candidates = function()
      return candidates or {}
    end,
  }
end

local function read_file(path)
  local file = assert(io.open(path, "r"))
  local content = file:read("*a")
  file:close()
  return content
end

t.test("collector uses the first cpu read only as a baseline", function()
  local io_api = fake_io({
    ["/proc/stat"] = "cpu 100 0 0 100 0 0 0 0\n",
    ["/proc/meminfo"] = "MemTotal: 1000 kB\nMemAvailable: 250 kB\n",
  })

  local sample, state = collector.sample_once({}, io_api)
  t.eq(sample.cpu, nil)
  t.eq(math.floor(sample.memory + 0.5), 75)
  t.truthy(state.previous_cpu ~= nil)
end)

t.test("collector computes cpu on the second snapshot", function()
  local cpu = "cpu 100 0 0 100 0 0 0 0\n"
  local io_api = {
    read = function(path)
      if path == "/proc/stat" then return cpu end
      if path == "/proc/meminfo" then return "MemTotal: 1000 kB\nMemAvailable: 500 kB\n" end
      return nil
    end,
    temperature_candidates = function()
      return {}
    end,
  }

  local _, state = collector.sample_once({}, io_api)
  cpu = "cpu 180 0 0 120 0 0 0 0\n"
  local sample = collector.sample_once(state, io_api)
  t.eq(math.floor(sample.cpu + 0.5), 80)
end)

t.test("collector selects package temperature without making it mandatory", function()
  local with_sensor = fake_io({
    ["/proc/stat"] = "cpu 100 0 0 100 0 0 0 0\n",
    ["/proc/meminfo"] = "MemTotal: 1000 kB\nMemAvailable: 500 kB\n",
  }, {
    { path = "/sys/a", label = "Core 0", raw = "51000" },
    { path = "/sys/b", label = "Package id 0", raw = "54000" },
  })

  local sample, state = collector.sample_once({}, with_sensor)
  t.eq(math.floor(sample.temperature + 0.5), 54)
  t.eq(state.temperature_path, "/sys/b")

  local without_sensor = fake_io({
    ["/proc/stat"] = "cpu 100 0 0 100 0 0 0 0\n",
    ["/proc/meminfo"] = "MemTotal: 1000 kB\nMemAvailable: 500 kB\n",
  }, {})
  local missing = collector.sample_once({}, without_sensor)
  t.eq(missing.temperature, nil)
end)

t.test("collector executable wires sources protocol flushing and cadence", function()
  local runtime = read_file("telemetry-collector.lua")
  local core = read_file("lua/workstation/telemetry_collector.lua")
  t.truthy(core:find("/proc/stat", 1, true))
  t.truthy(core:find("/proc/meminfo", 1, true))
  t.truthy(runtime:find("/sys/class/hwmon", 1, true))
  t.truthy(runtime:find("/sys/class/thermal", 1, true))
  t.truthy(runtime:find("encode_sample", 1, true))
  t.truthy(runtime:find("io.stdout:flush()", 1, true))
  t.truthy(runtime:find("sleep 2", 1, true))
end)
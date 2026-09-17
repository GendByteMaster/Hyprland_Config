local t = require("tests.testlib")
local collector = require("workstation.telemetry_collector")

local function fake_io(files, candidates, extra)
  local api = {
    read = function(path)
      return files[path]
    end,
    temperature_candidates = function()
      return candidates or {}
    end,
  }
  for key, value in pairs(extra or {}) do api[key] = value end
  return api
end

local function near(actual, expected, epsilon)
  t.truthy(actual ~= nil)
  t.truthy(math.abs(actual - expected) <= (epsilon or 0.01))
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
    temperature_candidates = function() return {} end,
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

  local missing = collector.sample_once({}, fake_io({
    ["/proc/stat"] = "cpu 100 0 0 100 0 0 0 0\n",
    ["/proc/meminfo"] = "MemTotal: 1000 kB\nMemAvailable: 500 kB\n",
  }, {}))
  t.eq(missing.temperature, nil)
end)

t.test("collector emits cpu frequency memory size gpu and network rate", function()
  local network = [[Inter-| Receive | Transmit
 face |bytes packets errs drop fifo frame compressed multicast|bytes packets errs drop fifo colls carrier compressed
enp3s0: 1000 1 0 0 0 0 0 0 2000 1 0 0 0 0 0 0
]]
  local io_api = fake_io({
    ["/proc/stat"] = "cpu 100 0 0 100 0 0 0 0\n",
    ["/proc/meminfo"] = "MemTotal: 16777216 kB\nMemAvailable: 8388608 kB\n",
    ["/proc/net/dev"] = network,
    ["/proc/cpuinfo"] = "cpu MHz : 2800.000\ncpu MHz : 3000.000\n",
  }, {}, {
    cpu_frequencies = function() return { "3400000", "3600000" } end,
    gpu_utilization = function() return "42\n" end,
    sample_interval_seconds = 2,
  })

  local first, state = collector.sample_once({}, io_api)
  near(first.cpu_ghz, 3.5)
  near(first.memory_used_gib, 8.0)
  near(first.memory_total_gib, 16.0)
  near(first.gpu, 42.0)
  t.eq(first.network_rx_bps, nil)
  t.eq(first.network_tx_bps, nil)
  t.truthy(state.previous_network ~= nil)

  network = [[Inter-| Receive | Transmit
 face |bytes packets errs drop fifo frame compressed multicast|bytes packets errs drop fifo colls carrier compressed
enp3s0: 5000 1 0 0 0 0 0 0 10000 1 0 0 0 0 0 0
]]
  io_api.read = function(path)
    if path == "/proc/net/dev" then return network end
    if path == "/proc/stat" then return "cpu 180 0 0 120 0 0 0 0\n" end
    if path == "/proc/meminfo" then return "MemTotal: 16777216 kB\nMemAvailable: 8388608 kB\n" end
    if path == "/proc/cpuinfo" then return "cpu MHz : 2800.000\ncpu MHz : 3000.000\n" end
  end

  local second = collector.sample_once(state, io_api)
  near(second.network_rx_bps, 2000)
  near(second.network_tx_bps, 4000)
end)

t.test("collector falls back to cpuinfo frequency", function()
  local io_api = fake_io({
    ["/proc/stat"] = "cpu 100 0 0 100 0 0 0 0\n",
    ["/proc/meminfo"] = "MemTotal: 1000 kB\nMemAvailable: 500 kB\n",
    ["/proc/cpuinfo"] = "cpu MHz : 3200.000\ncpu MHz : 3600.000\n",
  }, {}, {
    cpu_frequencies = function() return {} end,
  })
  local sample = collector.sample_once({}, io_api)
  near(sample.cpu_ghz, 3.4)
end)

t.test("collector executable wires extended linux sources and fallbacks", function()
  local runtime = read_file("telemetry-collector.lua")
  local core = read_file("lua/workstation/telemetry_collector.lua")
  t.truthy(core:find("/proc/stat", 1, true))
  t.truthy(core:find("/proc/meminfo", 1, true))
  t.truthy(core:find("/proc/net/dev", 1, true))
  t.truthy(core:find("/proc/cpuinfo", 1, true))
  t.truthy(runtime:find("scaling_cur_freq", 1, true))
  t.truthy(runtime:find("gpu_busy_percent", 1, true))
  t.truthy(runtime:find("nvidia-smi", 1, true))
  t.truthy(runtime:find("/sys/class/hwmon", 1, true))
  t.truthy(runtime:find("/sys/class/thermal", 1, true))
  t.truthy(runtime:find("encode_sample", 1, true))
  t.truthy(runtime:find("io.stdout:flush()", 1, true))
  t.truthy(runtime:find("sleep 2", 1, true))
end)

t.test("collector follows sysfs class links when discovering sensors", function()
  local runtime = read_file("telemetry-collector.lua")
  t.truthy(runtime:find("find -L /sys/class/hwmon", 1, true))
  t.truthy(runtime:find("find -L /sys/class/thermal", 1, true))
  t.truthy(runtime:find("find -L /sys/class/drm", 1, true))
  t.truthy(runtime:find("find -L /sys/devices/system/cpu", 1, true))
end)

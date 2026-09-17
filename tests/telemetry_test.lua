local t = require("tests.testlib")
local telemetry = require("workstation.telemetry")

local function near(actual, expected, epsilon)
  t.truthy(actual ~= nil)
  t.truthy(math.abs(actual - expected) <= (epsilon or 0.01))
end

t.test("telemetry parses aggregate cpu counters", function()
  local snapshot = assert(telemetry.parse_cpu_stat("cpu  100 20 30 400 10 5 3 2 0 0\ncpu0 1 2 3 4\n"))
  t.eq(snapshot.total, 570)
  t.eq(snapshot.idle, 410)
end)

t.test("telemetry computes cpu usage from counter deltas", function()
  local previous = { total = 1000, idle = 700 }
  local current = { total = 1200, idle = 760 }
  near(telemetry.cpu_percent(previous, current), 70.0)
end)

t.test("telemetry rejects cpu usage without a positive total delta", function()
  t.eq(telemetry.cpu_percent(nil, { total = 100, idle = 50 }), nil)
  t.eq(telemetry.cpu_percent({ total = 100, idle = 50 }, { total = 100, idle = 50 }), nil)
  t.eq(telemetry.cpu_percent({ total = 200, idle = 100 }, { total = 150, idle = 90 }), nil)
end)

t.test("telemetry parses MemTotal and MemAvailable", function()
  local memory = assert(telemetry.parse_meminfo([[MemTotal:       16000000 kB
MemFree:         1000000 kB
MemAvailable:    4000000 kB
Buffers:          500000 kB
]]))
  t.eq(memory.total_kib, 16000000)
  t.eq(memory.available_kib, 4000000)
end)

t.test("telemetry computes memory usage from MemAvailable", function()
  near(telemetry.memory_percent({ total_kib = 16000000, available_kib = 4000000 }), 75.0)
end)

t.test("telemetry rejects incomplete or impossible memory input", function()
  t.eq(telemetry.parse_meminfo("MemTotal: 1000 kB\n"), nil)
  t.eq(telemetry.memory_percent({ total_kib = 0, available_kib = 0 }), nil)
  t.eq(telemetry.memory_percent({ total_kib = 100, available_kib = 200 }), nil)
end)

t.test("telemetry converts millidegree temperature", function()
  near(telemetry.temperature_c("54000\n"), 54.0)
  near(telemetry.temperature_c("54\n"), 54.0)
end)

t.test("telemetry rejects impossible temperature", function()
  t.eq(telemetry.temperature_c("not-a-number"), nil)
  t.eq(telemetry.temperature_c("-50000"), nil)
  t.eq(telemetry.temperature_c("250000"), nil)
end)

t.test("telemetry prefers package and cpu temperature labels", function()
  local chosen = assert(telemetry.choose_temperature({
    { path = "/sys/class/hwmon/hwmon0/temp1_input", label = "acpitz", raw = "41000" },
    { path = "/sys/class/hwmon/hwmon1/temp2_input", label = "Package id 0", raw = "54000" },
    { path = "/sys/class/hwmon/hwmon1/temp3_input", label = "Core 0", raw = "51000" },
  }))
  t.eq(chosen.path, "/sys/class/hwmon/hwmon1/temp2_input")
  near(chosen.value, 54.0)
end)

t.test("telemetry encodes a versioned sample", function()
  t.eq(
    telemetry.encode_sample({ cpu = 12.34, memory = 56.78, temperature = 54.1 }),
    "v1\tcpu=12.3\tmem=56.8\ttemp=54.1"
  )
end)

t.test("telemetry protocol preserves unavailable metrics", function()
  t.eq(
    telemetry.encode_sample({ cpu = nil, memory = 50, temperature = nil }),
    "v1\tcpu=-\tmem=50.0\ttemp=-"
  )
end)
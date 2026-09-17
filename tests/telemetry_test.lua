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

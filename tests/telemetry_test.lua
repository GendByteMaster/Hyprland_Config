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

t.test("telemetry averages cpufreq kHz as GHz", function()
  near(telemetry.cpu_frequency_ghz({ "3400000\n", "3600000\n" }), 3.5)
  near(telemetry.cpu_frequency_ghz({ "2200000", "bad", "4200000" }), 3.2)
  t.eq(telemetry.cpu_frequency_ghz({ "bad" }), nil)
end)

t.test("telemetry falls back to cpuinfo MHz for GHz", function()
  near(telemetry.cpuinfo_frequency_ghz([[processor : 0
cpu MHz : 3200.000
processor : 1
cpu MHz : 3600.000
]]), 3.4)
  t.eq(telemetry.cpuinfo_frequency_ghz("processor : 0\n"), nil)
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

t.test("telemetry exposes used and total memory in GiB", function()
  local used, total = telemetry.memory_gib({ total_kib = 16000000, available_kib = 4000000 })
  near(used, 11.4440918, 0.0001)
  near(total, 15.2587891, 0.0001)
end)

t.test("telemetry rejects incomplete or impossible memory input", function()
  t.eq(telemetry.parse_meminfo("MemTotal: 1000 kB\n"), nil)
  t.eq(telemetry.memory_percent({ total_kib = 0, available_kib = 0 }), nil)
  t.eq(telemetry.memory_percent({ total_kib = 100, available_kib = 200 }), nil)
  t.eq(telemetry.memory_gib({ total_kib = 100, available_kib = 200 }), nil)
end)

t.test("telemetry aggregates network counters without loopback", function()
  local snapshot = assert(telemetry.parse_net_dev([[Inter-|   Receive                                                |  Transmit
 face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed
    lo: 1000 1 0 0 0 0 0 0 1000 1 0 0 0 0 0 0
enp3s0: 100000 10 0 0 0 0 0 0 200000 20 0 0 0 0 0 0
 wlan0: 50000 5 0 0 0 0 0 0 30000 3 0 0 0 0 0 0
]]))
  t.eq(snapshot.rx_bytes, 150000)
  t.eq(snapshot.tx_bytes, 230000)
end)

t.test("telemetry computes network byte rates from deltas", function()
  local rx, tx = telemetry.network_bytes_per_second(
    { rx_bytes = 1000, tx_bytes = 2000 },
    { rx_bytes = 5000, tx_bytes = 6000 },
    2
  )
  near(rx, 2000)
  near(tx, 2000)
end)

t.test("telemetry rejects invalid network deltas", function()
  t.eq(telemetry.network_bytes_per_second(nil, { rx_bytes = 100, tx_bytes = 100 }, 2), nil)
  t.eq(telemetry.network_bytes_per_second({ rx_bytes = 200, tx_bytes = 200 }, { rx_bytes = 100, tx_bytes = 100 }, 2), nil)
  t.eq(telemetry.network_bytes_per_second({ rx_bytes = 100, tx_bytes = 100 }, { rx_bytes = 200, tx_bytes = 200 }, 0), nil)
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

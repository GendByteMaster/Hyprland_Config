# System Monitor Topbar v0.2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an Omarchy topbar widget that continuously shows CPU, RAM, and optional CPU temperature, and opens/focuses the existing Omarchy Activity (`btop`) window on click.

**Architecture:** Pure Lua 5.1 code parses `/proc` and `/sys` data and owns metric calculations. A single long-lived Lua collector emits a small versioned line protocol to one Omarchy `service`; one or more `bar-widget` views render the service state without starting duplicate collectors. The built-in `omarchy.bar` and `btop` remain the UI foundations.

**Tech Stack:** Omarchy 4.x/quattro shell plugins, Quickshell/QML, `Quickshell.Io.Process`, Lua 5.1, Linux `/proc`, Linux `/sys`, coreutils, existing repository Lua test harness.

**Spec:** `docs/superpowers/specs/2026-09-17-system-monitor-topbar-v0.2-design.md`

## Global Constraints

- Never modify `/usr/share/omarchy`.
- Keep the built-in `omarchy.bar`; do not clone or replace the full bar.
- Do not bind `Super + H`; preserve existing Omarchy shortcuts including `Super + Ctrl + T` for Activity.
- No privileged daemon, `sudo`, `pkexec`, Python, Rust, `lm_sensors`, or systemd service dependency.
- Telemetry collection must not run in Hyprland input callbacks.
- Missing/invalid metrics must never be represented as a healthy zero.
- CPU requires a valid delta between two snapshots; the first sample is unavailable.
- Temperature is optional and disappears when no usable CPU/package sensor exists.
- The installer must preserve the user's canonical `~/.config/omarchy/shell.json` and use Omarchy's supported plugin command to add/remove only this widget.
- Existing v0.1 Mouse Mode behavior and tests must remain green.

---

### Task 1: Pure CPU and memory telemetry core

**Files:**
- Create: `lua/workstation/telemetry.lua`
- Create: `tests/telemetry_test.lua`
- Modify: `tests/run.lua`

**Interfaces:**
- Produces: `telemetry.parse_cpu_stat(text) -> snapshot|nil`
- Produces: `telemetry.cpu_percent(previous, current) -> number|nil`
- Produces: `telemetry.parse_meminfo(text) -> memory|nil`
- Produces: `telemetry.memory_percent(memory) -> number|nil`
- `snapshot` shape: `{ total = number, idle = number }`
- `memory` shape: `{ total_kib = number, available_kib = number }`

- [ ] **Step 1: Add the telemetry test module to the existing runner before production code exists**

Append to `tests/run.lua` before `require("tests.testlib").run()`:

```lua
require("tests.telemetry_test")
```

Create `tests/telemetry_test.lua` with the first CPU parser and delta tests:

```lua
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
```

- [ ] **Step 2: Run the suite and verify RED**

Run:

```bash
lua5.1 tests/run.lua
```

Expected: failure because `workstation.telemetry` does not exist.

- [ ] **Step 3: Implement the minimal CPU parser/calculator**

Create `lua/workstation/telemetry.lua` with:

```lua
local M = {}

local function finite_number(value)
  local number = tonumber(value)
  if not number or number ~= number or number == math.huge or number == -math.huge then
    return nil
  end
  return number
end

function M.parse_cpu_stat(text)
  if type(text) ~= "string" then return nil end
  local line = text:match("^([^\n]+)")
  if not line or not line:match("^cpu%s") then return nil end

  local fields = {}
  for value in line:gmatch("(%d+)") do
    fields[#fields + 1] = tonumber(value)
  end
  if #fields < 4 then return nil end

  local total = 0
  for _, value in ipairs(fields) do total = total + value end
  local idle = fields[4] + (fields[5] or 0)
  return { total = total, idle = idle }
end

function M.cpu_percent(previous, current)
  if type(previous) ~= "table" or type(current) ~= "table" then return nil end
  local previous_total = finite_number(previous.total)
  local previous_idle = finite_number(previous.idle)
  local current_total = finite_number(current.total)
  local current_idle = finite_number(current.idle)
  if not previous_total or not previous_idle or not current_total or not current_idle then return nil end

  local total_delta = current_total - previous_total
  local idle_delta = current_idle - previous_idle
  if total_delta <= 0 or idle_delta < 0 then return nil end

  local percent = (1 - idle_delta / total_delta) * 100
  if percent < 0 then percent = 0 end
  if percent > 100 then percent = 100 end
  return percent
end

return M
```

- [ ] **Step 4: Run the suite and verify the CPU tests are GREEN**

Run:

```bash
lua5.1 tests/run.lua
```

Expected: all existing tests plus the three CPU tests pass.

- [ ] **Step 5: Add failing memory parser/calculation tests**

Add to `tests/telemetry_test.lua`:

```lua
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
```

- [ ] **Step 6: Run the suite and verify RED for missing memory functions**

Run:

```bash
lua5.1 tests/run.lua
```

Expected: failure because `parse_meminfo`/`memory_percent` are not implemented.

- [ ] **Step 7: Implement minimal memory parsing/math**

Add before `return M` in `lua/workstation/telemetry.lua`:

```lua
function M.parse_meminfo(text)
  if type(text) ~= "string" then return nil end
  local total = tonumber(text:match("MemTotal:%s+(%d+)%s+kB"))
  local available = tonumber(text:match("MemAvailable:%s+(%d+)%s+kB"))
  if not total or not available or total <= 0 or available < 0 or available > total then return nil end
  return { total_kib = total, available_kib = available }
end

function M.memory_percent(memory)
  if type(memory) ~= "table" then return nil end
  local total = finite_number(memory.total_kib)
  local available = finite_number(memory.available_kib)
  if not total or not available or total <= 0 or available < 0 or available > total then return nil end
  return ((total - available) / total) * 100
end
```

- [ ] **Step 8: Run the complete suite and commit the telemetry core**

Run:

```bash
lua5.1 tests/run.lua
find lua tests -name '*.lua' -type f -print0 | xargs -0 -n1 luac5.1 -p
```

Expected: both commands exit 0.

Commit:

```bash
git add lua/workstation/telemetry.lua tests/telemetry_test.lua tests/run.lua
git commit -m "feat(telemetry): add CPU and memory metrics"
```

---

### Task 2: Temperature ranking and versioned sample protocol

**Files:**
- Modify: `lua/workstation/telemetry.lua`
- Modify: `tests/telemetry_test.lua`

**Interfaces:**
- Consumes: Task 1 telemetry module.
- Produces: `telemetry.temperature_c(raw) -> number|nil`
- Produces: `telemetry.choose_temperature(candidates) -> candidate|nil`
- Candidate shape: `{ path = string, label = string|nil, raw = string|number }`
- Produces: `telemetry.encode_sample(sample) -> string`
- Sample shape: `{ cpu = number|nil, memory = number|nil, temperature = number|nil }`
- Protocol: `v1\tcpu=<number|->\tmem=<number|->\ttemp=<number|->`

- [ ] **Step 1: Write failing temperature tests**

Add:

```lua
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
end)
```

- [ ] **Step 2: Verify RED, then implement temperature conversion/ranking**

Run `lua5.1 tests/run.lua`; expect missing-function failure.

Add:

```lua
function M.temperature_c(raw)
  local value = finite_number(raw)
  if not value then return nil end
  if math.abs(value) >= 1000 then value = value / 1000 end
  if value < 0 or value > 150 then return nil end
  return value
end

local function temperature_priority(label)
  local normalized = string.lower(label or "")
  if normalized:find("package", 1, true) then return 1 end
  if normalized:find("tdie", 1, true) then return 1 end
  if normalized:find("tctl", 1, true) then return 1 end
  if normalized:find("cpu", 1, true) then return 2 end
  if normalized:find("core", 1, true) then return 3 end
  return 10
end

function M.choose_temperature(candidates)
  if type(candidates) ~= "table" then return nil end
  local best, best_priority
  for _, candidate in ipairs(candidates) do
    local value = M.temperature_c(candidate.raw)
    if value then
      local priority = temperature_priority(candidate.label)
      if not best or priority < best_priority then
        best = { path = candidate.path, label = candidate.label, value = value }
        best_priority = priority
      end
    end
  end
  return best
end
```

Run `lua5.1 tests/run.lua`; expect GREEN.

- [ ] **Step 3: Write failing protocol tests**

Add:

```lua
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
```

- [ ] **Step 4: Verify RED, implement `encode_sample`, verify GREEN**

Add:

```lua
local function encode_metric(value)
  if value == nil then return "-" end
  return string.format("%.1f", value)
end

function M.encode_sample(sample)
  sample = sample or {}
  return table.concat({
    "v1",
    "cpu=" .. encode_metric(sample.cpu),
    "mem=" .. encode_metric(sample.memory),
    "temp=" .. encode_metric(sample.temperature),
  }, "\t")
end
```

Run:

```bash
lua5.1 tests/run.lua
luac5.1 -p lua/workstation/telemetry.lua
```

Expected: exit 0.

Commit:

```bash
git add lua/workstation/telemetry.lua tests/telemetry_test.lua
git commit -m "feat(telemetry): add temperature and sample protocol"
```

---

### Task 3: Long-lived collector process

**Files:**
- Create: `lua/workstation/telemetry_collector.lua`
- Create: `telemetry-collector.lua`
- Create: `tests/telemetry_collector_test.lua`
- Modify: `tests/run.lua`

**Interfaces:**
- Consumes: `workstation.telemetry` from Tasks 1-2.
- Produces: `collector.sample_once(state, io_api) -> sample, new_state`
- `state` shape: `{ previous_cpu = snapshot|nil, temperature_path = string|nil }`
- `io_api` functions: `read(path) -> string|nil`, `temperature_candidates() -> candidate[]`
- Executable stdout: exactly one `v1...` protocol line per sample, flushed immediately.

- [ ] **Step 1: Add failing collector state tests**

Create `tests/telemetry_collector_test.lua`:

```lua
local t = require("tests.testlib")
local collector = require("workstation.telemetry_collector")

local function fake_io(files, candidates)
  return {
    read = function(path) return files[path] end,
    temperature_candidates = function() return candidates or {} end,
  }
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
```

Add `require("tests.telemetry_collector_test")` to `tests/run.lua` and run `lua5.1 tests/run.lua`; expect RED because the collector module does not exist.

- [ ] **Step 2: Implement minimal stateful sampling**

Create `lua/workstation/telemetry_collector.lua`:

```lua
local telemetry = require("workstation.telemetry")

local M = {}

function M.sample_once(state, io_api)
  state = state or {}
  local cpu_snapshot = telemetry.parse_cpu_stat(io_api.read("/proc/stat"))
  local memory = telemetry.parse_meminfo(io_api.read("/proc/meminfo"))
  local chosen_temperature = telemetry.choose_temperature(io_api.temperature_candidates())

  local sample = {
    cpu = telemetry.cpu_percent(state.previous_cpu, cpu_snapshot),
    memory = telemetry.memory_percent(memory),
    temperature = chosen_temperature and chosen_temperature.value or nil,
  }

  return sample, {
    previous_cpu = cpu_snapshot or state.previous_cpu,
    temperature_path = chosen_temperature and chosen_temperature.path or state.temperature_path,
  }
end

return M
```

Run `lua5.1 tests/run.lua`; expect GREEN.

- [ ] **Step 3: Add a real filesystem adapter to the executable**

Create `telemetry-collector.lua` that sets the repository Lua path exactly like the other root tools, reads files with `io.open`, enumerates hwmon temperature inputs with `find`, falls back to thermal zones when no hwmon candidates validate, calls `sample_once`, prints `telemetry.encode_sample(sample)`, flushes stdout, then sleeps two seconds using the existing Linux `sleep` coreutility.

The executable must use this loop shape:

```lua
while true do
  local sample
  sample, state = collector.sample_once(state, io_api)
  io.stdout:write(telemetry.encode_sample(sample), "\n")
  io.stdout:flush()
  os.execute("sleep 2")
end
```

The candidate enumerator must read a sibling `tempN_label` when present and return `{ path, label, raw }`; it must not fail the whole sample if `find`, a label, or a sensor read fails.

- [ ] **Step 4: Add collector source checks to tests**

Extend `tests/telemetry_collector_test.lua` with a deterministic candidate test using fake data proving `Package id 0` beats an unlabeled sensor and absence yields `temperature=nil`. Do not execute the infinite loop in unit tests; unit tests target the module, not the root executable.

- [ ] **Step 5: Run tests/syntax and commit**

```bash
lua5.1 tests/run.lua
luac5.1 -p telemetry-collector.lua
luac5.1 -p lua/workstation/telemetry_collector.lua
```

Expected: exit 0.

Commit:

```bash
git add telemetry-collector.lua lua/workstation/telemetry_collector.lua tests/telemetry_collector_test.lua tests/run.lua
git commit -m "feat(telemetry): add long-lived collector"
```

---

### Task 4: Omarchy service plugin and protocol consumer

**Files:**
- Create: `omarchy/plugins/gendbyte.system-monitor/manifest.json`
- Create: `omarchy/plugins/gendbyte.system-monitor/Service.qml`
- Create: `omarchy/plugins/gendbyte.system-monitor/ServiceHost.js`
- Create: `tests/system_monitor_plugin_test.lua`
- Modify: `tests/run.lua`

**Interfaces:**
- Consumes collector protocol from Task 3.
- Produces service properties: `cpuPercent`, `memoryPercent`, `temperatureC`, `hasCpu`, `hasMemory`, `hasTemperature`, `lastSampleAt`, `collectorHealthy`.
- Produces `ServiceHost.hostedService(bar)` resolving `bar.shell.serviceFor("gendbyte.system-monitor")`.

- [ ] **Step 1: Write failing static contract tests for manifest/service host**

Create `tests/system_monitor_plugin_test.lua` using `io.open` to read repository files and assert that:

```text
manifest id == gendbyte.system-monitor
kinds contain service and bar-widget
entryPoints.service == Service.qml
entryPoints.barWidget == BarWidget.qml
defaultSection == right
allowMultiple == false
ServiceHost.js resolves gendbyte.system-monitor
```

Register it in `tests/run.lua` and run `lua5.1 tests/run.lua`; expect RED because plugin files do not exist.

- [ ] **Step 2: Create the manifest and service host**

Create `manifest.json`:

```json
{
  "schemaVersion": 1,
  "id": "gendbyte.system-monitor",
  "name": "System Monitor",
  "version": "0.2.0",
  "author": "GendByteMaster",
  "description": "CPU, RAM and temperature summary with Activity launcher",
  "kinds": ["service", "bar-widget"],
  "entryPoints": {
    "service": "Service.qml",
    "barWidget": "BarWidget.qml"
  },
  "barWidget": {
    "displayName": "System Monitor",
    "description": "CPU, RAM and CPU temperature",
    "category": "System",
    "aliases": ["cpu", "ram", "temperature", "activity", "btop"],
    "allowMultiple": false,
    "defaultSection": "right"
  }
}
```

Create `ServiceHost.js`:

```javascript
function hostedService(bar) {
  var shell = bar ? bar.shell : null
  if (!shell || typeof shell.serviceFor !== "function") return null
  return shell.serviceFor("gendbyte.system-monitor") || null
}

if (typeof module !== "undefined") {
  module.exports = { hostedService: hostedService }
}
```

- [ ] **Step 3: Implement `Service.qml` as the single collector owner**

Use `Quickshell.Io.Process` with:

```qml
Process {
  id: collector
  command: ["lua5.1", Quickshell.env("HOME") + "/.config/omarchy/plugins/gendbyte.system-monitor/telemetry-collector.lua"]
  running: true
  stdout: SplitParser { onRead: function(line) { root.acceptSample(line) } }
  onStarted: root.collectorHealthy = true
  onExited: function(exitCode) {
    root.collectorHealthy = false
    restartTimer.restart()
  }
}
```

Because the collector implementation lives at repository root, the plugin directory must contain a symlink-safe wrapper `telemetry-collector.lua` or the installer must expose the root collector at that exact path. Use the first option: create `omarchy/plugins/gendbyte.system-monitor/telemetry-collector.lua` as a tiny Lua launcher that resolves the repository root through the plugin symlink path and executes/loads the real collector without copying logic. Keep all parser/calculation logic under `lua/workstation/`.

`acceptSample(line)` must reject non-`v1` lines, parse `cpu=`, `mem=`, and `temp=`, treat `-` as unavailable, update `lastSampleAt = new Date()`, and set `collectorHealthy = true`. It must never coerce malformed text to zero.

Use a bounded restart timer of 5 seconds; one unexpected exit produces at most one restart attempt per timer fire, not a tight loop.

- [ ] **Step 4: Add static assertions for collector command and protocol safeguards**

Extend `tests/system_monitor_plugin_test.lua` to assert the service source contains `SplitParser`, `v1`, `collectorHealthy`, and the fixed plugin-local collector path. This does not replace live QML validation; it prevents accidental contract drift in generic CI.

- [ ] **Step 5: Run tests, Lua syntax, and Omarchy plugin validation where available**

```bash
lua5.1 tests/run.lua
find . -name '*.lua' -type f -print0 | xargs -0 -n1 luac5.1 -p
omarchy plugin validate ./omarchy/plugins/gendbyte.system-monitor
```

The first two commands must pass in CI. The third is required on the live Omarchy machine; if `omarchy` is unavailable in generic CI, verifier reports it as a live-environment check rather than silently pretending validation occurred.

Commit:

```bash
git add omarchy/plugins/gendbyte.system-monitor tests/system_monitor_plugin_test.lua tests/run.lua
git commit -m "feat(omarchy): add system monitor service plugin"
```

---

### Task 5: Topbar widget and Activity launcher

**Files:**
- Create: `omarchy/plugins/gendbyte.system-monitor/BarWidget.qml`
- Modify: `tests/system_monitor_plugin_test.lua`

**Interfaces:**
- Consumes hosted service from Task 4.
- Produces horizontal text `CPU <n>% · RAM <n>% · <n>°C` with unavailable parts omitted/placeholder rules from spec.
- Left click runs `omarchy-launch-or-focus-tui btop`.

- [ ] **Step 1: Write failing widget contract tests**

Add static tests asserting `BarWidget.qml` contains:

```text
BarWidget
ServiceHost.hostedService(bar)
omarchy-launch-or-focus-tui
btop
showTooltip
hideTooltip
```

Run `lua5.1 tests/run.lua`; expect RED because `BarWidget.qml` is absent.

- [ ] **Step 2: Implement a presentation-only bar widget**

Base it on Omarchy's `BarWidget` API and theme properties. The widget must:

```qml
readonly property string cpuText: service.hasCpu ? "CPU " + Math.round(service.cpuPercent) + "%" : "CPU --%"
readonly property string memoryText: service.hasMemory ? "RAM " + Math.round(service.memoryPercent) + "%" : "RAM --%"
readonly property string temperatureText: service.hasTemperature ? Math.round(service.temperatureC) + "°C" : ""
readonly property string summaryText: temperatureText.length > 0
  ? cpuText + " · " + memoryText + " · " + temperatureText
  : cpuText + " · " + memoryText
```

Use `Text` with `bar.barForeground`/`bar.fontFamily` fallbacks and `Style.font.body`; do not hard-code colors.

Add a `MouseArea` whose left click starts a `Process` with:

```qml
command: ["omarchy-launch-or-focus-tui", "btop"]
```

Hover calls:

```qml
root.bar.showTooltip(root, "Open Activity (btop)")
root.bar.hideTooltip(root)
```

When `vertical` is true, render a compact system glyph instead of the long summary so moving the Omarchy bar to a side does not create an unusable vertical label.

- [ ] **Step 3: Run tests and commit**

```bash
lua5.1 tests/run.lua
```

Expected: GREEN.

Commit:

```bash
git add omarchy/plugins/gendbyte.system-monitor/BarWidget.qml tests/system_monitor_plugin_test.lua
git commit -m "feat(omarchy): show telemetry in topbar"
```

---

### Task 6: Safe install, enable, verify, and uninstall integration

**Files:**
- Modify: `lua/workstation/installer.lua`
- Modify: `lua/workstation/uninstaller.lua`
- Modify: `lua/workstation/verifier.lua`
- Modify: `tests/installer_test.lua`
- Modify: `tests/uninstaller_test.lua`
- Modify: `tests/verifier_test.lua`

**Interfaces:**
- New managed plugin id: `gendbyte.system-monitor`.
- Installer links `<repo>/omarchy/plugins/gendbyte.system-monitor` to `~/.config/omarchy/plugins/gendbyte.system-monitor`.
- Installer enables placement with `omarchy plugin enable gendbyte.system-monitor --section right` through an injectable runtime.
- Uninstaller disables only `gendbyte.system-monitor` before removing its managed symlink.

- [ ] **Step 1: Extend fake repositories and write failing installer tests**

Update each test helper that creates a fake repository so it also creates:

```text
omarchy/plugins/gendbyte.system-monitor/manifest.json
omarchy/plugins/gendbyte.system-monitor/Service.qml
omarchy/plugins/gendbyte.system-monitor/BarWidget.qml
omarchy/plugins/gendbyte.system-monitor/ServiceHost.js
```

Add tests proving:

1. fresh install creates the system-monitor plugin link;
2. second install remains idempotent;
3. an occupied unrelated system-monitor plugin path is refused;
4. enabling is invoked exactly once for a newly linked plugin;
5. no test rewrites a fake `shell.json` directly.

Use an injected runtime object:

```lua
local calls = {}
local omarchy_runtime = {
  available = function() return true end,
  enable_plugin = function(id, section)
    calls[#calls + 1] = { action = "enable", id = id, section = section }
    return true
  end,
  disable_plugin = function(id)
    calls[#calls + 1] = { action = "disable", id = id }
    return true
  end,
}
```

Pass it as `installer.install({ ..., omarchy_runtime = omarchy_runtime })`.

Run `lua5.1 tests/run.lua`; expect RED.

- [ ] **Step 2: Implement the installer runtime boundary**

Add a default runtime whose production implementation uses `command.command_exists("omarchy")` and `command.run` with quoted arguments. The installer must fail with a clear message if the plugin was newly linked but Omarchy CLI is unavailable, because a silently unplaced widget would violate v0.2 install semantics.

On rollback after an enable failure, remove only the system-monitor link created by this install and restore the same pre-install state used by existing rollback logic.

Do not edit `~/.config/omarchy/shell.json` directly.

- [ ] **Step 3: Write failing uninstall ownership/disable tests, then implement**

Tests must prove:

- uninstall refuses to remove a replaced system-monitor link;
- successful uninstall calls `disable_plugin("gendbyte.system-monitor")` before removing the managed link;
- existing HUD removal/restoration semantics remain unchanged.

Then update `uninstaller.lua` with the same injectable runtime boundary.

- [ ] **Step 4: Write failing verifier tests, then implement plugin checks**

Verifier must check:

```text
system monitor manifest exists
Service.qml exists
BarWidget.qml exists
ServiceHost.js exists
telemetry collector entry exists
managed plugin symlink points to repository plugin
omarchy CLI exists for live validation
```

Keep generic Lua syntax validation intact. Do not claim QML runtime correctness from static file existence.

- [ ] **Step 5: Run the full suite and commit install integration**

```bash
lua5.1 tests/run.lua
find . -name '*.lua' -type f -print0 | xargs -0 -n1 luac5.1 -p
```

Expected: exit 0.

Commit:

```bash
git add lua/workstation/installer.lua lua/workstation/uninstaller.lua lua/workstation/verifier.lua tests/installer_test.lua tests/uninstaller_test.lua tests/verifier_test.lua
git commit -m "feat(install): manage system monitor plugin"
```

---

### Task 7: Documentation, CI evidence, and live Omarchy acceptance

**Files:**
- Modify: `README.md`
- Modify: `docs/superpowers/specs/2026-09-17-system-monitor-topbar-v0.2-design.md` only if implementation proves a documented assumption wrong.

**Interfaces:**
- Documents final user-visible behavior and verification commands.

- [ ] **Step 1: Update README v0.2 documentation**

Document exactly:

```text
Topbar: CPU <n>% · RAM <n>% · <n>°C (temperature omitted when unavailable)
Left click: open/focus Omarchy Activity (btop)
Existing hotkey: Super + Ctrl + T
Collector cadence: 2 seconds
No sudo/systemd/lm_sensors requirement
```

Add `gendbyte.system-monitor` to the repository layout/install ownership section.

- [ ] **Step 2: Run complete automated verification**

```bash
lua5.1 tests/run.lua
find . -name '*.lua' -type f -print0 | xargs -0 -n1 luac5.1 -p
lua5.1 verify.lua
```

Expected: all automated checks pass on an installed test environment. Do not report success if any command fails.

- [ ] **Step 3: Run live Omarchy acceptance checks**

On Omarchy:

```bash
omarchy plugin validate ./omarchy/plugins/gendbyte.system-monitor
lua5.1 reinstall.lua
omarchy plugin list
hyprctl configerrors
```

Then visually verify:

```text
CPU and RAM appear in topbar
temperature appears when a usable sensor exists
first CPU sample does not falsely show 0%
clicking widget opens/focuses the same btop Activity window
Super + Ctrl + T still works
Num Lock Mouse Mode still works
moving the bar to a vertical edge gives compact widget rendering
```

- [ ] **Step 4: Commit docs/evidence state**

```bash
git add README.md docs/superpowers/specs/2026-09-17-system-monitor-topbar-v0.2-design.md
git commit -m "docs: document system monitor topbar v0.2"
```

If the spec did not need correction, omit it from `git add`.

- [ ] **Step 5: Final branch verification before PR**

Run the full suite again after the documentation commit and inspect the branch diff against `main`. Only then create the v0.2 PR.

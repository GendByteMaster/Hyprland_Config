# System Monitor Topbar v0.2 Design

## Goal

Add lightweight workstation telemetry to the Omarchy top bar without building a second system-monitoring application.

v0.2 keeps `btop`/Omarchy Activity as the detailed monitor and adds an always-visible summary such as:

```text
CPU 18% 3.4GHz · RAM 20% 6.2/31.3GB · GPU 24% · ↓1.2MB/s ↑340KB/s · 54°C
```

Left-clicking the widget launches or focuses the existing Omarchy `btop` Activity window.

## Decision

v0.2 is a native third-party Omarchy shell plugin with two kinds:

- `service` — owns telemetry collection and normalized state;
- `bar-widget` — renders the topbar summary and opens Activity.

We do not replace `omarchy.bar`, clone the full bar, create a second monitoring dashboard, or bind `Super + H`.

Custom files remain under the user's configuration boundary. `/usr/share/omarchy` is never modified.

## User experience

### Horizontal top bar

The widget renders available metrics in this order:

```text
CPU <usage>% [<GHz>GHz] · RAM <usage>% [<used>/<total>GB] · [GPU <usage>%] · [↓<RX>/s ↑<TX>/s] · [<temp>°C]
```

Example:

```text
CPU 18% 3.4GHz · RAM 20% 6.2/31.3GB · GPU 24% · ↓1.2MB/s ↑340KB/s · 54°C
```

Rules:

- CPU and RAM utilization remain the primary metrics.
- CPU frequency is shown when a valid current frequency can be read.
- RAM used/total is shown in GiB, displayed with the compact `GB` label.
- GPU utilization is optional and omitted when no supported source is available.
- Network RX/TX is calculated from byte-counter deltas and omitted until a valid second sample exists.
- CPU/package temperature is optional and omitted when no valid sensor is available.
- Missing optional metrics never render as healthy zeroes.
- Before the first valid CPU delta, CPU renders as `CPU --%`.
- Styling uses Omarchy bar/theme properties rather than hard-coded colors.
- The widget defaults to the `right` bar section and remains movable through normal Omarchy controls.
- Vertical bar mode stays compact and does not attempt to render the full horizontal summary.

### Interaction

- **Left click:** run `omarchy-launch-or-focus-tui btop`.
- **Hover:** show the current summary and indicate when telemetry is unavailable.
- Existing Omarchy Activity shortcuts remain untouched.
- No custom right-click menu is required for v0.2.

The widget is a launcher/summary, not an alternative process manager.

## Architecture

```text
Omarchy / Quickshell
└─ omarchy.bar
   └─ gendbyte.system-monitor (bar-widget)
      └─ hosted gendbyte.system-monitor service
         └─ one long-lived Lua collector
            ├─ /proc/stat                         -> CPU utilization
            ├─ /sys/devices/system/cpu/...       -> CPU frequency
            │   └─ /proc/cpuinfo fallback
            ├─ /proc/meminfo                      -> RAM usage + GiB
            ├─ /proc/net/dev                      -> RX/TX counters
            ├─ /sys/class/drm/...gpu_busy_percent -> GPU utilization
            │   └─ nvidia-smi fallback when installed
            └─ /sys/class/hwmon + thermal         -> CPU temperature

left click
   └─ omarchy-launch-or-focus-tui btop
      └─ existing Omarchy Activity window
```

Repository ownership:

```text
omarchy/plugins/gendbyte.system-monitor/
├── manifest.json
├── Service.qml
├── ServiceHost.js
├── BarWidget.qml
└── telemetry-collector.lua

lua/workstation/
├── telemetry.lua
└── telemetry_collector.lua

telemetry-collector.lua

tests/
├── telemetry_test.lua
├── telemetry_collector_test.lua
└── system_monitor_plugin_test.lua
```

## Telemetry model

### Pure parsing/calculation layer

`lua/workstation/telemetry.lua` owns deterministic parsing and calculations:

- aggregate CPU counters and CPU delta utilization;
- average CPU frequency from `scaling_cur_freq` values;
- `/proc/cpuinfo` MHz fallback parsing;
- `MemTotal`/`MemAvailable`, memory percentage, used/total GiB;
- `/proc/net/dev` aggregation excluding `lo`;
- network byte rates from two samples and elapsed time;
- GPU percentage validation;
- temperature conversion/source selection;
- versioned sample serialization.

Malformed or impossible values are rejected instead of coerced to zero.

### Stateful collector core

`lua/workstation/telemetry_collector.lua` keeps only the state required between samples:

- previous CPU counters;
- previous network byte counters;
- selected temperature source metadata.

It produces one normalized sample with these fields:

```text
cpu
cpu_ghz
memory
memory_used_gib
memory_total_gib
gpu
network_rx_bps
network_tx_bps
temperature
```

### Linux runtime collector

The root `telemetry-collector.lua` owns OS source discovery and I/O.

It:

- samples every 2 seconds;
- reads CPU/RAM/network data from `/proc`;
- discovers CPU frequency files under cpufreq sysfs and falls back to `/proc/cpuinfo`;
- discovers DRM `gpu_busy_percent` first and falls back to `nvidia-smi` only when that command already exists;
- discovers CPU temperature under hwmon first, then thermal zones;
- flushes one versioned line to stdout per sample;
- is non-privileged and not installed as a systemd service.

The collector is launched with a parent-death signal so it does not remain orphaned when the Omarchy shell exits.

## Protocol

The protocol remains key-based and versioned as `v1`:

```text
v1\tcpu=12.3\tcpu_ghz=3.4\tmem=56.8\tmem_used_gib=6.2\tmem_total_gib=31.3\tgpu=24.0\tnet_rx_bps=1258291.2\tnet_tx_bps=348160.0\ttemp=54.1
```

Unavailable fields use `-`.

`Service.qml` parses by key rather than field position, keeping the protocol tolerant of optional metrics.

## Metric semantics

### CPU utilization

Source: aggregate `cpu` line in `/proc/stat`.

Utilization is calculated from the delta between consecutive total/idle snapshots. The first sample establishes a baseline.

### CPU frequency

Primary source: available `scaling_cur_freq` files under `/sys/devices/system/cpu/.../cpufreq/`.

The displayed value is the average of valid current per-CPU frequencies converted from kHz to GHz.

Fallback: average valid `cpu MHz` values from `/proc/cpuinfo`.

### Memory

Source: `/proc/meminfo`.

```text
used = MemTotal - MemAvailable
usagePercent = used / MemTotal * 100
usedGiB = usedKiB / 1024 / 1024
totalGiB = totalKiB / 1024 / 1024
```

`MemAvailable` is preferred over `MemFree`.

### Network

Source: `/proc/net/dev`.

All non-loopback interfaces are aggregated. RX/TX rates are derived from counter deltas over the collector interval. Counter rollback or invalid elapsed time makes the sample unavailable rather than negative.

### GPU

Primary source: DRM sysfs `device/gpu_busy_percent` when exposed by the active Linux driver.

Fallback: `nvidia-smi --query-gpu=utilization.gpu` when `nvidia-smi` is already installed.

GPU support is best-effort. No new GPU vendor package is installed by this project.

### Temperature

Primary source: `/sys/class/hwmon/hwmon*/temp*_input`, preferring CPU/package labels.

Fallback: `/sys/class/thermal/thermal_zone*/temp`.

Temperature is optional.

## Service and stale-data model

`Service.qml` is the single collector owner and exposes normalized properties including:

```text
cpuPercent
cpuGhz
memoryPercent
memoryUsedGib
memoryTotalGib
gpuPercent
networkRxBps
networkTxBps
temperatureC
hasCpu
hasCpuFrequency
hasMemory
hasMemorySize
hasGpu
hasNetwork
hasTemperature
lastSampleAt
collectorHealthy
```

The service restarts the collector after unexpected exit and uses a 7-second stale watchdog. If samples stop arriving, all `has*` availability flags are cleared so old values are not presented as live telemetry.

One missing metric does not invalidate the others.

## `BarWidget.qml`

The bar widget is presentation-only:

- reads the hosted singleton service;
- formats CPU usage/frequency, RAM percentage/size, optional GPU, optional network rates, and optional temperature;
- formats network rates as B/s, KB/s, or MB/s;
- follows Omarchy bar theme/font/spacing;
- uses compact vertical mode;
- launches/focuses `btop` on left click;
- performs no `/proc` or `/sys` parsing and starts no collector.

Multiple rendered bar instances therefore share one data collector.

## Installation ownership

The installer manages the repository-owned plugin link:

```text
~/.config/omarchy/plugins/gendbyte.system-monitor
```

Plugin placement/enabling uses the Omarchy plugin interface rather than replacing the user's `shell.json` or cloning the first-party bar.

Uninstall disables the plugin before removing its managed link and refuses to remove paths that are no longer owned by this installation.

## Testing strategy

Pure Lua tests cover:

- CPU counters, delta math, current frequency and fallback;
- RAM percentage and GiB calculations;
- network aggregation/rate calculation;
- GPU percentage parsing and invalid values;
- temperature conversion/source selection;
- extended `v1` serialization;
- stateful collector behavior and fallbacks.

Plugin/static tests cover:

- manifest/service/bar entry points;
- extended service properties and protocol keys;
- stale-data invalidation;
- topbar labels and Activity launcher;
- plugin-local collector handoff.

Installer/uninstaller/verifier tests protect ownership and Omarchy plugin lifecycle.

Live visual behavior still requires an actual Omarchy/Quickshell session because generic CI has no Hyprland desktop.

## Non-goals for v0.2

- no replacement for `btop`;
- no process list or process-management UI;
- no popup/full-screen monitoring dashboard;
- no disk graphs or network history graphs;
- no GPU graphs or vendor-specific control UI;
- no threshold alerts/notifications;
- no background systemd daemon;
- no `Super + H` binding;
- no replacement or clone of `omarchy.bar`;
- no installation of `lm_sensors`, NVIDIA utilities, or other heavy telemetry dependencies.

## Definition of done

v0.2 is complete when:

1. CPU usage and current GHz are visible when available.
2. RAM usage percentage and used/total GiB are visible.
3. GPU utilization appears when a supported source exists and disappears gracefully otherwise.
4. Network RX/TX rates appear after a valid delta sample and exclude loopback traffic.
5. CPU temperature appears when a valid sensor exists.
6. Stale telemetry is invalidated rather than displayed indefinitely.
7. Left click opens or focuses Omarchy Activity (`btop`).
8. Collection stays non-privileged, lightweight, and outside Hyprland input callbacks.
9. Installer/uninstaller preserve Omarchy bar ownership and unrelated user configuration.
10. Lua tests, plugin tests, installer tests, and syntax checks remain green.
11. The plugin validates and is visually checked in a live Omarchy session.

## Upstream references

- Omarchy `manual/32-shell-plugins.md` — plugin kinds, third-party plugin location, validation and lifecycle.
- Omarchy `manual/05-the-top-bar.md` — bar layout, sections and widget management.
- Omarchy `manual/21-tuis.md` and `default/hypr/bindings/utilities.lua` — Activity/btop behavior.
- Omarchy `bin/omarchy-launch-or-focus-tui` — launch-or-focus wrapper for TUI applications.

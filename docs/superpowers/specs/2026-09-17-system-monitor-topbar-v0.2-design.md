# System Monitor Topbar v0.2 Design

## Goal

Add lightweight workstation telemetry to the Omarchy top bar without building a second system-monitoring application.

v0.2 keeps `btop`/Omarchy Activity as the detailed monitor and adds a small always-visible summary in the bar:

```text
CPU 12% · RAM 38% · 54°C
```

Left-clicking the widget launches or focuses the existing Omarchy `btop` Activity window.

## Decision

v0.2 is a native third-party Omarchy shell plugin with two kinds:

- `service` — owns telemetry collection and normalized state;
- `bar-widget` — renders the compact topbar summary and opens Activity.

We will not replace `omarchy.bar`, clone the full bar, create a second dashboard, or bind `Super + H`.

This follows Omarchy's supported plugin boundary: custom plugins live under `~/.config/omarchy/plugins/`, `bar-widget` components can be placed in the active bar, and the built-in bar remains the owner of layout, theme, drag/reorder behavior, and multi-monitor rendering.

## User experience

### Horizontal top bar

Default presentation:

```text
CPU 12% · RAM 38% · 54°C
```

Rules:

- CPU and RAM are always shown when valid samples exist.
- Temperature is shown only when a usable CPU/package sensor is available.
- Before the first valid CPU delta sample, CPU renders as `CPU --%` rather than reporting a false zero.
- If one metric becomes stale or unavailable, the remaining valid metrics continue to render.
- Values use integer display precision in the bar; detailed precision belongs in `btop`.
- Styling uses Omarchy bar/theme properties rather than hard-coded colors.
- The widget defaults to the `right` bar section and remains movable through normal Omarchy bar controls.

### Interaction

- **Left click:** run `omarchy-launch-or-focus-tui btop`, which uses Omarchy's normal `org.omarchy.btop` app id and focuses an existing Activity window when one already exists.
- **Hover:** show a concise tooltip such as `Open Activity (btop)` plus the last refresh age when useful.
- No custom right-click menu is required for v0.2.
- Existing `Super + Ctrl + T` Activity behavior remains untouched.

The widget is a launcher/summary, not an alternative process manager.

## Architecture

```text
Omarchy / Quickshell
└─ omarchy.bar
   └─ gendbyte.system-monitor (bar-widget)
      └─ hosted gendbyte.system-monitor service
         └─ telemetry collector process
            ├─ /proc/stat       -> CPU utilization
            ├─ /proc/meminfo    -> memory utilization
            └─ /sys/...         -> CPU/package temperature

left click
   └─ omarchy-launch-or-focus-tui btop
      └─ existing Omarchy Activity window
```

Proposed repository layout:

```text
omarchy/plugins/gendbyte.system-monitor/
├── manifest.json
├── Service.qml
├── BarWidget.qml
└── ServiceHost.js

lua/workstation/
└── telemetry.lua

tests/
└── telemetry_test.lua
```

### `telemetry.lua`

The Lua module owns parsing and metric calculations so the data logic is deterministic and testable outside a live Quickshell session.

Responsibilities:

- parse aggregate CPU counters from `/proc/stat`;
- calculate CPU utilization from two consecutive counter snapshots;
- parse `MemTotal` and `MemAvailable` from `/proc/meminfo` and calculate used-memory percentage;
- discover a CPU/package temperature source under `/sys/class/hwmon/` first, with `/sys/class/thermal/` as a fallback;
- reject malformed, impossible, or missing values rather than coercing them to zero;
- emit a small machine-readable sample for the shell service.

No `lm_sensors`, Python, Rust, privileged helper, `/dev/uinput`, `sudo`, or `pkexec` dependency is introduced.

### Telemetry process

CPU percentage requires state across samples, so v0.2 uses one long-lived lightweight Lua collector process instead of spawning a new process for every refresh.

The collector:

- is started and owned by the Omarchy plugin service;
- exits with the service/shell lifecycle and is not installed as a systemd daemon;
- samples at a conservative default interval of 2 seconds;
- emits one compact line per sample;
- never runs in Hyprland input callbacks;
- treats individual metric failures as partial data, not fatal process errors.

The output protocol is deliberately simple and versioned so `Service.qml` does not need to understand `/proc` or `/sys` formats.

### `Service.qml`

The service owns the collector process and exposes normalized properties to the widget:

```text
cpuPercent
memoryPercent
temperatureC
hasCpu
hasMemory
hasTemperature
lastSampleAt
collectorHealthy
```

It is the only QML component that talks to the collector. Restart/backoff logic belongs here.

If the collector exits unexpectedly, the service may restart it with bounded backoff. The bar must remain usable while telemetry is unavailable.

### `BarWidget.qml`

The bar widget is presentation-only:

- reads the hosted service state;
- formats the compact label;
- follows the active Omarchy bar theme/font/spacing;
- adapts to unavailable metrics;
- launches/focuses `btop` on left click;
- performs no `/proc` parsing and no polling itself.

This separation prevents one bar instance per monitor from starting duplicate collectors: the service is the singleton data owner while each rendered bar widget is only a view.

## Metric semantics

### CPU

Source: aggregate `cpu` line in `/proc/stat`.

CPU utilization is calculated from the delta between two consecutive total/idle counter snapshots. The first sample establishes a baseline and is not presented as a real percentage.

Values are clamped only after a valid calculation to the display range `0..100` to tolerate small counter/race anomalies; malformed counter sets are rejected.

### Memory

Source: `/proc/meminfo`.

```text
used = MemTotal - MemAvailable
usagePercent = used / MemTotal * 100
```

`MemAvailable` is preferred over `MemFree` because it better represents memory that can be reclaimed for applications.

### Temperature

Primary source: `/sys/class/hwmon/hwmon*/temp*_input`, preferring labels that identify CPU package/control temperature when available.

Fallback: `/sys/class/thermal/thermal_zone*/temp` when no suitable hwmon source exists.

Temperature is optional. Systems without an exposed CPU sensor simply omit the temperature token from the bar. Sensor absence is not an error state.

## Failure and stale-data model

The widget must never display missing data as a healthy `0`.

- collector starting: placeholders for metrics that need a baseline;
- one metric invalid: omit or placeholder only that metric;
- temperature unavailable: omit temperature;
- collector disconnected: keep the last valid sample briefly and mark it stale internally;
- prolonged collector failure: render a compact unavailable state rather than blocking or repeatedly spawning processes;
- `btop` launch failure: telemetry continues; the click action fails independently.

No telemetry failure may affect Mouse Mode, Hyprland bindings, the Omarchy shell bar, or install/uninstall correctness.

## Installation ownership

v0.2 extends the existing installer only for repository-owned files.

It manages a symlink for:

```text
~/.config/omarchy/plugins/gendbyte.system-monitor
```

The plugin is then enabled/placed through the supported Omarchy plugin/bar interface rather than by copying or modifying first-party shell files.

The installer must preserve the user's existing canonical `~/.config/omarchy/shell.json`; it must not replace the whole bar layout just to add this widget.

Uninstall removes only this project's managed plugin link/state and must not reset unrelated bar customization.

## Testing strategy

### Pure Lua tests

`tests/telemetry_test.lua` covers:

- `/proc/stat` parsing;
- CPU delta math including first-sample behavior and counter edge cases;
- `/proc/meminfo` parsing and memory percentage math;
- temperature unit conversion and source selection;
- malformed/missing input handling;
- sample serialization protocol.

Tests use fixtures/strings and temporary directories; CI does not depend on the runner's real sensor layout.

### Integration/static verification

Verification checks:

- plugin manifest schema and required entry points;
- Lua 5.1 syntax/tests;
- QML/plugin files exist in the installed target;
- no project file modifies `/usr/share/omarchy`;
- installer/uninstaller ownership remains safe.

Live visual behavior and click-to-Activity are validated on Omarchy because generic CI does not provide its Quickshell/Hyprland desktop session.

## Non-goals for v0.2

- no replacement for `btop`;
- no process list or process-management UI;
- no full-screen or popup monitoring dashboard;
- no GPU telemetry in the first v0.2 slice;
- no disk/network graphs in the topbar;
- no alerts/notifications based on thresholds;
- no background systemd service;
- no `Super + H` binding;
- no replacement or clone of `omarchy.bar`.

Disk/network/GPU summaries can be considered later only if real use shows the compact bar needs them. `btop` remains the detailed source of truth.

## Compatibility boundary

The design intentionally uses documented Omarchy extension points rather than internal bar replacement:

- Omarchy shell plugins support `service` and `bar-widget` kinds;
- third-party plugins belong in `~/.config/omarchy/plugins/`;
- the built-in bar owns three movable sections and widget configuration;
- Omarchy already ships `btop` as Activity and binds it to `Super + Ctrl + T`;
- Omarchy provides `omarchy-launch-or-focus-tui`, which can focus an existing TUI window or launch it with the normal TUI launcher.

If a future Omarchy release changes private QML internals, the plugin should adapt at its small service-host boundary without requiring changes to telemetry parsing or the rest of Hyprland_Config.

## Definition of done

v0.2 is complete when:

1. CPU and RAM are continuously visible in the Omarchy topbar, with temperature when available.
2. The widget does not duplicate the detailed `btop` interface.
3. Left click opens or focuses Omarchy Activity (`btop`).
4. Telemetry collection is non-privileged, lightweight, and isolated from Hyprland input callbacks.
5. Missing sensors and collector failures degrade gracefully without false zero readings.
6. The installer safely adds/removes the plugin without replacing the user's bar configuration.
7. Pure telemetry logic is covered by Lua tests and existing v0.1 tests remain green.
8. The plugin validates against the supported Omarchy plugin model and works in a live Omarchy session.

## Upstream references

- Omarchy `manual/32-shell-plugins.md` — plugin kinds, third-party plugin location, validation and lifecycle.
- Omarchy `manual/05-the-top-bar.md` — bar layout, sections and widget management.
- Omarchy `manual/21-tuis.md` and `default/hypr/bindings/utilities.lua` — Activity/btop behavior and `Super + Ctrl + T`.
- Omarchy `bin/omarchy-launch-or-focus-tui` — supported launch-or-focus wrapper for TUI applications.
- `basecamp/omarchy-basecamp-plugin` — current service + bar-widget third-party plugin precedent.

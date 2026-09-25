# Developer Spatial Desktop — Phase 1 Architecture

Status: Proposed implementation baseline for Issue #24  
Branch: `feat/issue-24-developer-spatial-desktop`  
Target baseline: Hyprland 0.56.x, validated first against 0.56.2  
Reference only: https://github.com/kaolti/phantomat

## 1. Goal

Phase 1 proves the minimum compositor-side model required for a future project-aware spatial desktop without replacing the existing Hyprland workstation.

The deliverable is an **opt-in spatial core MVP** that can:

- load and unload safely as a Hyprland plugin;
- track a bounded set of managed windows;
- assign stable-for-session world rectangles;
- maintain a camera in world coordinates;
- pan the camera at `zoom = 1.0`;
- expose read-only machine-readable state;
- enter and leave spatial mode without corrupting the normal Hyprland session;
- fail closed when the plugin build does not match the running Hyprland build.

Phase 1 is intentionally not a visual showcase. It exists to validate coordinate semantics, lifecycle, compatibility, and testability before render-level zoom is attempted.

## 2. Hard constraints

### 2.1 Spatial mode is optional

Normal Hyprland remains the source of truth when spatial mode is disabled.

The project must never require Spatial Desktop for:

- login;
- Project Launcher;
- standard workspaces;
- normal window focus;
- Omarchy integration;
- install, reinstall, or uninstall.

A missing, incompatible, or failed spatial plugin must degrade to normal Hyprland behavior.

### 2.2 The plugin is version-bound

Hyprland plugins are compiled against Hyprland headers and are not assumed to be ABI-compatible across Hyprland updates.

`PLUGIN_INIT` must compare the compositor hash with the client/header hash and abort initialization on mismatch.

No compatibility shim may bypass this check.

### 2.3 Keep compositor-critical code small

The plugin owns only behavior that must execute inside Hyprland:

- spatial session state;
- window/world geometry mapping;
- camera state;
- compositor-facing commands;
- render/input integration required by later phases.

The following do not belong in the plugin:

- project discovery;
- fuzzy search;
- session orchestration policy;
- long-term persistence;
- user-facing project configuration;
- Quickshell UI;
- general workstation business logic.

### 2.4 Prefer supported APIs and event hooks

Use Hyprland plugin API entry points and event hooks where they are sufficient.

Function hooks are permitted only when a concrete requirement cannot be implemented otherwise, and each such hook must be isolated, documented, signature-validated, and covered by nested-session tests.

Phase 1 should not require a function hook.

### 2.5 No background thread inside the compositor for Phase 1

The Wayland event loop is single-threaded. Phase 1 does not add a plugin-owned worker thread, socket server thread, polling loop, or filesystem watcher.

All Phase 1 operations must be bounded and fast.

## 3. Scope boundary

### In scope

- C++ plugin skeleton;
- version/hash guard;
- plugin lifecycle;
- explicit spatial mode on/off state;
- managed-window registry;
- world coordinate model;
- camera model;
- pan at zoom 1;
- session-only state;
- custom read-only/control IPC surface;
- Lua-callable plugin entry points for bindings when supported;
- nested Hyprland test harness or equivalent repeatable integration checks;
- safe no-op behavior outside spatial mode.

### Out of scope

- arbitrary zoom;
- transformed rendering;
- transformed pointer hit-testing;
- minimap;
- Quickshell search UI;
- Rust `spatiald`;
- persistent window identity;
- project regions;
- Project Launcher integration;
- MRU search;
- automatic arrangement;
- multi-monitor independent-camera mode;
- shaders, distortion, blur, parallax;
- gestures;
- replacing workspaces globally.

## 4. Repository ownership

Phase 1 should add an isolated module rather than mix compositor code into the existing Lua workstation backend.

Expected layout:

```text
spatial/
  core/
    CMakeLists.txt
    include/
      spatial/
        Camera.hpp
        Geometry.hpp
        Protocol.hpp
        SpatialState.hpp
    src/
      Camera.cpp
      Protocol.cpp
      SpatialState.cpp
      plugin.cpp
    tests/
      camera_test.cpp
      geometry_test.cpp
      protocol_test.cpp

hypr/
  workstation/
    spatial.lua

tests/
  spatial_binding_test.lua
  spatial_fallback_test.lua

docs/
  superpowers/
    specs/
      2026-09-25-developer-spatial-desktop-phase-1-design.md
```

Exact C++ build tooling may change if the repository adopts a common native build system, but core math/protocol code must remain testable without launching Hyprland.

## 5. State model

The plugin owns one `SpatialState` per running Hyprland session.

Conceptually:

```text
SpatialState
  protocol_version
  enabled
  epoch
  camera
  desk
  managed_windows
  focused_window?
```

### 5.1 Epoch

`epoch` is a monotonically increasing session-local integer.

Increment it whenever a state transition invalidates a previous snapshot, for example:

- spatial mode enabled/disabled;
- managed window added/removed;
- camera position changes;
- monitor topology relevant to the desk changes.

Consumers can use `epoch` to reject stale state without requiring timestamps.

No persistence guarantee exists across compositor restarts in Phase 1.

## 6. World coordinate model

### 6.1 Units

World coordinates use Hyprland logical coordinate units at zoom 1.

They are:

- signed;
- represented internally as double precision;
- independent of physical pixel scale;
- not rounded during camera math;
- allowed to be negative.

This avoids binding the world model to a specific monitor DPI or framebuffer size.

### 6.2 World rectangles

Each managed window has:

```text
WorldRect
  x
  y
  width
  height
```

The rectangle represents the compositor-facing outer logical geometry selected by the Phase 1 adapter.

The exact Hyprland geometry accessor used by the plugin must be centralized so later changes in decoration/layout semantics do not leak into the world model.

### 6.3 Seeding existing windows

When a window becomes managed for the first time:

```text
world_rect := current compositor logical rect + camera offset
```

At `camera = (0, 0)`, entering spatial mode must not visually jump the window.

Phase 1 must never infer a persistent identity from the initial rect.

### 6.4 Floating-point policy

Camera/world state remains double precision even if a Hyprland API ultimately requires integer or rounded coordinates.

Rounding occurs only at the final compositor boundary.

This prevents drift after repeated pan operations.

## 7. Desk and monitor model

Phase 1 chooses **linked desk** semantics.

All active physical monitors remain in their existing Hyprland logical arrangement and act as viewports into one world.

Let the union bounding box of active monitor logical rectangles be:

```text
DeskRect
  min_x
  min_y
  max_x
  max_y
```

At zoom 1, define desk-local screen coordinates:

```text
desk_x = compositor_x - DeskRect.min_x
desk_y = compositor_y - DeskRect.min_y
```

The camera stores the world coordinate mapped to `DeskRect.min_x/min_y`.

The Phase 1 mapping is therefore:

```text
world_x = camera.x + desk_x
world_y = camera.y + desk_y

desk_x = world_x - camera.x
desk_y = world_y - camera.y
```

At `camera = (0, 0)` and an unchanged monitor topology, world geometry seeded from current compositor geometry remains visually stationary.

### 7.1 Non-rectangular monitor layouts

Monitor gaps and irregular arrangements are allowed.

The desk bounding box is only a coordinate reference. A world point mapped into a gap is not considered visible on a monitor.

Visibility is tested against the individual monitor rectangles, not only against the desk union box.

### 7.2 Monitor topology changes

Phase 1 does not attempt a sophisticated persistent reflow.

When monitors are added, removed, repositioned, or rescaled while spatial mode is active:

1. recompute `DeskRect`;
2. preserve the world point under the focused monitor's logical origin when possible;
3. increment `epoch`;
4. never rewrite saved world rectangles merely because the monitor topology changed.

If safe re-anchoring cannot be determined, disable spatial mode and return to normal Hyprland rather than guessing.

## 8. Camera model

Phase 1 camera:

```text
Camera
  x: double
  y: double
  zoom: 1.0
```

`zoom` is present in the model from day one but Phase 1 rejects values other than exactly `1.0`.

This prevents a protocol/schema break when Phase 2 adds zoom.

### 8.1 Pan

A pan by `(dx, dy)` changes:

```text
camera.x += dx
camera.y += dy
```

Window world rectangles do not change when the camera pans.

The compositor projection changes from the camera delta.

### 8.2 Camera bounds

The world is logically unbounded, but Phase 1 applies defensive numeric bounds to reject NaN, infinity, and unreasonable magnitudes.

Initial implementation bound:

```text
abs(camera.x), abs(camera.y) <= 1e9 logical units
```

The exact constant lives in one core header and is covered by tests.

### 8.3 Future zoom math

Phase 2 will use the invariant:

```text
world = camera + desk / zoom
desk  = (world - camera) * zoom
```

Zoom around a desk-local anchor `a` will preserve the world point below the anchor:

```text
anchor_world = old_camera + a / old_zoom
new_camera   = anchor_world - a / new_zoom
```

This math is specified now so Phase 1 camera semantics do not need to be renamed later.

## 9. Managed-window boundary

Phase 1 must not silently take ownership of every window in the session.

Spatial ownership is explicit.

A window can be:

```text
unmanaged
managed
excluded
destroyed
```

### 9.1 Default policy

For the first implementation:

- existing windows remain unmanaged until spatial mode is enabled;
- enabling spatial mode adopts only eligible windows in the active spatial test context;
- layer surfaces are never managed;
- desktop/background surfaces are never managed;
- unmanaged windows keep normal Hyprland behavior;
- fullscreen windows are not adopted in Phase 1;
- windows with unsafe/unsupported state are skipped with a diagnostic.

The exact eligibility adapter must be one function with tests rather than scattered conditions.

### 9.2 Workspace containment for MVP

Phase 1 does **not** replace all Hyprland workspaces.

The implementation should use an isolated spatial test workspace/context so development can be performed without taking over the user's normal workspace graph.

This is a deliberate safety boundary, not the final product behavior.

Moving from an isolated spatial context to whole-desktop ownership requires a later explicit design change.

## 10. Mode lifecycle

### 10.1 Enable

Enabling spatial mode is transactional:

1. validate plugin compatibility/state;
2. capture current desk topology;
3. discover eligible test-context windows;
4. seed their world rectangles;
5. initialize camera at zero unless an explicit session-local camera exists;
6. only after all validation succeeds set `enabled = true`;
7. increment `epoch`.

If any required step fails before commit, remain in normal mode.

### 10.2 Disable

Disabling spatial mode:

1. stop applying spatial projection;
2. restore managed windows to the best-known normal compositor geometry;
3. clear active managed projections;
4. keep only non-dangerous diagnostic/session state;
5. set `enabled = false`;
6. increment `epoch`.

Disable must be idempotent.

### 10.3 Plugin unload

`PLUGIN_EXIT` should make a best effort to disable spatial mode before plugin-owned state disappears.

The design must not rely on `PLUGIN_EXIT` for crash recovery because Hyprland may not call it after a plugin fault.

Therefore the default/fallback configuration outside the plugin must remain independently valid.

## 11. Hyprland integration surface

### 11.1 Version guard

`PLUGIN_INIT` must compare:

- `__hyprland_api_get_hash()`;
- `__hyprland_api_get_client_hash()`.

Mismatch means initialization aborts with a clear notification/error.

### 11.2 Lua binding surface

Because this repository is Lua-first, bindings should call plugin-owned Lua functions when the current Hyprland plugin API supports them.

Conceptual namespace:

```text
hl.plugin.gendbyte_spatial.toggle()
hl.plugin.gendbyte_spatial.pan(dx, dy)
hl.plugin.gendbyte_spatial.reset()
```

The Lua adapter must detect plugin availability before calling these functions.

It must never make login/config parsing depend on the plugin being installed.

### 11.3 Do not depend on generic string dispatch from Lua

Phase 1 must not base its primary control path on `hyprctl dispatch <string dispatcher>`.

The Lua-first Hyprland generation has had dispatcher-resolution regressions, and plugin dispatchers are not a strong enough compatibility boundary for this feature.

### 11.4 Hyprctl command

Register a dedicated custom command through the plugin API for diagnostics and machine-readable state.

Conceptual CLI:

```text
hyprctl gendbyte-spatial status
hyprctl gendbyte-spatial windows
hyprctl gendbyte-spatial camera
hyprctl gendbyte-spatial enable
hyprctl gendbyte-spatial disable
hyprctl gendbyte-spatial pan <dx> <dy>
```

Mutation commands are for development/automation. User keybindings should prefer the Lua plugin namespace.

## 12. Protocol v1

All machine-readable output uses versioned JSON.

### 12.1 Status

Example:

```json
{
  "protocol": 1,
  "enabled": true,
  "epoch": 42,
  "camera": {
    "x": 1200.0,
    "y": -300.0,
    "zoom": 1.0
  },
  "desk": {
    "min_x": 0.0,
    "min_y": 0.0,
    "max_x": 3840.0,
    "max_y": 1080.0
  },
  "managed_window_count": 5
}
```

### 12.2 Window state

Example:

```json
{
  "protocol": 1,
  "epoch": 42,
  "windows": [
    {
      "session_id": "0x1234",
      "world": {
        "x": 600.0,
        "y": 120.0,
        "width": 1100.0,
        "height": 780.0
      }
    }
  ]
}
```

`session_id` is explicitly ephemeral in Phase 1.

Consumers must not persist it as a durable window identity.

### 12.3 Error envelope

Machine-readable failures use:

```json
{
  "protocol": 1,
  "error": {
    "code": "SPATIAL_DISABLED",
    "message": "spatial mode is not enabled"
  }
}
```

Stable error codes are part of protocol v1; human-readable messages are not.

## 13. Plugin ↔ future daemon boundary

Issue #24 proposes a Rust `spatiald`, but it is not required to prove Phase 1.

The Phase 1 control plane intentionally uses the registered Hyprland command surface.

Future `spatiald` may consume that command surface for low-frequency control/state while using standard Hyprland event IPC for ordinary window lifecycle signals.

Do not add a plugin-owned socket server until measurements show that the command surface is insufficient.

Camera animation, render transforms, and pointer-critical operations must never depend on a round trip through `spatiald`.

The compositor remains authoritative for immediate camera/render state.

## 14. Persistence and identity design

### 14.1 Phase 1

No durable spatial window persistence.

Only session-local world state exists.

This is intentional: persisting a weak identity scheme early would create incorrect window relocation and make later migration harder.

### 14.2 Future durable identity

A later phase may construct a conservative identity from multiple signals:

```text
project_id?
launch_role?
app_id / X11 class
executable identity?
initial title pattern?
user override?
```

No single transient title or Hyprland address may be treated as authoritative.

Ambiguous matches must remain unmatched.

## 15. Failure model

### Plugin missing

Lua adapter reports spatial capability unavailable. Normal bindings/workspaces continue.

### Version mismatch

Plugin refuses initialization. No compatibility bypass. Normal workstation remains usable.

### Invalid command/protocol input

Reject with a stable error code. Never partially mutate state.

### Invalid numeric input

Reject NaN, infinity, overflow, and out-of-bound camera values.

### Managed window disappears

Remove it from the registry, increment `epoch`, continue.

### Unsupported window state transition

Prefer dropping that window from spatial management over forcing it into an invalid state.

### Monitor reconfiguration cannot be reconciled

Disable spatial mode safely rather than guessing.

## 16. Security and robustness

The feature is local and non-privileged.

It must not require:

- sudo;
- setuid;
- privileged daemon;
- network listener;
- world-writable IPC;
- execution of project content.

Protocol parsers must:

- reject unknown mutation forms conservatively;
- bound list sizes and string lengths where applicable;
- never trust a daemon/UI payload because it came from the same user session;
- avoid shell interpolation.

## 17. Build and packaging strategy

Phase 1 development uses a repository-local native build.

Required properties:

- exact Hyprland headers available at build time;
- plugin output is a single shared object;
- no installation into system-owned directories;
- developer load/unload uses an absolute path;
- production installer integration is deferred until nested tests are green.

Do not add automatic plugin loading to the main installer in the first implementation commit.

The initial development loop is:

```text
build
→ launch/use nested Hyprland
→ hyprctl plugin load <absolute .so>
→ run tests
→ hyprctl plugin unload <absolute .so>
```

## 18. Testing strategy

### 18.1 Pure native tests

Camera and geometry tests must run without Hyprland.

Cover:

- world/screen round trips at zoom 1;
- future zoom formulas as pure math;
- negative world coordinates;
- irregular desk origin;
- large but valid values;
- NaN/infinity rejection;
- repeated pan without accumulating geometry drift;
- monitor desk bounding-box calculation;
- protocol serialization;
- stable protocol error codes.

### 18.2 Plugin lifecycle tests

In a nested Hyprland session where supported:

- load succeeds with matching headers;
- load fails with mismatched build/hash;
- unload leaves the session usable;
- enable/disable is idempotent;
- state command works while enabled and disabled;
- invalid command does not crash the compositor.

### 18.3 Window tests

- adopt eligible floating test windows;
- skip layer surfaces;
- remove closed windows;
- opening/closing windows while enabled is safe;
- pan does not change stored world rectangles;
- disable restores normal behavior;
- fullscreen/unsupported windows are skipped rather than corrupted.

### 18.4 Multi-monitor tests

Phase 1 requires at least synthetic/nested coverage for:

- two horizontally arranged monitors;
- a negative monitor origin;
- a gap between monitors;
- different logical scales if nested tooling permits;
- monitor removal while spatial mode is active.

### 18.5 Lua/fallback tests

Repository Lua tests cover:

- no plugin installed;
- plugin capability available;
- spatial binding does not shadow normal behavior when unavailable;
- config parsing remains valid with spatial feature disabled.

## 19. Phase 1 acceptance criteria

Phase 1 is complete only when all are true:

- [ ] plugin load checks exact Hyprland build compatibility;
- [ ] plugin can be loaded/unloaded repeatedly in a nested session;
- [ ] spatial mode is opt-in and disabled by default;
- [ ] normal Hyprland remains functional when plugin is absent;
- [ ] eligible test windows receive session-local world rectangles;
- [ ] camera pan changes projection without mutating world rectangles;
- [ ] camera state uses the documented world/desk model;
- [ ] linked-desk multi-monitor semantics are deterministic;
- [ ] read-only status/window state is available as protocol-v1 JSON;
- [ ] invalid commands/numbers fail safely;
- [ ] no background thread is created by the plugin;
- [ ] Phase 1 requires no function hook;
- [ ] native camera/protocol tests pass;
- [ ] nested plugin lifecycle tests pass on the supported baseline;
- [ ] disabling/unloading the feature returns to normal workstation behavior.

## 20. Explicit gates before Phase 2

Do not start render-level zoom until Phase 1 evidence exists for:

1. repeatable plugin load/unload;
2. stable camera/world math;
3. correct linked-desk semantics;
4. safe monitor topology handling;
5. reliable fallback;
6. bounded plugin state;
7. no compositor crash across the nested acceptance suite.

Phase 2 must then separately design the minimum render/input integration needed for transformed windows.

If true zoom requires Hyprland internals or function hooks, that dependency must be documented as a new risk and must not be smuggled into Phase 1.

## 21. Key decisions

This design intentionally chooses:

- **hybrid architecture, but no Rust daemon in Phase 1**;
- **session-only identity before persistence**;
- **linked desk before multiple camera modes**;
- **pan-only before zoom**;
- **isolated spatial test context before whole-desktop ownership**;
- **Lua plugin functions + dedicated hyprctl command**, not generic string dispatcher dependence;
- **exact-version plugin compatibility**, not ABI assumptions;
- **safe fallback over automatic recovery guesses**.

These decisions keep the first implementation small enough to verify while preserving the architecture required by Issue #24.

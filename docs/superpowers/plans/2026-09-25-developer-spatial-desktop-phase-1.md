# Developer Spatial Desktop — Phase 1 Implementation Plan

> **For agentic workers:** implement task-by-task, keep each task reviewable, and do not advance to render-level zoom before the Phase 1 gates are green.

**Goal:** Build the smallest safe Hyprland spatial-core MVP for Issue #24: exact-version plugin loading, session-local world geometry, a linked-desk camera, pan at zoom 1, versioned JSON diagnostics, Lua-safe bindings, and normal-Hyprland fallback.

**Architecture:** Native camera/geometry/protocol code is pure C++ and testable without Hyprland. A thin Hyprland plugin adapter owns lifecycle, managed-window registration, plugin Lua functions, and a dedicated custom hyprctl command. No Rust daemon, persistence, Quickshell, render-level zoom, or function hooks are introduced in Phase 1.

**Target:** Hyprland 0.56.x, first validated against 0.56.2.

**Spec:** `docs/superpowers/specs/2026-09-25-developer-spatial-desktop-phase-1-design.md`

## Global constraints

- Spatial Desktop is opt-in and disabled by default.
- Normal Hyprland must remain usable if the plugin is absent, incompatible, disabled, or fails to load.
- Exact compositor/header hash mismatch aborts plugin initialization.
- Phase 1 uses no function hook and no plugin-owned background thread.
- World coordinates are signed double-precision logical units.
- `zoom` exists in the model but Phase 1 accepts only `1.0`.
- Camera pan changes projection, never the stored world rectangle.
- Phase 1 state is session-local only.
- Phase 1 uses linked-desk multi-monitor semantics.
- The first implementation is isolated from the user's normal whole-desktop workflow.
- User bindings prefer plugin-owned Lua functions; generic string dispatch is not the primary control path.
- A dedicated custom hyprctl command provides protocol-v1 JSON state/diagnostics.
- Do not integrate automatic plugin loading into the production installer until the nested acceptance suite is green.

---

## File structure

Create:

```text
spatial/core/
  CMakeLists.txt
  include/spatial/
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
    CMakeLists.txt
    camera_test.cpp
    geometry_test.cpp
    protocol_test.cpp
    state_test.cpp

hypr/workstation/
  spatial.lua

tests/
  spatial_binding_test.lua
  spatial_fallback_test.lua

docs/superpowers/plans/
  2026-09-25-developer-spatial-desktop-phase-1.md
```

Modify as needed:

```text
hypr/bindings.lua
tests/run.lua
.github/workflows/lua.yml
README.md
```

Do not modify installer lifecycle files until the plugin MVP has passed nested validation.

---

## Task 1: Pure geometry and camera core

**Files:**
- Create: `spatial/core/include/spatial/Geometry.hpp`
- Create: `spatial/core/include/spatial/Camera.hpp`
- Create: `spatial/core/src/Camera.cpp`
- Create: `spatial/core/tests/geometry_test.cpp`
- Create: `spatial/core/tests/camera_test.cpp`
- Create: `spatial/core/tests/CMakeLists.txt`
- Create: `spatial/core/CMakeLists.txt`

**Interfaces:**

```cpp
namespace spatial {

struct Point {
    double x;
    double y;
};

struct Rect {
    double x;
    double y;
    double width;
    double height;
};

struct DeskRect {
    double minX;
    double minY;
    double maxX;
    double maxY;
};

class Camera {
public:
    static constexpr double kMinCoordinate = -1.0e9;
    static constexpr double kMaxCoordinate =  1.0e9;

    Point position() const noexcept;
    double zoom() const noexcept;

    bool pan(double dx, double dy) noexcept;
    bool setPosition(Point value) noexcept;
    bool setZoom(double value) noexcept;

    Point deskToWorld(Point desk) const noexcept;
    Point worldToDesk(Point world) const noexcept;
};

}
```

- [ ] **Step 1: Write RED tests**

Cover:

- camera starts at `(0,0)`, zoom `1.0`;
- `deskToWorld` and `worldToDesk` round-trip;
- negative coordinates;
- pan does not accumulate integer rounding drift;
- NaN and infinity are rejected;
- coordinates outside `±1e9` are rejected;
- Phase 1 rejects zoom other than `1.0`;
- future zoom transform helper tests are pure and disabled from mutation API if useful.

- [ ] **Step 2: Add minimal CMake test target**

The pure core must build without Hyprland headers.

Use C++23 only if required by repository/toolchain reality; otherwise prefer C++20 for the pure core.

CTest must be runnable with:

```bash
cmake -S spatial/core -B build/spatial-core -DSPATIAL_BUILD_PLUGIN=OFF
cmake --build build/spatial-core
ctest --test-dir build/spatial-core --output-on-failure
```

- [ ] **Step 3: Implement minimum geometry/camera code**

No Hyprland includes in `Geometry.hpp`, `Camera.hpp`, or `Camera.cpp`.

- [ ] **Step 4: Verify GREEN**

Run the pure native tests.

- [ ] **Step 5: Commit**

```text
feat(spatial): add camera and geometry core
```

---

## Task 2: Spatial state model

**Files:**
- Create: `spatial/core/include/spatial/SpatialState.hpp`
- Create: `spatial/core/src/SpatialState.cpp`
- Create: `spatial/core/tests/state_test.cpp`
- Modify: `spatial/core/CMakeLists.txt`

**Interfaces:**

```cpp
namespace spatial {

using SessionWindowId = std::string;

struct ManagedWindow {
    SessionWindowId id;
    Rect world;
};

class SpatialState {
public:
    bool enabled() const noexcept;
    std::uint64_t epoch() const noexcept;
    const Camera& camera() const noexcept;

    bool enable(DeskRect desk);
    void disable() noexcept;

    bool addWindow(ManagedWindow window);
    bool removeWindow(std::string_view id);
    const ManagedWindow* findWindow(std::string_view id) const noexcept;

    bool pan(double dx, double dy) noexcept;

    std::span<const ManagedWindow> windows() const noexcept;
};

}
```

Implementation may use a vector/map internally; public API must not expose Hyprland window pointers.

- [ ] **Step 1: Write RED state tests**

Cover:

- default disabled state;
- enable increments epoch;
- repeated enable has deterministic behavior;
- disable is idempotent;
- add/remove increments epoch;
- duplicate window IDs are rejected or replaced according to one explicit rule;
- pan increments epoch only on successful mutation;
- failed pan does not change epoch;
- stored world rectangles remain unchanged after pan;
- state can be cleared without accessing compositor objects.

- [ ] **Step 2: Implement minimal state core**

Keep all Hyprland types outside this unit.

- [ ] **Step 3: Run camera + state tests**

- [ ] **Step 4: Commit**

```text
feat(spatial): add session state model
```

---

## Task 3: Protocol v1 JSON serialization

**Files:**
- Create: `spatial/core/include/spatial/Protocol.hpp`
- Create: `spatial/core/src/Protocol.cpp`
- Create: `spatial/core/tests/protocol_test.cpp`
- Modify: `spatial/core/CMakeLists.txt`

**Outputs:**

```text
status JSON
windows JSON
camera JSON
stable error JSON
```

Protocol schema follows the Phase 1 spec.

- [ ] **Step 1: Write RED serialization tests**

Assert exact structural fields:

- `protocol = 1`;
- `enabled`;
- `epoch`;
- camera `x/y/zoom`;
- desk rectangle;
- managed count;
- session-only window IDs;
- error `code/message`.

Do not test whitespace or object key order unless the serializer guarantees it.

- [ ] **Step 2: Select the smallest serialization dependency**

Preferred order:

1. already-available project/system JSON dependency with deterministic packaging;
2. small vendored/header-only dependency only if license and maintenance cost are acceptable;
3. narrow hand-written JSON encoder for this fixed output schema.

Do not introduce a general parser if Phase 1 commands can be parsed as bounded tokens.

- [ ] **Step 3: Implement output-only protocol v1**

No durable identity field.

- [ ] **Step 4: Fuzz/edge checks**

Ensure strings are escaped correctly and non-finite numbers can never reach JSON output.

- [ ] **Step 5: Commit**

```text
feat(spatial): add protocol v1 diagnostics
```

---

## Task 4: Hyprland plugin skeleton and version guard

**Files:**
- Create: `spatial/core/src/plugin.cpp`
- Modify: `spatial/core/CMakeLists.txt`
- Add build documentation under `spatial/core/README.md` if needed

**Plugin contract:**

- exports `PLUGIN_API_VERSION`;
- stores plugin handle;
- in `PLUGIN_INIT`, compares compositor/client hashes;
- aborts initialization on mismatch;
- creates only bounded session state;
- registers no function hook;
- creates no background thread;
- returns plugin metadata;
- best-effort disables state in `PLUGIN_EXIT`.

- [ ] **Step 1: Add plugin target behind `SPATIAL_BUILD_PLUGIN`**

Pure tests must still build with plugin target disabled.

- [ ] **Step 2: Implement exact-version guard first**

Do not register callbacks/commands before compatibility validation succeeds.

- [ ] **Step 3: Build against matching Hyprland 0.56.x development headers**

Document the exact command and detected version.

- [ ] **Step 4: Manual/nested smoke test**

```bash
hyprctl plugin load /absolute/path/to/gendbyte-spatial.so
hyprctl plugin list
hyprctl plugin unload /absolute/path/to/gendbyte-spatial.so
```

Expected: repeated load/unload does not leave config errors or crash the nested session.

- [ ] **Step 5: Commit**

```text
feat(spatial): add Hyprland plugin lifecycle
```

---

## Task 5: Dedicated hyprctl command surface

**Files:**
- Modify: `spatial/core/src/plugin.cpp`
- Create or extend command adapter file if `plugin.cpp` becomes too large
- Extend: `spatial/core/tests/protocol_test.cpp`

**Command family:**

```text
gendbyte-spatial status
gendbyte-spatial windows
gendbyte-spatial camera
gendbyte-spatial enable
gendbyte-spatial disable
gendbyte-spatial pan <dx> <dy>
```

- [ ] **Step 1: Write pure command parser tests**

Extract command token parsing from Hyprland registration so malformed numeric inputs can be tested without the compositor.

Cover:

- missing command;
- unknown command;
- too many args;
- invalid number;
- NaN/Inf spelling;
- out-of-range pan;
- mutation while disabled where relevant.

- [ ] **Step 2: Register custom Hyprland command**

Use the current plugin API custom command registration rather than relying on generic string dispatcher resolution.

- [ ] **Step 3: Return protocol-v1 JSON**

Examples:

```bash
hyprctl gendbyte-spatial status
hyprctl gendbyte-spatial camera
```

- [ ] **Step 4: Nested tests**

Invalid commands must return errors without destabilizing Hyprland.

- [ ] **Step 5: Commit**

```text
feat(spatial): expose versioned control protocol
```

---

## Task 6: Managed-window registry adapter

**Files:**
- Create: `spatial/core/include/spatial/HyprlandAdapter.hpp`
- Create: `spatial/core/src/HyprlandAdapter.cpp`
- Modify: `spatial/core/src/plugin.cpp`
- Extend nested tests

**Boundary:**

`HyprlandAdapter` converts compositor window state into pure `ManagedWindow` records and applies Phase 1 projection.

It must centralize all direct Hyprland window geometry access.

- [ ] **Step 1: Define eligibility**

Explicitly skip:

- layer surfaces;
- destroyed/unmapped windows;
- unsupported fullscreen state;
- windows outside the Phase 1 isolated spatial test context.

- [ ] **Step 2: Adopt eligible windows transactionally**

On enable:

1. collect candidates;
2. validate all records;
3. seed `world = compositor geometry + camera`;
4. commit managed state only if the enable transition is valid.

- [ ] **Step 3: Handle open/close lifecycle with event hooks**

Use supported events where possible.

No function hook.

- [ ] **Step 4: Test disappearance while enabled**

Closing a managed window removes it and increments epoch.

- [ ] **Step 5: Commit**

```text
feat(spatial): track managed Hyprland windows
```

---

## Task 7: Pan projection at zoom 1

**Files:**
- Modify: `spatial/core/src/HyprlandAdapter.cpp`
- Modify: `spatial/core/src/plugin.cpp`
- Extend: native and nested tests

**Invariant:**

```text
stored world rectangle does not change when camera pans
projected compositor rectangle = world rectangle - camera offset
```

- [ ] **Step 1: Add RED projection tests**

For a window:

```text
world=(1000,500)
camera=(200,-100)
projected=(800,600)
```

- [ ] **Step 2: Implement Phase 1 projection**

Keep projection code centralized.

If applying the projection requires an unstable/internal Hyprland path, stop this task and document the exact API gap before adding a function hook. A hook is not implicitly authorized by this plan.

- [ ] **Step 3: Nested visual/geometry verification**

Open at least three test windows, pan in four directions, and verify:

- relative world positions stay constant;
- focus remains usable;
- no cumulative drift;
- disable returns to the captured normal geometry.

- [ ] **Step 4: Commit**

```text
feat(spatial): implement zoom-one camera pan
```

---

## Task 8: Lua-safe bindings and fallback

**Files:**
- Create: `hypr/workstation/spatial.lua`
- Modify: `hypr/bindings.lua`
- Create: `tests/spatial_binding_test.lua`
- Create: `tests/spatial_fallback_test.lua`
- Modify: `tests/run.lua`

**Behavior:**

The Lua layer must detect whether plugin functions are actually available before invoking them.

No config parse or login failure is allowed when the plugin is missing.

Suggested user-facing bindings are provisional and must avoid collisions with existing owned keys.

- [ ] **Step 1: Write RED Lua tests**

Cover:

- plugin namespace absent;
- namespace present;
- toggle calls plugin exactly once;
- pan calls correct bounded values;
- missing plugin returns a capability/unavailable result rather than throwing;
- existing Project Launcher/overview bindings remain intact.

- [ ] **Step 2: Register plugin-owned Lua functions in C++**

Conceptual API:

```text
hl.plugin.gendbyte_spatial.toggle()
hl.plugin.gendbyte_spatial.pan(dx, dy)
hl.plugin.gendbyte_spatial.reset()
```

- [ ] **Step 3: Implement Lua adapter**

Keep all plugin capability checks in one module.

- [ ] **Step 4: Run full Lua suite**

```bash
lua5.1 tests/run.lua
find . -name '*.lua' -type f -print0 | xargs -0 -n1 luac5.1 -p
```

- [ ] **Step 5: Commit**

```text
feat(spatial): add safe Lua bindings and fallback
```

---

## Task 9: CI for pure native core

**Files:**
- Create: `.github/workflows/spatial-core.yml` or extend existing CI with a separate job

Do **not** make the generic GitHub-hosted job pretend it has a matching live Hyprland compositor.

CI split:

### Pure native CI

Runs everywhere:

- configure with `SPATIAL_BUILD_PLUGIN=OFF`;
- compile geometry/camera/state/protocol;
- run CTest;
- optionally clang-format/clang-tidy if configuration is deterministic.

### Plugin build CI

Only add when a reproducible Hyprland 0.56.x development environment is pinned.

### Nested compositor CI

May remain local/manual initially if reliable nested Hyprland is not feasible in GitHub-hosted runners.

- [ ] **Step 1: Add pure native job**
- [ ] **Step 2: Verify existing Lua/web jobs are unchanged**
- [ ] **Step 3: Commit**

```text
ci: test spatial core independently
```

---

## Task 10: Phase 1 acceptance harness and evidence

**Files:**
- Create: `spatial/core/tests/nested/README.md`
- Create scripts only where repeatability justifies them
- Update: `docs/superpowers/specs/2026-09-25-developer-spatial-desktop-phase-1-design.md` only for discovered implementation facts, not to rewrite history

Acceptance evidence must record:

- Hyprland exact version/hash;
- plugin build/header version;
- load/unload iterations;
- test commands;
- status JSON sample;
- managed window count;
- pan checks;
- monitor topology used;
- fallback result;
- `hyprctl configerrors`.

- [ ] **Step 1: Run native suite**
- [ ] **Step 2: Run full existing Lua suite**
- [ ] **Step 3: Run nested plugin lifecycle suite**
- [ ] **Step 4: Run managed-window/pan tests**
- [ ] **Step 5: Verify plugin missing/incompatible fallback**
- [ ] **Step 6: Record evidence**
- [ ] **Step 7: Commit**

```text
test(spatial): add phase 1 acceptance evidence
```

---

## Phase 1 stop conditions

Stop implementation and update Issue #24 before proceeding if any of these are discovered:

1. pan projection requires broad renderer hooking rather than a narrow compositor API;
2. correct disable/unload cannot restore normal geometry deterministically;
3. Lua plugin functions are unavailable/unreliable on the supported baseline;
4. custom hyprctl command registration cannot provide a stable local control surface;
5. linked-desk semantics conflict with Hyprland monitor logical coordinates;
6. nested testing cannot reproduce compositor failures reliably;
7. plugin unload leaves dangling compositor state.

The correct response to a stop condition is a design revision, not an undocumented workaround.

---

## Definition of done

Phase 1 is done when:

- all pure native tests pass;
- existing Lua/web CI remains green;
- plugin version mismatch fails closed;
- repeated nested load/unload is stable;
- spatial mode is disabled by default;
- managed test windows have session-local world rectangles;
- camera pan leaves world rectangles unchanged;
- linked-desk state is deterministic;
- protocol-v1 JSON works through the dedicated hyprctl command;
- Lua bindings fail safely when the plugin is absent;
- no function hook or background plugin thread was introduced;
- disabling/unloading returns to normal Hyprland behavior;
- acceptance evidence is recorded against the supported Hyprland baseline.

Only then open Phase 2 work for render-level zoom and transformed input.

# Phase 1 nested Hyprland validation

This directory contains the runtime acceptance harness for the compositor-facing part of Developer Spatial Desktop Phase 1.

The native and Arch build workflows prove that the pure core is correct enough to compile/test and that `gendbyte-spatial.so` builds against the packaged Hyprland headers. They **do not** prove that moving live compositor windows is safe.

Run this validation only in a disposable or nested Hyprland session.

## Build

Use matching development headers and running compositor:

```bash
pkg-config --modversion hyprland
hyprctl version

cmake -S spatial/core -B build/spatial-plugin \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DSPATIAL_BUILD_PLUGIN=ON \
  -DSPATIAL_BUILD_TESTS=ON

cmake --build build/spatial-plugin --parallel
ctest --test-dir build/spatial-plugin --output-on-failure
```

## Prepare the nested session

Open at least one ordinary window on the visible workspace.

Do not use important unsaved applications for the test.

Eligibility:

- on a single-monitor session, ordinary tiled and floating windows are managed;
- on multi-monitor sessions, floating windows are managed, while tiled cross-seam projection is intentionally deferred;
- fullscreen/maximized windows managed as fullscreen are excluded;
- layer surfaces are excluded;
- windows on non-visible workspaces are excluded.

Tiled windows are **not** converted to floating. Spatial projection overrides
their live compositor box while leaving Hyprland's layout tree untouched.
Disable restores canonical tiling by recalculating the existing layout tree.

## Run

The harness deliberately requires an explicit acknowledgement:

```bash
export SPATIAL_TEST_ACK=I_UNDERSTAND_THIS_MUST_RUN_IN_A_DISPOSABLE_HYPRLAND_SESSION

spatial/core/tests/nested/phase1-smoke.sh \
  "$(realpath build/spatial-plugin/gendbyte-spatial.so)"
```

The script:

1. verifies a Hyprland session exists;
2. loads the plugin by absolute path;
3. confirms protocol v1 and disabled-by-default state;
4. enables spatial mode;
5. prints managed world rectangles;
6. pans the camera by `(+320,0)`;
7. pans back to zero;
8. disables spatial mode;
9. prints `hyprctl configerrors`;
10. unloads the plugin;
11. uses a trap to attempt disable/unload on early failure.

## Manual observations required

While the script pauses only through normal command output, observe the desktop during the two pan operations.

At `camera = (+320,0)`:

- every managed window should move by `(-320,0)` in compositor coordinates;
- relative distances between managed windows must remain unchanged;
- window size must not change;
- pointer targeting/focus should still correspond to the moved window geometry;
- floating windows may cross monitor boundaries when their source workspace is visible; tiled cross-monitor projection is intentionally deferred;
- `hyprctl gendbyte-spatial windows` must keep the same world rectangles.

After the reverse pan and `disable`:

- camera returns to `(0,0)`;
- managed windows return to their captured pre-enable geometry;
- normal focus and drag behavior works;
- plugin unload does not crash or hang Hyprland;
- `hyprctl configerrors` has no new spatial-related errors.

## Important current limitation

Manual user movement of a managed window while spatial mode is active is not yet reconciled into world coordinates. Phase 1 treats the geometry captured at adoption as the normal geometry to restore on disable.

Do not use manual window dragging as part of the smoke test unless specifically testing this limitation.

## Evidence to record

For Issue #24, record:

- `hyprctl version`;
- package/header version;
- plugin commit SHA;
- number of managed windows;
- monitor topology;
- status/windows/camera JSON output;
- whether cross-monitor rendering remained correct;
- whether focus/pointer targeting remained correct;
- whether disable restored geometry;
- whether unload remained stable;
- `hyprctl configerrors`.


## Why runtime projection is not executed in GitHub-hosted container CI

An automated runtime attempt was implemented and tested against the Arch Linux GitHub container.

The compositor reached the Hyprland startup path, but Aquamarine could not create a backend because the hosted container exposes no DRM render node.

This is not a plugin build failure:

- the pure native suite passes;
- `gendbyte-spatial.so` builds successfully against Arch Hyprland 0.56.2;
- shell smoke syntax is validated.

Aquamarine currently requires a primary allocator before Hyprland can run. Its Wayland backend also expects linux-dmabuf/DRM feedback and a usable DRM node; a software-only Weston/pixman parent does not satisfy that requirement. Therefore a normal GitHub-hosted container without `/dev/dri` cannot provide a representative compositor runtime gate.

Do not mark runtime acceptance green from compile CI alone. The `phase1-smoke.sh` test remains required on a disposable/nested Hyprland session backed by a real render node.

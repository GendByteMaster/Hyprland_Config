# Workspace Overview v0.4 — preview feasibility

Issue: #6

## Decision

Use Quickshell's native Hyprland/Wayland integration for window state and live previews:

```text
Quickshell.Hyprland
  -> Hyprland.toplevels
  -> toplevel.wayland
  -> Quickshell.Wayland.ScreencopyView
```

This is the selected Phase 0 preview path.

The production overview must **not** use periodic PNG/screenshot capture and must not poll
`hyprctl` on a render loop.

## Evidence

Two existing public Omarchy/Quickshell overview implementations were inspected as
feasibility references:

- `itsmoorgrove/omarchy-overview`
  - `WindowTile.qml` uses `ScreencopyView` with
    `captureSource: entry.toplevel.wayland` and `live: true`.
  - `Surface.qml` uses `Quickshell.Hyprland` state and a layer-shell overlay.
- `ecylmz/omarchy-spaceview`
  - `WindowPreview.qml` uses `ScreencopyView` with a Wayland toplevel capture source.
  - `Spaceview.qml` uses `Hyprland.toplevels`, `Hyprland.workspaces`,
    `Hyprland.monitors`, raw Hyprland events, and scoped refreshes after mutations.

References:

- https://github.com/itsmoorgrove/omarchy-overview
- https://github.com/ecylmz/omarchy-spaceview

These projects are architecture/feasibility references only. Do not copy their code into this
repository.

## Why this approach

### Advantages

- live compositor-backed previews;
- no screenshot files;
- no continuous process spawning;
- no image-cache invalidation loop;
- preview lifetime can be tied to overview visibility;
- direct access to Hyprland workspaces, monitors, focused state, and toplevel objects;
- graceful icon/title fallback when a Wayland capture source is temporarily unavailable.

### Rejected: periodic screenshots

A screenshot pipeline would require repeated capture, temporary buffers/files or image
transport, invalidation, throttling, and stale-frame handling. It would also scale poorly as the
number of windows grows.

It is not acceptable for the v0.4 primary implementation.

### Rejected: render-loop `hyprctl` polling

Repeatedly spawning `hyprctl -j clients` or related commands for rendering would duplicate
state already maintained by Quickshell's Hyprland integration and introduce unnecessary process
and parsing overhead.

Bounded CLI/dispatcher calls remain acceptable for mutations if a direct Quickshell dispatcher is
not available.

## Proposed state split

The implementation should have two layers:

### Compositor adapter

Quickshell owns live compositor objects:

- `Hyprland.toplevels`
- `Hyprland.workspaces`
- `Hyprland.monitors`
- focused workspace/monitor;
- Wayland capture source;
- raw compositor events.

The adapter converts those objects into a narrow metadata shape for navigation and policy.

### Pure overview model

Pure logic must remain independent of visual QML delegates:

- address validation;
- client normalization;
- filtering;
- workspace grouping;
- selection reconciliation;
- spatial keyboard navigation;
- stale-reference protection.

The first model implementation lives in `lua/workstation/overview_model.lua` and is covered by
Lua 5.1 tests. QML must follow the same rules; do not hide policy inside visual delegates.

## Preview lifecycle

A `ScreencopyView` should capture only while the overview is visible.

Expected behavior:

```text
overview hidden
  -> captureSource = null / live = false

overview visible
  -> captureSource = toplevel.wayland
  -> live = true
```

If `toplevel.wayland` or preview content is unavailable, render a deterministic fallback:

1. app icon;
2. title;
3. app/class identifier.

Window activation must continue to work without a live preview.

## Try Omarchy validation required

Phase 0 is code-feasible, but runtime validation is still required on the target Try Omarchy
environment.

Before declaring live previews production-ready, verify:

- native Wayland window;
- XWayland window if available;
- fullscreen window;
- floating window;
- rapidly changing content;
- 5+ simultaneous previews;
- opening/closing the overview repeatedly;
- preview resources stop updating when hidden.

## Performance guardrails

- no polling timer for normal window-state observation;
- no screenshot files;
- no unbounded preview cache;
- live capture only while visible;
- event-triggered refresh only for mutations where native state is temporarily stale;
- any settle/retry timer must be short, bounded, and documented.

## Phase 0 result

**GO** for a Quickshell-native live preview prototype using
`Quickshell.Hyprland` + `Quickshell.Wayland.ScreencopyView`.

The remaining risk is target-environment runtime behavior, not availability of a viable preview
API.

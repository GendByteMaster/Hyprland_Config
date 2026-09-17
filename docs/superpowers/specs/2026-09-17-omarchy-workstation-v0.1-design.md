# Omarchy Workstation v0.1 Design

## Goal

Build the first maintainable layer of a personal workstation on top of the Hyprland configuration shipped by Omarchy, without forking Omarchy or editing files under `/usr/share/omarchy`.

The first vertical slice covers only:

- repository-as-source-of-truth for personal Hyprland overrides;
- safe installation through per-file symlinks into `~/.config/hypr`;
- personal keybinding module compatible with Omarchy's Lua config API;
- NumFlow-like Mouse Mode launched from Hyprland;
- verification and uninstall/restore behavior.

System monitoring, Warp-like terminal workflows, Project Launcher, Command Center, notifications, and a custom shell/dashboard are explicitly deferred to later subprojects.

## Context

Current Omarchy loads its defaults first and then loads these user modules:

- `hypr.monitors`
- `hypr.input`
- `hypr.bindings`
- `hypr.looknfeel`
- `hypr.autostart`

That makes `~/.config/hypr` the correct extension boundary. Personal changes must stay outside `/usr/share/omarchy` so Omarchy updates can replace upstream defaults without overwriting this repository.

Omarchy's `bindings.lua` supports adding or replacing bindings through `o.bind` and `o.rebind`, and existing bindings can be disabled with `hl.unbind`.

## Scope decomposition

The workstation project is larger than one implementation unit, so development is split into independently testable subprojects:

1. **v0.1 — Omarchy integration + Mouse Mode**
2. **v0.2 — System monitoring and dashboard**
3. **v0.3 — Ghostty/Warp-like terminal workflow layer**
4. **v0.4 — Project Launcher and workspace orchestration**
5. **v0.5 — Unified Command Center and optional custom shell UI**

This document specifies only v0.1.

## Approaches considered

### A. Edit Omarchy defaults directly

Modify files under `/usr/share/omarchy/default/hypr`.

**Advantages:** minimal indirection.

**Disadvantages:** package updates can overwrite changes; upstream and personal configuration become mixed; rollback is difficult.

**Decision:** rejected.

### B. Replace the entire `~/.config/hypr` directory with the repository

Make the repository own every Hyprland file, including Omarchy's bootstrap-facing user files.

**Advantages:** simple mental model; everything is version controlled.

**Disadvantages:** unnecessarily takes ownership of files Omarchy may evolve; makes migration across Omarchy versions more brittle; harder to preserve local machine-specific monitor/input settings.

**Decision:** rejected for v0.1.

### C. Manage only selected user override files through symlinks

Keep Omarchy as the base and symlink only repository-owned modules/scripts into the expected user paths.

**Advantages:** smallest ownership surface; compatible with Omarchy updates; easy rollback; repository remains portable; machine-local files can remain local.

**Disadvantages:** installer must detect pre-existing files and preserve them safely.

**Decision:** selected.

## Repository layout

```text
Hyprland_Config/
├── hypr/
│   └── bindings.lua
├── mouse-mode/
│   ├── mouse-mode.sh
│   └── README.md
├── scripts/
│   ├── install.sh
│   ├── uninstall.sh
│   └── verify.sh
├── docs/
│   └── superpowers/
│       ├── specs/
│       └── plans/
└── README.md
```

Only `hypr/bindings.lua` is managed in v0.1. `input.lua`, `monitors.lua`, `looknfeel.lua`, and `autostart.lua` remain untouched until a later feature actually needs them.

## Installation model

The repository is the source of truth.

`install.sh` creates:

```text
~/.config/hypr/bindings.lua -> <repo>/hypr/bindings.lua
~/.local/bin/hypr-mouse-mode -> <repo>/mouse-mode/mouse-mode.sh
```

Before replacing an existing non-symlink file, the installer moves it to a timestamped backup directory under:

```text
~/.local/state/hyprland-config/backups/<timestamp>/
```

The installer must be idempotent: running it again when the correct symlinks already exist must succeed without creating duplicate backups.

It must not modify `/usr/share/omarchy`.

## Keybinding design

`hypr/bindings.lua` adds only workstation-specific bindings and does not disable Omarchy's complete default binding set.

Initial binding:

```text
SUPER + M -> toggle Mouse Mode
```

The binding launches `hypr-mouse-mode` through `o.bind`.

`Super + H`, terminal bindings, Project Launcher bindings, and Command Center bindings remain unassigned by this subproject unless Omarchy already owns them.

## Mouse Mode behavior

Mouse Mode is a modal helper inspired by NumFlow. It must not require changes to Hyprland itself.

Activation:

```text
Super + M -> enter/toggle Mouse Mode
Esc       -> exit Mouse Mode
```

Mappings while active:

```text
NumPad 8 -> up
NumPad 2 -> down
NumPad 4 -> left
NumPad 6 -> right
NumPad 7 -> up-left
NumPad 9 -> up-right
NumPad 1 -> down-left
NumPad 3 -> down-right

NumPad 5 -> left click
NumPad + -> double left click
NumPad * -> right click
NumPad - -> middle click
NumPad 0 -> hold left button
NumPad . -> release left button
```

Movement must support acceleration rather than a fixed large step:

- short taps: precise movement;
- continued hold: progressively faster movement;
- releasing a direction resets acceleration for the next movement.

The implementation must keep the mode bounded: when Mouse Mode is not active, NumPad behavior must remain normal.

## Implementation boundary

v0.1 may use existing Wayland/Hyprland-compatible command-line tools for pointer injection instead of implementing a kernel/input backend.

The Mouse Mode process owns only:

- mode lifecycle;
- NumPad key interpretation;
- acceleration state;
- pointer/button actions;
- clean exit.

It does not own window management, global application launching, monitoring, or terminal behavior.

## Failure handling

The installer must stop with a clear error when:

- Omarchy/Hyprland user config directory cannot be created;
- a required dependency for Mouse Mode is missing;
- a target path exists but cannot be backed up or replaced;
- the repository path cannot be resolved.

Mouse Mode must exit cleanly on `Esc`, process termination, or dependency failure and must not leave a mouse button logically held down.

## Verification

`verify.sh` performs non-destructive checks:

1. repository-managed files exist;
2. expected symlinks point to this repository;
3. `bindings.lua` is syntactically valid Lua;
4. Mouse Mode script is executable/syntax-valid;
5. required runtime commands are available;
6. no repository-owned path points into `/usr/share/omarchy`.

Manual acceptance checks:

1. restart/reload the Omarchy shell/Hyprland configuration;
2. confirm existing Omarchy shortcuts still work;
3. press `Super + M` and confirm Mouse Mode activates;
4. verify all movement directions and click actions;
5. exit with `Esc` and confirm NumPad behaves normally again;
6. rerun `install.sh` and confirm idempotence;
7. run `uninstall.sh` and confirm previous files can be restored from backup.

## Security and safety constraints

- No `sudo` is required for normal installation.
- No files under `/usr/share/omarchy` are modified.
- Existing user configuration is backed up before replacement.
- Scripts use strict shell error handling.
- Mouse Mode releases any held pointer button during shutdown.
- Installation and uninstall operations are limited to explicit paths owned by this project.

## Non-goals for v0.1

The following are intentionally excluded:

- replacing Omarchy Shell;
- custom Quickshell dashboard;
- CPU/RAM/network monitoring UI;
- Ghostty configuration beyond any dependency needed by Mouse Mode;
- Warp-style command blocks or AI terminal assistant;
- project detection or workspace orchestration;
- clipboard manager;
- notification daemon;
- system service management UI.

## Success criteria

v0.1 is complete when a fresh Omarchy user can clone this repository, run one installer without `sudo`, keep Omarchy's defaults intact, toggle a NumFlow-like Mouse Mode with `Super + M`, verify the installation, and uninstall/restore the previous local configuration without editing Omarchy's packaged files.
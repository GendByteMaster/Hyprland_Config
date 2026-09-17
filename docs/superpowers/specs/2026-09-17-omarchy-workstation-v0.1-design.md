# Omarchy Workstation v0.1 Design

## Goal

Build the first maintainable layer of a personal workstation on top of the Hyprland configuration shipped by Omarchy, without forking Omarchy or editing `/usr/share/omarchy`.

v0.1 is intentionally narrow:

- repository-as-source-of-truth for personal Hyprland overrides;
- Lua-first implementation for all project-owned behavior;
- NumFlow-like Mouse Mode implemented inside Hyprland's Lua runtime;
- safe Lua installer, verifier, and uninstaller;
- preservation and restoration of an existing user `bindings.lua`.

Monitoring, the Warp-like terminal layer, Project Launcher, Command Center, and custom dashboard are separate later subprojects.

## Architecture principle: Lua-first

All logic owned by this repository is written in Lua unless a later feature has a concrete technical reason not to be. Existing system components remain external: Hyprland, Omarchy, Ghostty, Git, Docker, systemd, and coreutils are orchestrated rather than reimplemented.

Omarchy already installs `lua51`, so standalone project tools target Lua 5.1 and are invoked with `lua5.1`. Hyprland runs its own Lua configuration runtime and supplies the `hl` API.

No Bash/Python/Rust runtime is introduced by v0.1.

## Omarchy integration boundary

Omarchy loads its defaults first and then user modules including `hypr.bindings`. Its bootstrap adds `~/.config/?.lua` to `package.path`, so a module such as `require("hypr.workstation.mouse")` resolves from `~/.config/hypr/workstation/mouse.lua`.

Project files never modify `/usr/share/omarchy`.

## Repository layout

```text
Hyprland_Config/
├── hypr/
│   ├── bindings.lua
│   └── workstation/
│       ├── mouse.lua
│       └── mouse_state.lua
├── lua/
│   └── workstation/
│       ├── command.lua
│       ├── paths.lua
│       └── install_state.lua
├── tests/
│   ├── run.lua
│   └── mouse_state_test.lua
├── install.lua
├── uninstall.lua
├── verify.lua
├── docs/
│   └── superpowers/
│       ├── specs/
│       └── plans/
└── README.md
```

`mouse_state.lua` contains compositor-independent acceleration state so it can be unit tested with plain Lua 5.1. `mouse.lua` is the Hyprland adapter.

## Installation model

The repository is the source of truth. `lua5.1 install.lua` manages only these user paths:

```text
~/.config/hypr/bindings.lua
~/.config/hypr/workstation
```

They point to:

```text
<repo>/hypr/bindings.lua
<repo>/hypr/workstation
```

If `~/.config/hypr/bindings.lua` already exists and is not this project's managed link, the installer moves it into a timestamped backup under:

```text
~/.local/state/hyprland-config/backups/<timestamp>/hypr/bindings.lua
```

The project wrapper then loads that preserved file before registering workstation bindings, so existing personal bindings continue to work while v0.1 is installed.

A small data-only state file under `~/.local/state/hyprland-config/` records the active repository root and backup path. The installer is idempotent: rerunning it when the correct links already exist must not create another backup.

Installation requires no `sudo`, `pkexec`, input-group membership, `/dev/uinput`, or daemon.

## Keybinding design

`hypr/bindings.lua` performs two operations in order:

1. load the preserved pre-install user bindings when an active backup is recorded;
2. register the workstation Mouse Mode.

`SUPER + M` is reserved for Mouse Mode with `o.rebind` so a pre-existing user binding cannot leave duplicate actions on the same shortcut.

Other workstation shortcuts are outside v0.1.

## Mouse Mode

Mouse Mode is implemented entirely using Hyprland's Lua API. It uses a Hyprland submap named `mouse`, cursor dispatchers, key-state dispatchers, timers, and notifications.

Activation:

```text
Super + M -> enter Mouse Mode
Esc       -> exit Mouse Mode
Super + M -> exit Mouse Mode while already active
```

Mappings:

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

Both numeric keypad symbols (`KP_8`, etc.) and their NumLock-off navigation equivalents (`KP_Up`, etc.) are registered where applicable.

### Movement

Movement binds use Hyprland's `repeating` flag. Each direction maintains a repeat count. The movement step grows in bounded stages:

```text
presses 1-2   -> 3 px
presses 3-5   -> 6 px
presses 6-10  -> 12 px
presses 11+   -> 24 px
```

Releasing that direction resets its counter. Diagonal movement is normalized so it is not approximately 1.41x faster than horizontal/vertical movement.

The handler reads the current cursor position with `hl.get_cursor_pos()` and dispatches an absolute move with `hl.dsp.cursor.move({ x = ..., y = ... })`.

### Pointer buttons

Mouse buttons use `hl.dsp.send_key_state`:

```text
left   -> mouse:272
right  -> mouse:273
middle -> mouse:274
```

A click sends `down` then `up`. Double-click sends one click immediately and schedules the second through a short Hyprland one-shot timer. Hold sends `down` only once; release sends `up`.

Leaving Mouse Mode, reloading the config, or unloading it must release a held left button before state is discarded.

## Runtime safety

Hyprland bind callbacks must not block. Mouse Mode callbacks therefore perform no shell commands, filesystem reads, sleeps, network access, or process waits. All pointer operations use the in-process Hyprland API.

Standalone install/uninstall/verify tools may call normal coreutils such as `mkdir`, `mv`, `ln`, and `readlink`; these run outside the compositor event loop.

## Verification

`lua5.1 verify.lua` performs non-destructive checks:

1. `lua5.1` and `luac5.1` are available;
2. repository-managed Lua files exist;
3. all standalone/project Lua files parse with `luac5.1 -p`;
4. expected symlinks resolve to this repository;
5. installation state is internally consistent;
6. no managed destination or source is under `/usr/share/omarchy`.

`lua5.1 tests/run.lua` runs pure Lua tests for acceleration/reset behavior and any standalone path/state helpers added by v0.1.

Manual acceptance on Omarchy:

1. run `lua5.1 install.lua`;
2. reload Hyprland configuration;
3. confirm existing Omarchy and preserved personal shortcuts still work;
4. press `Super + M` and confirm the `mouse` submap activates;
5. test movement, acceleration, clicks, hold/release, and NumLock on/off variants;
6. exit with `Esc` and confirm normal NumPad behavior returns;
7. rerun the installer and confirm idempotence;
8. run `lua5.1 uninstall.lua` and confirm the previous `bindings.lua` is restored.

## Security and failure handling

- No normal operation requires root privileges.
- No files under `/usr/share/omarchy` are modified.
- Existing user bindings are preserved before replacement.
- Installer aborts rather than overwriting an unexpected backup/state conflict.
- Uninstaller removes only links owned by the active installation state.
- Mouse Mode releases any held pointer button on exit/config unload.
- Hyprland callbacks contain no blocking I/O.

## Non-goals for v0.1

- replacing Omarchy Shell;
- dashboard or system monitoring UI;
- Ghostty/Warp-like workflows;
- project/workspace launcher;
- clipboard or notification daemon replacement;
- kernel/input drivers;
- ydotool/uinput integration;
- custom terminal emulator.

## Success criteria

v0.1 is complete when a fresh current Omarchy installation can clone the repository, run `lua5.1 install.lua` without privilege escalation, preserve its existing user bindings, operate a NumFlow-like Mouse Mode entirely through Hyprland Lua, pass project tests and verification, and cleanly restore the previous configuration through `lua5.1 uninstall.lua`.
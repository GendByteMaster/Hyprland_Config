# Omarchy Workstation v0.1 Design

## Goal

Build the first maintainable layer of a personal workstation on top of the Hyprland configuration shipped by Omarchy, without forking Omarchy or editing `/usr/share/omarchy`.

v0.1 is intentionally narrow:

- repository-as-source-of-truth for personal Hyprland overrides;
- Lua-first implementation for all project-owned behavior;
- NumFlow-like Mouse Mode implemented inside Hyprland's Lua runtime;
- **Num Lock OFF = Mouse Mode ON** and **Num Lock ON = Mouse Mode OFF**;
- safe Lua installer, verifier, and uninstaller;
- preservation and restoration of an existing user `bindings.lua`.

Monitoring, the Warp-like terminal layer, Project Launcher, Command Center, and custom dashboard remain separate later subprojects.

## Architecture principle: Lua-first

All logic owned by this repository is written in Lua unless a later feature has a concrete technical reason not to be. Existing system components remain external: Hyprland, Omarchy, Ghostty, Git, Docker, systemd, and coreutils are orchestrated rather than reimplemented.

Omarchy already installs `lua51`, so standalone project tools target Lua 5.1 and are invoked with `lua5.1`. Hyprland runs its own Lua configuration runtime and supplies the `hl` API.

No Bash/Python/Rust runtime is introduced by v0.1.

## Omarchy integration boundary

Omarchy loads its defaults first and then user modules including `hypr.bindings`. Its bootstrap adds `~/.config/?.lua` to `package.path`, so `require("hypr.workstation.mouse")` resolves from `~/.config/hypr/workstation/mouse.lua`.

Project files never modify `/usr/share/omarchy`.

## Repository layout

```text
Hyprland_Config/
├── hypr/
│   ├── bindings.lua
│   └── workstation/
│       ├── mouse.lua
│       ├── mouse_state.lua
│       └── numlock_store.lua
├── lua/
│   └── workstation/
│       ├── command.lua
│       ├── paths.lua
│       ├── install_state.lua
│       ├── installer.lua
│       ├── uninstaller.lua
│       └── verifier.lua
├── tests/
│   ├── run.lua
│   ├── mouse_state_test.lua
│   ├── numlock_store_test.lua
│   └── mouse_test.lua
├── install.lua
├── uninstall.lua
├── verify.lua
└── README.md
```

`mouse_state.lua` contains compositor-independent acceleration state. `numlock_store.lua` contains session-scoped Num Lock mode persistence. `mouse.lua` is the Hyprland adapter.

## Installation model

The repository is the source of truth. `lua5.1 install.lua` manages only:

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

The project wrapper loads that preserved file before registering workstation bindings, so existing personal bindings continue to work while v0.1 is installed.

A data-only state file under `~/.local/state/hyprland-config/` records the active repository root and backup path. The installer is idempotent and does not require `sudo`, `pkexec`, input-group membership, `/dev/uinput`, or a daemon.

## Num Lock ownership model

Num Lock is the mode-state source:

```text
Num Lock OFF -> Mouse Mode ON
Num Lock ON  -> Mouse Mode OFF / normal NumPad
```

`mouse.lua` sets:

```text
input.numlock_by_default = true
```

so a fresh Hyprland instance starts in the safe/default state: Num Lock ON and Mouse Mode OFF.

`Num_Lock` is registered with `o.rebind` and these flags:

- `submap_universal = true` so Num Lock can always leave Mouse Mode;
- `non_consuming = true` so the real Num Lock key event still propagates and the keyboard lock state changes normally.

`Super + M` is not owned by v0.1.

### Reload synchronization

The current logical Num Lock state is written as data to:

```text
$XDG_RUNTIME_DIR/hyprland-config-numlock-<HYPRLAND_INSTANCE_SIGNATURE>.state
```

The file contains only `on` or `off` and is scoped to the current Hyprland instance.

On config reload, the new Lua state reads the same instance-scoped value. The `mouse` submap is restored from the `config.reloaded` event rather than during config initialization, avoiding dispatcher calls while Hyprland is still loading the config.

On Hyprland shutdown the session-state file is removed. A new Hyprland instance therefore starts from `numlock_by_default = true` rather than inheriting stale state.

## Mouse Mode

When Num Lock is OFF, the Hyprland submap `mouse` owns the NumPad mappings:

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
Num Lock -> leave Mouse Mode by turning Num Lock ON
```

There is no independent `Esc` exit in v0.1 because that would allow Mouse Mode OFF while Num Lock remained OFF and break the state invariant.

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

Leaving Mouse Mode, reloading the config, or unloading it must release a held left button before movement state is discarded.

## Runtime safety

Normal Mouse Mode callbacks perform no shell commands, process waits, network access, or privileged input injection. Pointer operations use the in-process Hyprland API.

The only runtime filesystem operation is the tiny session state file written when Num Lock changes and read when the Lua configuration is reconstructed. It is data-only and located under `XDG_RUNTIME_DIR`.

Standalone install/uninstall/verify tools may call ordinary coreutils outside the compositor event loop.

## Verification

`lua5.1 verify.lua` performs non-destructive checks:

1. `lua5.1` and `luac5.1` are available;
2. repository-managed Lua files exist;
3. project Lua files parse with `luac5.1 -p`;
4. expected symlinks resolve to this repository;
5. installation state is internally consistent;
6. no managed destination or source is under `/usr/share/omarchy`.

`lua5.1 tests/run.lua` covers acceleration, Num Lock session-state persistence, Hyprland adapter behavior, installer, uninstaller, and verifier logic.

Manual acceptance on Omarchy:

1. run `lua5.1 install.lua`;
2. run `hyprctl reload`;
3. confirm Num Lock starts ON and normal NumPad behavior works;
4. press Num Lock so it becomes OFF and confirm Mouse Mode activates;
5. test movement, acceleration, clicks, hold/release, and NumLock-off aliases;
6. press Num Lock again so it becomes ON and confirm normal NumPad behavior returns;
7. while Num Lock is OFF, run `hyprctl reload` and confirm Mouse Mode is restored after reload;
8. rerun the installer and confirm idempotence;
9. run `lua5.1 uninstall.lua` and confirm the previous `bindings.lua` is restored.

## Security and failure handling

- No normal operation requires root privileges.
- No files under `/usr/share/omarchy` are modified.
- Existing user bindings are preserved before replacement.
- Installer aborts rather than overwriting unexpected backup/state conflicts.
- Uninstaller removes only links owned by the active installation state.
- Mouse Mode releases any held pointer button on exit/config unload.
- No `ydotool`, `/dev/uinput`, input group, or privileged daemon is used.

## Non-goals for v0.1

- replacing Omarchy Shell;
- dashboard or system monitoring UI;
- Ghostty/Warp-like workflows;
- project/workspace launcher;
- clipboard or notification daemon replacement;
- kernel/input drivers;
- custom terminal emulator.

## Success criteria

v0.1 is complete when a fresh current Omarchy installation can clone the repository, run `lua5.1 install.lua` without privilege escalation, preserve its existing user bindings, use Num Lock OFF as a NumFlow-like Mouse Mode and Num Lock ON as normal NumPad mode, survive `hyprctl reload` without losing that relationship, pass project tests and verification, and cleanly restore the previous configuration through `lua5.1 uninstall.lua`.

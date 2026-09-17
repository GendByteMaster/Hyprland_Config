# Hyprland_Config

Personal Lua-first workstation layer for the Hyprland configuration shipped by Omarchy.

This project does **not** fork Omarchy, replace Hyprland, or edit `/usr/share/omarchy`. Omarchy remains the base system; this repository owns only selected user overrides under `~/.config/hypr`.

## v0.1

The first release focuses on a safe foundation and a NumFlow-like keyboard Mouse Mode.

### Architecture

```text
Omarchy
  └─ Hyprland
      └─ ~/.config/hypr/bindings.lua
          ├─ preserved personal bindings
          └─ hypr.workstation.mouse
              ├─ Num Lock state bridge
              ├─ global conditional NumPad binds
              ├─ cursor movement
              ├─ acceleration
              ├─ mouse buttons
              └─ optional PipeWire sound feedback
```

Project-owned behavior is Lua-first. v0.1 introduces no Bash, Python, Rust, `ydotool`, `/dev/uinput`, privileged daemon, `sudo`, or `pkexec` requirement.

Omarchy already ships Lua 5.1 for standalone tooling. Hyprland supplies the Lua API used by Mouse Mode. Optional audio feedback uses the existing PipeWire `pw-play` utility when available.

## Mouse Mode

Num Lock is the mode switch:

```text
Num Lock OFF -> Mouse Mode ON
Num Lock ON  -> Mouse Mode OFF / normal NumPad
```

The project sets `numlock_by_default = true`, so a fresh Hyprland session starts with normal NumPad behavior. Mouse Mode does **not** enter a Hyprland submap. Instead, the NumPad bindings stay in the global keymap and use Hyprland's `auto_consuming` behavior: while Num Lock is off they consume the NumPad event and perform the mouse action; while Num Lock is on they return `{ ok = false }` so the original key event passes through normally.

Keeping Mouse Mode out of a submap is intentional: Omarchy's regular global shortcuts such as `Super + 1..10`, `Super + Tab`, and `Super + Arrow` remain available while Mouse Mode is active.

`Num_Lock` is registered as a `submap_universal` and `non_consuming` bind so it continues to work if another Hyprland submap is active and the real Num Lock state still changes. `Super + M` is not used by v0.1.

| Key while Num Lock is OFF | Action |
| --- | --- |
| NumPad 8 | Move up |
| NumPad 2 | Move down |
| NumPad 4 | Move left |
| NumPad 6 | Move right |
| NumPad 7 | Move up-left |
| NumPad 9 | Move up-right |
| NumPad 1 | Move down-left |
| NumPad 3 | Move down-right |
| NumPad / | Select Left Button mode (LMB) |
| NumPad * | Select Right Button mode (RMB) |
| NumPad - | Select Middle Button mode (MMB) |
| NumPad 5 | Click selected button |
| NumPad + | Double-click selected button |
| NumPad 0 | Hold selected button |
| NumPad . | Release held button |
| Num Lock | Return to normal NumPad |

The mouse-button controls use a Windows Mouse Keys-style selection model: `/`, `*`, and `-` change the active button mode without clicking immediately. The HUD shows the currently selected `LMB`, `RMB`, or `MMB` mode. `5`, `+`, `0`, and `.` then operate on that selected button. Both numeric keypad symbols and their NumLock-off navigation aliases are registered where applicable.

Movement accelerates while a direction is held:

```text
repeats 1-2   -> 3 px
repeats 3-5   -> 6 px
repeats 6-10  -> 12 px
repeats 11+   -> 24 px
```

Diagonal movement is normalized so it is not faster than horizontal/vertical movement.

### Num Lock sound feedback

Num Lock changes have two distinct short cues from the open-source [UI SFX](https://uisfx.com/) `mechanical` pack:

```text
Num Lock OFF -> Mouse Mode ON  -> mechanical / toggle-on
Num Lock ON  -> normal NumPad   -> mechanical / toggle-off
```

The generated UI SFX audio assets are CC0-1.0. They are vendored as Base64 text under `assets/sounds/` and decoded during install/reinstall to:

```text
~/.local/share/hyprland_config/sounds/toggle-on.ogg
~/.local/share/hyprland_config/sounds/toggle-off.ogg
```

Playback is asynchronous and best-effort through `pw-play`. Missing audio files, a missing PipeWire playback utility, or playback failure never prevents Num Lock or Mouse Mode from changing. HUD feedback remains the visible source of state.

### Reload synchronization

The Mouse Mode state is kept in a tiny data file under `XDG_RUNTIME_DIR`, scoped by the current `HYPRLAND_INSTANCE_SIGNATURE`.

This means:

- `hyprctl reload` preserves `Num Lock OFF -> Mouse Mode ON`;
- a new Hyprland instance starts clean with Num Lock ON;
- reload and submap changes release any held virtual mouse button;
- cursor movement and button actions do not require an external input daemon or privileged process;
- optional Num Lock audio launches a short local `pw-play` process and never participates in mouse-state correctness.

## Install

Clone the repository, check out the feature/release branch you want to test, then run:

```bash
lua5.1 install.lua
```

The installer manages these Hyprland/Omarchy symlink targets:

```text
~/.config/hypr/bindings.lua
~/.config/hypr/workstation
~/.config/omarchy/plugins/gendbyte.mouse-hud
```

It also materializes the two local UI SFX files under `~/.local/share/hyprland_config/sounds/`.

Existing Hyprland files are preserved under:

```text
~/.local/state/hyprland_config/backups/<timestamp>/
```

The managed `bindings.lua` loads a preserved previous user bindings file first, then registers the workstation overrides. `Num_Lock` is intentionally claimed with `o.rebind` for Mouse Mode.

After installation reload Hyprland:

```bash
hyprctl reload
```

For an already installed checkout, the repository also provides:

```bash
lua5.1 reinstall.lua
```

It uninstalls and reinstalls the managed links, refreshes the local sound assets, verifies the installation, reloads Hyprland, and checks `hyprctl configerrors` before reporting success.

## Verify

```bash
lua5.1 verify.lua
```

Verification checks the Lua 5.1 runtime/compiler, repository files, install state, managed symlink ownership, preserved bindings marker, repository safety, and Lua syntax.

Run the unit/integration suite from the repository root with:

```bash
lua5.1 tests/run.lua
```

## Uninstall

```bash
lua5.1 uninstall.lua
```

The uninstaller refuses to remove a managed path if it no longer points to this installation. When the installation replaced previous bindings/workstation files, those files are restored from the recorded backup.

Reload Hyprland afterwards:

```bash
hyprctl reload
```

## Repository layout

```text
assets/
  sounds/
    uisfx-mechanical-toggle-on.ogg.b64
    uisfx-mechanical-toggle-off.ogg.b64
    LICENSE-UI-SFX

hypr/
  bindings.lua
  workstation/
    mouse.lua
    mouse_state.lua
    numlock_store.lua
    sound.lua

lua/workstation/
  command.lua
  paths.lua
  install_state.lua
  installer.lua
  sound_assets.lua
  uninstaller.lua
  verifier.lua

tests/
  run.lua
  testlib.lua
  mouse_state_test.lua
  numlock_store_test.lua
  mouse_test.lua
  numlock_sound_test.lua
  sound_test.lua
  sound_assets_test.lua
  installer_test.lua
  uninstaller_test.lua
  verifier_test.lua

install.lua
reinstall.lua
uninstall.lua
verify.lua
```

## Roadmap

- **v0.1** — Omarchy integration + Num Lock Mouse Mode
- **v0.2** — system monitoring/dashboard
- **v0.3** — Ghostty/Warp-like workflow layer
- **v0.4** — Project Launcher/workspace orchestration
- **v0.5** — unified Command Center and optional custom shell UI

The later layers keep the same rule: use Lua for project-owned logic where it is technically appropriate, while keeping Hyprland, Omarchy, Ghostty, Git, Docker, systemd and other system components as external foundations rather than reimplementing them.

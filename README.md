# Hyprland_Config

A Lua-first workstation layer for **Hyprland** with optional Omarchy integration.

The project does **not** fork Hyprland or Omarchy and does not edit `/usr/share/omarchy`. It owns a small set of user-level configuration links, launcher files, state, and optional Omarchy plugins.

## Current scope

- **v0.1** — Num Lock Mouse Mode
- **v0.2** — System Monitor topbar + `btop`
- **v0.4** — Workspace Overview + All-Monitor Window Switcher
- **v0.3** — Project Launcher / Terminal Workflow Layer
- **v0.3.1** — Managed external Omarchy plugin integration
- **v0.3.2** — Omarchy desktop hotkeys + optional AmneziaVPN integration

The architecture is Hyprland-first. Omarchy-specific pieces are adapters or optional plugins rather than a runtime requirement for the core workstation layer.

## Requirements

Core v0.3 / v0.3.1:

- Hyprland 0.55+
- Lua 5.1
- `luac5.1`
- Quickshell with the `qs` CLI

Optional capabilities are detected at runtime. Depending on which project actions you use, tools such as Git, Cargo, npm/pnpm/yarn/bun, pytest, Docker, `wl-copy`, an editor, or a file manager may also be used.

Omarchy is optional. When present, the installer can also manage the Mouse Mode HUD and System Monitor plugins. v0.3.1 additionally manages explicitly pinned third-party Omarchy plugins without making them a core runtime dependency.

## v0.1 — Mouse Mode

Num Lock is the mode switch:

```text
Num Lock OFF -> Mouse Mode ON
Num Lock ON  -> Mouse Mode OFF / normal NumPad
```

Mouse Mode stays in the global Hyprland keymap rather than entering a dedicated submap, so normal `Super + ...` shortcuts continue to work.

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
| NumPad / | Select Left Button mode |
| NumPad * | Select Right Button mode |
| NumPad - | Select Middle Button mode |
| NumPad 5 | Click selected button |
| NumPad + | Double-click |
| NumPad 0 | Hold selected button |
| NumPad . | Release held button |
| Num Lock | Return to normal NumPad |

The project sets `numlock_by_default = true`. Some Hyprland/XKB combinations continue to emit navigation keysyms such as `KP_End` with Num Lock on, so the workstation layer proxies those aliases back to ordinary digits while normal NumPad mode is active.

Mouse Mode also keeps the cursor visible while keyboard-driven movement is active. Optional mode-change sound feedback uses local UI SFX through `pw-play` when available; audio failure never blocks Mouse Mode.

The session Num Lock state is stored under `XDG_RUNTIME_DIR` and scoped to the current Hyprland instance, so `hyprctl reload` preserves Mouse Mode without carrying stale state into a new session.

## v0.2 — System Monitor

On Omarchy, the optional `gendbyte.system-monitor` plugin adds topbar telemetry including:

- CPU utilization
- CPU frequency
- RAM utilization and used/total memory
- network RX/TX
- optional GPU utilization
- optional temperature

Clicking the monitor uses Omarchy's terminal launcher path to open or focus `btop`.

This feature is optional in v0.3. A plain Hyprland installation does not create Omarchy plugin directories and does not require the Omarchy CLI.

## v0.4 — Workspace Overview + All-Monitor Window Switcher

v0.4 adds two related but distinct Quickshell surfaces.

### Workspace Overview

```text
Super + Tab
```

Shows the focused Hyprland workspace with live compositor-backed previews and the workspace strip.

### All-Monitor Window Switcher

```text
Ctrl + Alt + Tab
Super + F10
```

Shows one persistent task switcher on the currently focused physical monitor. Its window list includes windows from every Hyprland workspace that is currently active on any physical monitor, so windows on secondary displays remain available without including hidden/inactive workspaces.

The switcher is MRU ordered from Hyprland `focusHistoryID` (most recent first), shows each window's physical monitor name, and scales its grid against both available width and height. Preview sizing is automatic: one window receives a large card, two windows are arranged side by side, 3–4 use medium cards, and denser sets progressively reduce the preview cap.

Keyboard and pointer behavior:

- `Up/Down/Left/Right` moves the selected window
- `Enter` focuses the selected window, including windows on another physical monitor
- pointer hover updates selection
- click focuses the selected window
- `Esc` closes the switcher

`Super + F10` remains the persistent all-monitor task switcher. In **Try Omarchy for Windows**, `Super + F9` remains the Workspace Overview fallback. Windows may intercept Win/Super shortcuts unless QEMU raw keyboard grab is active, so use `Ctrl + Alt + G` if the host consumes the chord.

Workspace Overview uses on-demand keyboard focus rather than permanent exclusive ownership. When Overview is already open, pressing `Super` closes Overview immediately and returns the key to the normal Hyprland/Omarchy flow; the user's existing single-`Super` binding can then open Omarchy Menu on release and take focus. The overview does not duplicate the menu command itself, avoiding double-toggle behavior.

The overview also follows the active Omarchy theme. On startup the wrapper resolves `$XDG_STATE_HOME/omarchy/current/theme/colors.toml` (normally `~/.local/state/omarchy/current/theme/colors.toml`, with the legacy config path as fallback). Each time Overview opens it refreshes `background`, `foreground`, `accent`, `muted`, selection, and surface colors from that palette, so built-in and user-installed Omarchy themes are applied automatically. If no Omarchy palette is available, conservative dark/orange fallback colors are used.

Window previews use one-shot Quickshell Hyprland/Wayland `ScreencopyView` snapshots; the implementation does not use screenshot-file polling, continuous live capture, or a render-loop `hyprctl` poller.

## Windows-like Interaction Layer

Tracked separately in **#7**, the Windows-like interaction layer keeps familiar keyboard semantics in a dedicated Hyprland module instead of coupling them to Workspace Overview.

```text
Alt + Tab                  → next window
Alt + Shift + Tab          → previous window

Super + Shift + Left       → move active window to monitor on the left
Super + Shift + Right      → move active window to monitor on the right

Ctrl + Super + Left        → previous existing workspace on current monitor
Ctrl + Super + Right       → next existing workspace on current monitor
```

The implementation uses native Hyprland Lua dispatchers:

- `hl.dsp.window.cycle_next(...)` for forward/reverse window cycling;
- `hl.dsp.window.move({ monitor = "l"|"r" })` for physical-monitor transfer;
- `hl.dsp.focus({ workspace = "m-1"|"m+1" })` for existing-workspace navigation on the current monitor.

The layer intentionally does **not** override `Super + Left/Right`, `Super + Up/Down`, `Super + D`, or `Super + M` yet, because those keys can conflict with useful Hyprland/Omarchy layout semantics.

`Ctrl + Alt + Tab` remains part of Workspace Overview because it directly opens the persistent All-Monitor Window Switcher surface.

## v0.3 — Project Launcher

Press:

```text
Super + F8
```

to toggle a centered floating Quickshell Project Launcher.

`Super + H` is intentionally left free.

When running under **Try Omarchy for Windows**, the Windows host may intercept some Super/Win shortcuts before Hyprland receives them. If `Super + F8` does not reach the guest, focus the Try Omarchy window and press `Ctrl + Alt + G` to grab raw keyboard input; press it again to release the grab.

The launcher is keyboard-first and uses the approved two-pane layout:

```text
┌──────────────────────────────────────────────────────────┐
│ Search projects...                                      │
├───────────────────────────┬──────────────────────────────┤
│ Projects                  │ Actions                      │
│                           │                              │
│ NumFlow                   │ Open Shell                   │
│ Voxelyra                  │ Git Status                   │
│ Hyprland_Config           │ Tests                        │
│ ...                       │ Dev Server                   │
│                           │ Docker Compose               │
│                           │ Open Editor                  │
└───────────────────────────┴──────────────────────────────┘
```

Keyboard behavior:

- type to fuzzy-filter projects
- `Up/Down` moves through projects or actions
- `Tab` / `Right` enters the Actions pane
- `Left` returns from Actions
- `Enter` runs the selected action
- `Esc` closes the launcher

Queries are debounced. Project detection and action logic stay in Lua; QML only renders the UI and talks to the versioned JSON backend.

### Project discovery

The default discovery root is:

```text
~/Repository
```

Git project roots are discovered with bounded depth; the default maximum depth is 4. Common heavy/generated directories are pruned, symlink Git markers are rejected, and canonical paths are used as stable project IDs.

Additional roots can also be added directly from the launcher with **Add folder**. The launcher now uses its own dark, keyboard-first directory browser instead of the native desktop folder dialog. Navigate with `Up/Down`, open a directory with `Enter`, go up with `Backspace` or `Left`, then choose **Use this folder**. The selected root is persisted in launcher state and rescanned immediately. When no manual `projects.lua` exists, the first UI-selected root replaces the implicit `~/Repository` fallback so a missing default directory does not keep producing warnings.

Explicit non-Git projects, hidden paths, application preferences, and action overrides can still be configured in:

```text
~/.config/hyprland-workstation/projects.lua
```

Example:

```lua
return {
  roots = {
    "~/Repository",
    "~/Projects",
  },

  projects = {
    { path = "~/scratch/demo", name = "Demo" },
  },

  hidden = {
    "~/Repository/archive",
  },

  max_depth = 4,

  apps = {
    terminal = "auto",
    editor = { "code", "--reuse-window" },
    file_manager = { "thunar" },
  },

  overrides = {
    ["~/Repository/example"] = {
      actions = {
        {
          id = "custom-dev",
          label = "Custom Dev",
          argv = { "bash", "-lc", "echo ok" },
          terminal = true,
          shell = true,
          confirm = true,
        },
      },
    },
  },
}
```

If the file is missing, safe defaults are used. A malformed config is ignored with a warning rather than rewritten.

### Favorites, recent projects, and cache

Favorites and recent-project ordering are stored as data under the XDG state directory. Recent history is bounded.

Discovery results are cached under the XDG cache directory so ordinary fuzzy queries do not rescan the filesystem on every keypress.

With an empty search query, favorites are shown first, then recent projects, then remaining projects. With a text query, fuzzy match relevance remains stronger than favorite/recent boosts.

### Automatic action detection

Universal actions include:

- Open Shell
- Open Editor
- Open File Manager
- Favorite / Unfavorite
- Copy Path when a clipboard tool is available

Project-specific actions are detected from project files and runtime capabilities.

Supported v0.3 detection includes:

- Git
- Rust / Cargo
- Node package scripts
- Python / pytest
- Docker Compose

For Node projects, the package manager is selected from lockfiles with npm as the fallback. Only declared `dev`, `test`, and `build` scripts are exposed.

Missing executables disable only the affected action and show a reason instead of disabling the launcher.

Potentially destructive actions such as `Compose Down` require confirmation.

### Terminal and desktop adapters

Interactive actions run in a terminal at the selected project's canonical root. Quick actions such as editor, file manager, and copy path run directly.

In `apps.terminal = "auto"` mode, the generic adapter prefers `xdg-terminal-exec`. It can also use a single unambiguous supported terminal or an exact supported `$TERMINAL` preference.

Known terminal adapters include:

- Foot
- Ghostty
- Kitty
- Alacritty

On Omarchy, v0.3 still uses the generic explicit-cwd terminal path so project actions do not inherit an unrelated active terminal directory.

All action arguments are handled as argv data. Project paths and action arguments are not concatenated into an unquoted command string.

## v0.3.1 — Managed external Omarchy plugins

Third-party Omarchy plugins are declared in `omarchy/external-plugins.lua` and pinned to exact Git commits. Their source is stored under:

```text
~/.local/share/hyprland_config/external-plugins/
```

Omarchy sees each managed plugin through an owned symlink under
`~/.config/omarchy/plugins/`. Existing user-managed plugin paths are never
silently replaced.

The initial managed set is:

- Orbit
- Clipboard Manager
- Agent Orchestrator

On Omarchy, `install.lua` and `reinstall.lua` reconcile these plugins after
the core workstation layer is installed. External network/plugin failures are
reported but do not roll back or corrupt the core Hyprland_Config installation.

Manual lifecycle commands are also available:

```bash
lua5.1 omarchy-plugins.lua sync
lua5.1 omarchy-plugins.lua remove
```

Pins never follow `main` automatically. Upgrades require reviewing upstream
changes and changing the exact commit in the manifest. See
`docs/omarchy-external-plugins.md` for the ownership and security model.


## v0.3.2 — Omarchy desktop integrations

When the managed components are available, the workstation layer adds these conditional shortcuts:

| Shortcut | Action |
| --- | --- |
| `Alt + Tab` | Orbit window switcher |
| `Super + V` | Clipboard Manager |
| `Super + A` | Agent Orchestrator |
| `Super + Alt + V` | Launch AmneziaVPN |

The Windows-like native `Alt + Tab` cycle remains the fallback. The pinned Orbit `bindings.lua` is loaded only when the managed Orbit plugin exists, so Orbit can replace that fallback without making the core Hyprland configuration depend on the plugin.

Plugin/application hotkeys are registered only when their target is available. Missing optional components therefore do not reserve those key combinations.

On Arch/Omarchy, `install.lua` and `reinstall.lua` also try to install AmneziaVPN when it is missing. The integration prefers `yay`, falls back to `paru`, and explicitly installs:

```text
aur/amneziavpn-bin
```

with `--needed --noconfirm`. Failure to install this optional system package is reported but does not roll back or fail the core Hyprland_Config installation. The repository does not own or remove the system AmneziaVPN package during uninstall.

## Install

Clone the repository and run from the checkout you want to use:

```bash
lua5.1 install.lua
```

v0.3 requires Quickshell's `qs` CLI before the installer changes managed targets.

The core installation manages:

```text
~/.config/hypr/bindings.lua
~/.config/hypr/workstation
~/.local/bin/hyprland-workstation-launcher
~/.config/quickshell/gendbyte-project-launcher
```

On Omarchy, it can additionally manage:

```text
~/.config/omarchy/plugins/gendbyte.mouse-hud
~/.config/omarchy/plugins/gendbyte.system-monitor
```

Existing Hyprland files are preserved under:

```text
~/.local/state/hyprland_config/backups/<timestamp>/
```

Install ownership is recorded in a versioned state file so uninstall/verify know which optional components belong to this installation.

After installation:

```bash
hyprctl reload
hyprctl configerrors
```

### Reinstall / update

For an existing installation:

```bash
lua5.1 reinstall.lua
```

Reinstall is **reconciliation**, not uninstall-then-install. Existing managed links are checked in place, missing components are added, install state is migrated when necessary, verification runs, and Hyprland is reloaded only after verification succeeds.

## Verify

```bash
lua5.1 verify.lua
```

Verification checks:

- repository safety
- Lua runtime/compiler
- required repository files
- install state
- managed Hyprland links
- Project Launcher links
- Quickshell availability when the launcher is installed
- preserved bindings
- optional Omarchy links/validation when those components are managed
- Lua syntax

Omarchy checks are skipped successfully for a generic Hyprland-only installation.

Run the complete automated suite from the repository root with:

```bash
lua5.1 tests/run.lua
find . -name '*.lua' -type f -print0 | xargs -0 -r -n1 luac5.1 -p
bash -n bin/hyprland-workstation-launcher
```

## Uninstall

```bash
lua5.1 uninstall.lua
```

The uninstaller refuses to delete a managed target that no longer points to this repository. Only components recorded as owned by the active installation are removed.

A generic Hyprland installation therefore uninstalls without requiring Omarchy. An Omarchy installation disables the managed System Monitor plugin before deleting its link.

Previously preserved Hyprland configuration is restored from the recorded backup.

Reload afterwards:

```bash
hyprctl reload
```

## Repository layout

```text
hypr/
  bindings.lua
  workstation/
    mouse.lua
    project_launcher.lua
    ...

quickshell/
  gendbyte-project-launcher/
    shell.qml
    ProjectLauncher.qml
    components/

lua/workstation/
  action_executor.lua
  adapters/
  project_actions.lua
  project_cache.lua
  project_config.lua
  project_discovery.lua
  project_launcher_cli.lua
  project_model.lua
  project_search.lua
  project_state.lua
  project_types.lua
  launcher_protocol.lua
  installer.lua
  omarchy_plugins.lua
  uninstaller.lua
  verifier.lua
  ...

omarchy/
  external-plugins.lua
  plugins/
    gendbyte.mouse-hud/
    gendbyte.system-monitor/

bin/
  hyprland-workstation-launcher

project-launcher.lua
omarchy-plugins.lua
install.lua
reinstall.lua
uninstall.lua
verify.lua
```

## Roadmap

- **v0.1** — Num Lock Mouse Mode
- **v0.2** — System Monitor / `btop` integration
- **v0.4** — Workspace Overview + All-Monitor Window Switcher
- **v0.3** — Project Launcher + Terminal Workflow Layer
- **v0.3.1** — managed external Omarchy plugins
- **v0.3.2** — Omarchy desktop hotkeys + optional AmneziaVPN integration
- **v0.4** — workspace orchestration around projects
- **v0.5** — unified Command Center and optional custom shell UI

v0.3 intentionally stops short of full workspace orchestration. It provides project discovery, search, actions, and terminal/application launch primitives; v0.4 owns broader workspace lifecycle behavior.

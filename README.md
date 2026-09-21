# Hyprland_Config

A Lua-first workstation layer for **Hyprland** with optional **Omarchy** integration.

`Hyprland_Config` adds keyboard-first window/workspace controls, Num Lock mouse control, Quickshell productivity surfaces, Omarchy status plugins, pinned third-party plugins, and optional desktop integrations without forking Hyprland or Omarchy and without modifying `/usr/share/omarchy`.

The design is intentionally modular:

- **Hyprland-first** - core workstation behavior does not require Omarchy.
- **User-level ownership** - managed targets are symlinked from this repository and backed up before replacement.
- **Optional integrations stay optional** - network/plugin/application failures do not corrupt the core workstation installation.

## Status

| Version | Implemented feature |
| --- | --- |
| **v0.1** | Num Lock Mouse Mode |
| **v0.2** | Omarchy System Monitor + `btop` integration |
| **v0.3** | Project Launcher / terminal workflow layer |
| **v0.3.1** | Managed external Omarchy plugins |
| **v0.3.2** | Desktop integration hotkeys + optional AmneziaVPN |
| **v0.4** | Workspace Overview + All-Monitor Window Switcher |
| - | Windows-like Hyprland interaction layer |

## Requirements

Core workstation layer:

- Hyprland 0.55+
- Lua 5.1
- `luac5.1`
- Quickshell with the `qs` CLI

Omarchy is optional. When present, the installer can additionally manage repository-owned Omarchy plugins, pinned third-party plugins, desktop integration hotkeys, and the optional AmneziaVPN installation path.

Project Launcher actions are capability-driven. Depending on the selected project, optional tools can include Git, Cargo, npm/pnpm/yarn/bun, pytest, Docker Compose, `wl-copy`, an editor, a file manager, and a supported terminal emulator.

## Quick start

Clone and install:

```bash
git clone https://github.com/GendByteMaster/Hyprland_Config.git ~/Hyprland_Config
cd ~/Hyprland_Config
lua5.1 install.lua
```

Update an existing installation:

```bash
cd ~/Hyprland_Config
git switch master
git pull --ff-only origin master
lua5.1 reinstall.lua
```

Verify:

```bash
lua5.1 verify.lua
```

## Keyboard map

### Desktop and window shortcuts

| Shortcut | Action | Availability |
| --- | --- | --- |
| `Alt + Tab` | Orbit window switcher | Orbit installed |
| `Alt + Tab` | Native next-window cycle | fallback when Orbit is unavailable |
| `Alt + Shift + Tab` | Orbit/native previous-window cycle | Orbit or fallback |
| `Super + Shift + Left` | Move active window to physical monitor on the left | core |
| `Super + Shift + Right` | Move active window to physical monitor on the right | core |
| `Ctrl + Super + Left` | Previous existing workspace on current monitor | core |
| `Ctrl + Super + Right` | Next existing workspace on current monitor | core |
| `Super + Tab` | Workspace Overview | core |
| `Ctrl + Alt + Tab` | Persistent All-Monitor Window Switcher | core |
| `Super + F10` | All-Monitor Window Switcher | core |
| `Super + F9` | Workspace Overview fallback | Try Omarchy only |
| `Super + F8` | Project Launcher | core |
| `Super + V` | Clipboard Manager | managed plugin installed |
| `Super + A` | Agent Orchestrator | managed plugin installed |
| `Super + Alt + V` | AmneziaVPN | application installed |

When Orbit is available, its pinned bindings also provide:

| Shortcut | Orbit action |
| --- | --- |
| `Super + Z` | Snap Layouts |
| `Super + Shift + Z` | Window mode picker |
| `Super + Q` | Direct next-window cycle |
| `Super + Shift + Q` | Direct previous-window cycle |

Optional shortcuts are registered only when their target exists. Missing plugins/applications therefore do not reserve their key combinations.

### Try Omarchy on Windows

Windows can intercept Win/Super chords before they reach Hyprland. If that happens, focus the Try Omarchy window and toggle QEMU raw keyboard grab with:

```text
Ctrl + Alt + G
```

`Super + F9` is kept as an additional Workspace Overview path for Try Omarchy.

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

Additional roots can also be added directly from the launcher with **Add folder**. The launcher now uses its own dark, keyboard-first directory browser instead of the native desktop folder dialog. Navigate with `Up/Down`, open a directory with `Enter`, go up with `Backspace` or `Left`, then choose **Use this folder**. The selected root is persisted in launcher state and rescanned immediately. When no manual `projects.toml` exists, the first UI-selected root replaces the implicit `~/Repository` fallback so a missing default directory does not keep producing warnings.

Explicit non-Git projects, hidden paths, application preferences, and action overrides are configured as **data-only TOML** in:

```text
~/.config/hyprland-workstation/projects.toml
```

Example:

```toml
roots = [
  "~/Repository",
  "~/Projects",
]
hidden = ["~/Repository/archive"]
max_depth = 4

[[projects]]
path = "~/scratch/demo"
name = "Demo"

[apps]
terminal = "auto"
editor = ["code", "--reuse-window"]
file_manager = ["thunar"]

[[overrides."~/Repository/example".actions]]
id = "custom-dev"
label = "Custom Dev"
argv = ["pnpm", "dev"]
terminal = true
confirm = true
```

The TOML parser is intentionally strict and data-only: it does not use `dofile`, `load`, Lua expressions, functions, or metatables. The old `projects.lua` path is never executed; if it is present without `projects.toml`, the launcher falls back to safe defaults and reports a migration warning.

A malformed TOML config is ignored with a warning rather than rewritten. Configuration is still trusted local policy: explicit `argv` entries intentionally launch the programs you configure, so do not install unreviewed project configuration files.

A ready-to-copy example for the current development repositories lives at:

```text
examples/projects.toml
```

It configures `Voxelyra_Nexus`, `VoxClip`, `ForgeGuard`, `NumFlow`, `Veridyn`, `submart_backend`, and `Hyprland_Config` with a conservative first workspace layout: editor on workspace 1 and an interactive project shell on workspace 2.

Install it from the repository root:

```bash
mkdir -p ~/.config/hyprland-workstation
cp examples/projects.toml ~/.config/hyprland-workstation/projects.toml
```

The example deliberately does not enable singleton class/title matching yet. Capture the real compositor metadata with `hyprctl clients -j` first, then add `match` only for verified application identities.

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

On x86_64 Arch/Omarchy, `install.lua` and `reinstall.lua` also try to install AmneziaVPN when it is missing. The installer is pinned to the official stable GitHub release `5.0.1.5`:

```text
AmneziaVPN_5.0.1.5_linux_x64.run
sha256: ddb471efbe149232aa98c75534f98d42114b15fdc7976802f8feaeba320bc791
```

The file is downloaded from the official `amnezia-vpn/amnezia-client` release, verified with SHA-256, and then invoked through the Qt Installer Framework unattended path. The pinned version/checksum are intentionally reviewable rather than following an unpinned package source. Failure to install this optional application is reported but does not roll back or fail the core Hyprland_Config installation. The repository does not own or remove the system AmneziaVPN installation during uninstall.

The AmneziaVPN hotkey launches the client with `QT_QPA_PLATFORM=xcb`, which is the compatibility path for the current Linux client under a Wayland/Hyprland session.

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

## v0.5 — Workspace Orchestrator (in development)

v0.5 extends the Project Launcher from running one project action at a time to opening a declarative development workspace.

Optional logical monitor aliases can be defined at the top level:

```toml
[monitors]
primary = "DP-1"
secondary = "HDMI-A-1"
```

When an alias is not configured, `primary`, `secondary`, and `tertiary` resolve from the current Hyprland monitor set: the focused monitor is first, then the remaining monitors are ordered deterministically by geometry. If a configured/direct monitor is unavailable, the orchestrator falls back deterministically and reports the target as degraded instead of silently pretending the requested placement succeeded.

Workspace orchestration is configured per project under `overrides.<project>.workspace.targets`:

```toml
[[overrides."~/Repository/Voxelyra".workspace.targets]]
name = "editor"
workspace = 1
monitor = "primary"
operation = "editor"
singleton = true
wait_ms = 1200
match.class = "Code"

[[overrides."~/Repository/Voxelyra".workspace.targets]]
name = "backend"
workspace = 2
terminal = true
argv = ["uv", "run", "fastapi", "dev"]

[[overrides."~/Repository/Voxelyra".workspace.targets]]
name = "frontend"
workspace = 3
terminal = true
argv = ["pnpm", "dev"]

[[overrides."~/Repository/Voxelyra".workspace.targets]]
name = "browser"
workspace = 4
operation = "url"
url = "http://localhost:3000"
```

When a project has at least one validated workspace target, Project Launcher adds:

```text
Open Workspace
```

Supported targets:

- `operation = "editor"` — uses the configured/resolved editor adapter;
- `terminal = true` + `argv` — opens a project-root terminal and runs the argv command;
- direct `argv` — launches a process without a terminal;
- `operation = "url"` + `url` — opens through `xdg-open`;
- optional `workspace` — applies a Hyprland workspace exec rule;
- optional `monitor` — accepts a direct monitor name or logical role;
- optional `match` — matches Hyprland clients by `class`, `initial_class`, `title`, and/or `initial_title`;
- optional `singleton = true` — skips launch when a matching mapped window already exists;
- optional `wait_ms` — bounds post-launch matching instead of polling indefinitely.

Workspace configuration is bounded before execution: at most 32 targets, at most 10 seconds of total matching wait budget, and at most 16 monitor aliases. URL targets accept only `http://` and `https://`.

Workspace targets intentionally do **not** support a raw shell flag. Arguments remain structured argv data and are quoted before entering Hyprland's command-string dispatcher. Explicit argv is still trusted local configuration and can intentionally invoke command interpreters if you choose to configure one.

For targets with matching metadata, the orchestrator snapshots Hyprland clients before launch and only treats a later **new** matching address as the launched window. If the pre-launch snapshot is unavailable, it refuses to guess and reports degraded placement.

Initial placement uses Hyprland `exec_cmd(..., rules)`. When an application forks or reuses a process and the new window appears on the wrong location, v0.5 can safely correct a single placement dimension:

- workspace-only target → move the matched window to the requested workspace;
- monitor-only target → move the matched window to the requested monitor.

A target that requests both workspace and monitor is verified after launch, but ambiguous combined correction is deliberately not forced because moving an existing window and workspace between monitors can affect compositor state beyond that one target. A mismatch is surfaced as **degraded**.

Targets are independent. Failed or degraded targets do not hide successfully started targets. Examples:

```text
Workspace: 2 started, 1 failed · backend: terminal unavailable
Workspace: 3 started, 1 degraded · editor: combined workspace+monitor placement could not be verified safely
```

Repeated `Open Workspace` is idempotent for targets configured with `singleton = true`: an already-running matching client is reported as skipped instead of spawning another instance.

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

## Install and ownership model

The installer manages explicit symlinks from the checked-out repository rather than copying an opaque generated configuration into your home directory.

Run:

```bash
lua5.1 install.lua
```

Core managed targets:

```text
~/.config/hypr/bindings.lua
~/.config/hypr/workstation
~/.local/bin/hyprland-workstation-launcher
~/.config/quickshell/gendbyte-project-launcher
~/.local/bin/hyprland-workspace-overview
~/.config/quickshell/gendbyte-workspace-overview
```

On Omarchy, repository-owned plugins can also be linked at:

```text
~/.config/omarchy/plugins/gendbyte.mouse-hud
~/.config/omarchy/plugins/gendbyte.system-monitor
```

Pinned third-party plugins are stored under:

```text
~/.local/share/hyprland_config/external-plugins/<plugin-id>
```

and exposed to Omarchy through owned symlinks under `~/.config/omarchy/plugins/`.

### Existing configuration and backups

Existing Hyprland configuration is preserved under:

```text
~/.local/state/hyprland_config/backups/<timestamp>/
```

Install ownership is tracked in:

```text
~/.local/state/hyprland_config/active.state
```

If an active managed target is replaced or redirected outside this repository, reinstall/uninstall refuses to silently overwrite or delete it.

### Update / reconcile

```bash
cd ~/Hyprland_Config
git switch master
git pull --ff-only origin master
lua5.1 reinstall.lua
```

`reinstall.lua` is reconciliation, not uninstall-then-install. It checks managed links, adds newly introduced components, reconciles repository-owned Omarchy plugins, syncs pinned external plugins, attempts the optional AmneziaVPN install when applicable, verifies the result, and reloads Hyprland only after verification passes.

## Verify and test

Runtime installation verification:

```bash
lua5.1 verify.lua
```

Verification covers repository safety, Lua availability, required repository files, install state, managed Hyprland links, Project Launcher/Workspace Overview links, Quickshell availability, preserved configuration, repository-owned Omarchy plugin links, Omarchy plugin validation where applicable, and Lua syntax.

Generic Hyprland installations skip Omarchy-only runtime checks successfully.

Full development suite:

```bash
lua5.1 tests/run.lua
find . -name '*.lua' -type f -print0 | xargs -0 -r -n1 luac5.1 -p
bash -n bin/hyprland-workstation-launcher
bash -n bin/hyprland-workspace-overview
```

GitHub Actions runs the same test/syntax gates for feature pushes and pull requests.

## Uninstall

```bash
lua5.1 uninstall.lua
```

The uninstaller:

- verifies that managed targets still point to this repository;
- disables/removes repository-owned Omarchy integration when owned;
- removes only owned external plugin sources/symlinks;
- preserves conflicting user-managed plugin paths instead of deleting them;
- restores preserved Hyprland configuration from the recorded backup;
- removes active install state.

The system AmneziaVPN installation is intentionally **not** removed.

Reload Hyprland afterwards if required:

```bash
hyprctl reload
```

## Troubleshooting

### Check the whole installation

```bash
cd ~/Hyprland_Config
lua5.1 verify.lua
```

### Hyprland configuration errors

```bash
hyprctl reload
hyprctl configerrors
```

### Super shortcuts do not work in Try Omarchy on Windows

Toggle raw keyboard grab:

```text
Ctrl + Alt + G
```

### External Omarchy plugins are missing

```bash
cd ~/Hyprland_Config
lua5.1 omarchy-plugins.lua sync
omarchy plugin list
```

Low-level shell rescan:

```bash
omarchy-shell shell rescanPlugins
```

### Check AmneziaVPN

```bash
command -v AmneziaVPN || test -x /opt/AmneziaVPN/client/AmneziaVPN.sh
```

Manual Hyprland/Wayland-compatible launch:

```bash
QT_QPA_PLATFORM=xcb AmneziaVPN
```

Fallback path:

```bash
QT_QPA_PLATFORM=xcb /opt/AmneziaVPN/client/AmneziaVPN.sh
```

## Repository layout

```text
.
|-- hypr/
|   |-- bindings.lua
|   `-- workstation/
|       |-- compat.lua
|       |-- desktop_integrations.lua
|       |-- hud.lua
|       |-- mouse.lua
|       |-- project_launcher.lua
|       |-- windows_shortcuts.lua
|       `-- workspace_overview.lua
|-- lua/workstation/
|   |-- adapters/
|   |-- installer.lua
|   |-- omarchy_plugins.lua
|   |-- optional_apps.lua
|   |-- overview_model.lua
|   |-- project_*.lua
|   |-- telemetry*.lua
|   |-- uninstaller.lua
|   `-- verifier.lua
|-- quickshell/
|   |-- gendbyte-project-launcher/
|   `-- gendbyte-workspace-overview/
|-- omarchy/
|   |-- external-plugins.lua
|   `-- plugins/
|       |-- gendbyte.mouse-hud/
|       `-- gendbyte.system-monitor/
|-- bin/
|   |-- hyprland-workspace-overview
|   `-- hyprland-workstation-launcher
|-- docs/
|-- tests/
|-- install.lua
|-- reinstall.lua
|-- uninstall.lua
|-- verify.lua
|-- omarchy-plugins.lua
|-- project-launcher.lua
`-- telemetry-collector.lua
```

## Design and safety notes

### No Omarchy fork

The project does not patch `/usr/share/omarchy` and does not require a custom Omarchy build.

### Explicit ownership

Managed targets are checked before replacement or deletion. An unrelated file occupying a managed path causes an error instead of being overwritten.

### Restorable configuration

Existing Hyprland configuration is preserved before first install and can be restored during uninstall.

### Pinned third-party code

External Omarchy plugins are pinned to exact Git commits rather than floating branches. Because Omarchy plugins execute as the current user, pin updates should be treated as code-review changes.

### Pinned optional installer

AmneziaVPN is pinned to an exact official release asset and SHA-256 before execution.

### Failure boundaries

Optional external-plugin or VPN failures are reported separately from the core Hyprland workstation installation.

## Roadmap

Implemented milestones are documented above.

Next directions:

- project-aware workspace orchestration;
- tighter Project Launcher <-> workspace lifecycle integration;
- unified **v0.5 Command Center**;
- optional custom shell UI where it adds value without unnecessarily replacing Omarchy.

The project remains intentionally modular: keyboard semantics, project workflow, workspace UI, Omarchy plugins, and optional applications should stay independently replaceable.

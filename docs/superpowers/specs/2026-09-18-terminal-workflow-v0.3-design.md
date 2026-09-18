# Hyprland-first Project Launcher / Terminal Workflow v0.3 Design

## Goal

v0.3 adds a fast, keyboard-first Project Launcher and terminal workflow layer to Hyprland.

The feature is **Hyprland-first**. Omarchy is a supported integration, not a runtime requirement. The launcher must work on a plain supported Hyprland installation and should automatically take advantage of Omarchy defaults when Omarchy is present.

The primary user flow is:

```text
Super + R
  -> floating launcher
  -> select project
  -> select action
  -> run quick action or open a terminal at the project root
```

The UI uses the approved two-pane model: projects on the left, context-aware actions on the right.

## Scope

v0.3 owns these capabilities:

- a centered floating Quickshell Project Launcher;
- automatic Git-project discovery;
- configurable scan roots, with `~/Repository` as the default;
- favorites and recent-project state;
- fuzzy project filtering;
- project-type detection for Git, Rust, Node, Python, and Docker/Compose;
- automatic actions plus per-project manual overrides;
- generic terminal/editor/file-manager adapters;
- an optional Omarchy adapter;
- `Super + R` as the launcher hotkey;
- capability-based installation that does not require Omarchy;
- safe failure behavior when projects or external tools are missing.

v0.3 does **not** build full workspace orchestration. Opening an editor, terminal, browser, Docker stack, and several panes as one coordinated workspace remains v0.4 scope. A unified cross-desktop Command Center remains v0.5 scope.

`Super + H` remains unbound by this project.

## Architectural decision

The core is independent of Omarchy.

```text
Hyprland
   |
   | Super + R
   v
launcher wrapper
   |
   +-- running instance -> IPC toggle
   |
   +-- no instance -> start Quickshell config
                           |
                           v
                    Project Launcher UI
                           |
                           v
                      Lua backend
          +----------------+----------------+
          |                |                |
          v                v                v
   project discovery  action resolver   state/config
          |                |                |
          +----------------+----------------+
                           |
                           v
                        adapters
                    +------+------+
                    |             |
                 generic        omarchy
```

The compositor hotkey callback does only a fast process launch/toggle request. Filesystem scanning, manifest inspection, sorting, and action resolution never run inside the Hyprland event callback.

### Why Quickshell is standalone

The launcher is a standalone Quickshell configuration rather than an Omarchy shell plugin. This keeps the feature usable on plain Hyprland while still allowing an Omarchy adapter to reuse Omarchy-provided defaults.

Only one lightweight launcher Quickshell process should exist per graphical session. The visible launcher window is created/shown on demand and hidden after an action or `Esc`.

## Component boundaries

### Hyprland binding

Repository-owned Hyprland Lua registers `Super + R`.

Its only responsibility is to invoke the launcher wrapper. It does not know about projects, Git, Cargo, Node, Docker, favorites, or Omarchy.

The project intentionally claims `Super + R` in the managed binding layer. Existing preserved user bindings are loaded first, then this project registers its own launcher binding. The implementation must make the ownership explicit and test it.

### Launcher wrapper

A small non-privileged launcher entry point owns process lifecycle:

1. try to toggle the existing launcher through Quickshell IPC;
2. if the launcher is not running, start the project Quickshell configuration;
3. request the launcher to become visible and focused;
4. return immediately to Hyprland.

It must not scan projects or wait for discovery to complete before returning.

### Quickshell UI

QML owns presentation and user interaction only:

- search input;
- project list;
- action list;
- focus movement;
- selected project/action;
- disabled-action reasons;
- errors and empty states;
- invoking the backend command interface.

QML must not contain Git/Cargo/npm/Docker detection logic.

### Lua backend

The backend owns deterministic workstation logic:

- project discovery;
- normalization and stable project IDs;
- fuzzy matching/ranking;
- project type detection;
- action construction;
- action override merging;
- favorite/recent persistence;
- adapter selection;
- safe command construction.

The backend exposes a stable machine-readable interface to QML. The v0.3 protocol is versioned JSON emitted by a Lua CLI entry point. JSON encoding/decoding used by the core must not require Omarchy or `jq`.

### Adapters

Adapters isolate external environment details from project logic.

```text
lua/workstation/adapters/
  generic.lua
  omarchy.lua
```

The adapter contract covers:

- opening a terminal at an explicit working directory with an argv command;
- opening an editor at a project path;
- opening the file manager at a project path;
- copying text to the clipboard when a supported clipboard command exists;
- capability checks and human-readable unavailable reasons.

The core chooses the Omarchy adapter only when Omarchy capabilities are actually present. Otherwise it uses the generic adapter.

No action resolver may call Omarchy directly.

## Repository ownership

The implementation should extend the current repository layout rather than create an unrelated second project.

Expected ownership:

```text
hypr/
  bindings.lua
  workstation/
    project_launcher.lua

lua/workstation/
  project_discovery.lua
  project_model.lua
  project_search.lua
  project_types.lua
  project_actions.lua
  project_config.lua
  project_state.lua
  launcher_protocol.lua
  adapters/
    generic.lua
    omarchy.lua

quickshell/
  gendbyte-project-launcher/
    shell.qml
    ProjectLauncher.qml
    components/...

bin/
  hyprland-workstation-launcher

project-launcher.lua

tests/
  project_discovery_test.lua
  project_search_test.lua
  project_types_test.lua
  project_actions_test.lua
  project_config_test.lua
  project_state_test.lua
  launcher_protocol_test.lua
  project_launcher_binding_test.lua
  launcher_installer_test.lua
```

Exact file decomposition may be adjusted during implementation if a smaller boundary is clearer, but UI, discovery, action resolution, state, adapters, and installation must remain independently testable units.

## Project discovery

### Default roots

Without user configuration, discovery scans:

```text
~/Repository
```

Additional roots are read from the user configuration.

If a configured root does not exist, discovery skips it and reports it as unavailable without failing the launcher.

### What counts as an automatically discovered project

Automatic discovery is Git-root based. A directory is an automatically discovered project when it contains a Git repository marker such as `.git`.

Non-Git directories are not silently promoted into projects merely because they contain `package.json`, `Cargo.toml`, or another manifest. A non-Git directory can still be added explicitly through user configuration.

This keeps automatic discovery predictable and matches the approved "find Git projects + allow manual additions" behavior.

### Bounded recursive scan

Discovery must be bounded and non-blocking from Hyprland's perspective.

Defaults:

- recursive search under each root;
- no symlink traversal;
- configurable maximum depth, defaulting to 4 directory levels below each configured root;
- skip known heavy/generated directories such as `.git`, `node_modules`, `target`, `.venv`, `dist`, `build`, and cache directories;
- deduplicate projects by canonical path;
- allow nested Git repositories when they appear within the configured depth;
- never recurse through `.git` contents.

A scan failure for one subtree must not discard successfully discovered projects from other subtrees.

### Stable project identity

Project identity is derived from its canonical absolute path, not only its basename. Two repositories with the same folder name in different roots remain distinct.

Display names default to the directory basename and may be overridden by user configuration.

## Configuration

The default user configuration path is:

```text
~/.config/hyprland-workstation/projects.lua
```

The file returns a declarative Lua table. The conceptual shape is:

```lua
return {
  roots = {
    "~/Repository",
    "~/Projects",
  },

  projects = {
    {
      path = "~/work/non-git-project",
      name = "Special Project",
    },
  },

  hidden = {
    "~/Repository/archive/old-project",
  },

  apps = {
    terminal = "auto",
    editor = { "code" },
    file_manager = { "thunar" },
  },

  overrides = {
    ["~/Repository/example"] = {
      actions = {
        {
          id = "dev",
          label = "Dev Server",
          argv = { "uv", "run", "fastapi", "dev" },
          terminal = true,
        },
      },
    },
  },
}
```

Configuration rules:

- `~/Repository` is used when no roots are configured;
- explicit `projects` may add non-Git or out-of-root projects;
- `hidden` removes matching projects from the normal list;
- `apps.terminal` is `"auto"` by default and may select a known terminal adapter such as `foot`, `ghostty`, `kitty`, or `alacritty`;
- `apps.editor` and `apps.file_manager` are optional argv arrays; when omitted, the generic adapter uses safe environment/default discovery;
- project action overrides take precedence over auto-detected actions with the same stable action ID;
- command overrides use argv arrays, not shell command strings, by default;
- a deliberately shell-based custom action must opt into shell execution explicitly;
- user configuration is trusted user-authored code, but backend APIs still validate the returned table before using it.

A malformed configuration must not make the launcher unusable. The launcher falls back to safe defaults, surfaces a configuration error, and does not overwrite the user's file.

## State

Mutable launcher state lives under `XDG_STATE_HOME`, falling back to `~/.local/state`.

Conceptually:

```text
$XDG_STATE_HOME/hyprland-workstation/project-launcher/
  favorites
  recent
```

Favorites and recents are intentionally separate from the declarative config so normal launcher usage does not rewrite configuration.

State behavior:

- favorite toggles are persisted immediately;
- recent usage records successful action launches;
- missing projects may remain visible as stale favorites/recent entries long enough to explain that the path is missing;
- a rescan removes stale entries from the ordinary discovered list;
- corrupt state is ignored/rebuilt without damaging config.

## Project type detection

Type detection enriches a discovered/explicit project; it does not define automatic project discovery.

Supported v0.3 signals:

- Git: `.git`;
- Rust: `Cargo.toml`;
- Node: `package.json`;
- Python: `pyproject.toml`;
- Docker Compose: `compose.yaml`, `compose.yml`, `docker-compose.yaml`, or `docker-compose.yml`.

A project may have multiple types at once.

Detection only reads metadata needed to construct actions. It never executes project files during scanning.

## Actions

### Universal actions

Every valid project exposes:

- Open Shell;
- Open Editor;
- Open File Manager;
- Favorite / Unfavorite;
- Copy Path, when clipboard capability exists.

Favorite / Unfavorite is a quick action and is the primary v0.3 UI mechanism for changing favorite state.

### Git actions

Git projects may expose:

- Git Status;
- Git Log.

These open in a terminal because their output is interactive/inspectable.

### Rust actions

When `Cargo.toml` exists and `cargo` is available:

- Cargo Test;
- Cargo Run.

If `cargo` is missing, the actions remain visible but disabled with a reason.

### Node actions

When `package.json` exists, the backend detects the preferred package manager using lockfiles when possible and exposes `dev`, `test`, and `build` only when the corresponding scripts are actually declared in `package.json`.

Examples:

- Dev;
- Test;
- Build.

The implementation should parse `package.json` without adding an Omarchy- or `jq`-only dependency.

### Python actions

When `pyproject.toml` exists, v0.3 may expose conservative actions only when a runnable/test tool can be resolved safely.

At minimum:

- Test when a supported test command can be resolved;
- a user override may define project-specific Run/Dev behavior.

v0.3 must not guess destructive or highly framework-specific Python commands.

### Docker/Compose actions

When a Compose file exists and Docker Compose capability is available:

- Compose Up;
- Compose Logs;
- Compose Down.

`Compose Down` requires confirmation.

### Override precedence

Action resolution order is:

```text
universal actions
  + auto-detected project actions
  -> apply per-project overrides by stable action id
  -> add custom actions
  -> capability check
  -> final ordered action list
```

Manual overrides can replace label, argv, terminal behavior, confirmation requirement, and visibility.

## Action execution model

Actions are divided into two categories.

### Terminal actions

Interactive or output-oriented actions open a terminal rooted at the selected project.

Examples:

- Open Shell;
- Git Status;
- Git Log;
- tests;
- development server;
- Cargo Run;
- Compose Up/Logs/Down.

The terminal adapter receives an explicit canonical cwd and argv. It must not depend on the cwd of whichever terminal currently has focus.

### Quick actions

Quick actions execute without opening a terminal:

- Open Editor;
- Open File Manager;
- Copy Path.

The launcher hides immediately after a successful action dispatch.

## Terminal selection

The implementation must not hard-code Foot.

The generic adapter resolves terminal capability in this order:

1. an explicit `apps.terminal` adapter id from `projects.lua`, when it is not `"auto"`;
2. `xdg-terminal-exec` when available;
3. conservative support for known installed terminal executables and an unambiguous environment preference;
4. otherwise mark terminal actions unavailable with a clear reason.

The generic adapter recognizes at least Foot, Ghostty, Kitty, and Alacritty. Their differing cwd/exec flags remain inside the adapter and never leak into action resolution.

Commands are passed as argv wherever the selected mechanism supports it. The project must not build a shell string from an untrusted project path.

### Omarchy adapter

When Omarchy is detected, the adapter may use Omarchy's default-terminal infrastructure and related launch helpers where they accept the required explicit cwd/argv semantics.

The adapter must not assume Foot. Changing Omarchy's default terminal to Ghostty, Kitty, or Alacritty must not require changing project-launcher configuration.

If an Omarchy helper cannot honor an explicit selected-project cwd, the adapter falls back to the lower-level terminal mechanism instead of inheriting the active terminal's cwd.

## UI and interaction

The approved layout is a centered floating two-pane launcher.

```text
+-------------------------------------------------+
| Search projects...                              |
+----------------------+--------------------------+
| Projects             | Actions                  |
|                      |                          |
| * Voxelyra           | Open Shell               |
| * NumFlow            | Open Editor              |
|   ForgeGuard         | Git Status               |
|   VoxClip            | Tests                    |
|   Hyprland_Config    | Dev Server               |
|                      | Docker Compose            |
+----------------------+--------------------------+
| up/down  Tab/right  Enter run  Esc close        |
+-------------------------------------------------+
```

### Keyboard behavior

- `Super + R`: show/toggle launcher;
- opening focuses the search field;
- typing fuzzy-filters projects;
- `Up/Down`: move through projects or actions in the focused pane;
- `Tab` or `Right`: move from projects to actions;
- `Left`: return from actions to projects;
- `Enter`: run the selected enabled action;
- `Esc`: close the launcher without side effects.

Mouse interaction may be supported, but keyboard interaction is the primary contract.

### Sorting

With an empty query:

1. favorites;
2. recent projects not already shown as favorites;
3. remaining discovered projects.

With a query, fuzzy-match relevance is primary while favorite/recent status acts only as a tie-breaker/boost. A poor textual match must not outrank a clearly better match merely because it is a favorite.

### Visual treatment

The launcher is independent of Omarchy theme APIs.

Default appearance:

- dark translucent surface;
- rounded corners;
- thin border;
- restrained orange accent;
- compact developer-oriented typography;
- clear focus/selection states;
- disabled actions visibly distinct with an explanatory reason.

The UI may later gain theme adapters, but v0.3 must remain usable on plain Hyprland without them.

## Error handling

Failures are local and actionable.

### Missing project

If a selected path disappears:

- do not execute the action;
- show "project path no longer exists";
- offer/trigger a rescan;
- keep the launcher responsive.

### Missing executable

If `cargo`, Docker, a package manager, terminal, editor, file manager, or clipboard utility is unavailable:

- do not crash;
- disable only the affected action;
- expose a concise reason.

### Scan errors

Permission or I/O errors in one subtree are recorded for diagnostics and skipped. Other roots continue scanning.

### Backend/protocol errors

Malformed backend output must show a launcher error state rather than causing QML exceptions or executing a partially parsed command.

### Configuration errors

Invalid user config falls back to default discovery and reports the config problem. The project never silently rewrites a broken config.

## Security

The launcher is non-privileged.

It must not require:

- `sudo`;
- `pkexec`;
- a privileged daemon;
- `/dev/uinput` for this feature;
- modification of system-owned Hyprland or Omarchy files.

Discovery does not execute repository content.

Paths and normal auto-generated actions use argv-safe process execution. Project names and paths are never concatenated into a shell program string.

Custom actions that explicitly request shell execution are treated as trusted user configuration and must be visibly marked as shell actions in the configuration model.

Potentially destructive actions require explicit confirmation. v0.3 requires confirmation for Compose Down and for any custom action with `confirm = true`.

## Installation and lifecycle

### Capability-based install

The current installer hard-requires Omarchy because v0.2 installs Omarchy-specific plugins. v0.3 changes installation to capability-based behavior.

On every supported system the installer manages:

- Hyprland workstation Lua;
- the `Super + R` binding;
- launcher wrapper;
- Quickshell launcher configuration;
- Lua backend/runtime files;
- project-launcher state/config directories only when needed.

When Omarchy is available, the installer additionally manages the existing Omarchy extras from v0.1/v0.2:

- Mouse Mode HUD plugin;
- System Monitor plugin.

On plain Hyprland, missing Omarchy is not an installation error. Omarchy-only components are skipped.

### Quickshell requirement

Quickshell is a v0.3 runtime requirement for the graphical launcher.

The installer does not install system packages itself. If Quickshell is unavailable it reports the missing dependency and leaves existing workstation configuration safe.

### Supported Hyprland baseline

v0.3 targets the Lua-first Hyprland configuration generation already used by this repository and sets a supported minimum of Hyprland 0.55+.

A second legacy pre-0.55 binding backend is out of scope for v0.3.

### Install state migration

Install state must evolve from the current all-or-nothing Omarchy assumption.

The next state version records which optional components were actually installed/enabled so reinstall/uninstall can be symmetrical.

Migration requirements:

- an existing v0.1/v0.2 active installation upgrades in place;
- original backup references remain valid;
- existing working Mouse Mode and System Monitor links are not replaced unnecessarily;
- reinstall reconciles missing/new components instead of deleting and recreating healthy ones;
- uninstall removes only components owned by this repository and restores preserved user files as before.

Rollback must restore the pre-install state if a new launcher component fails during installation.

## Testing strategy

Implementation follows TDD and extends the current Lua test suite.

### Pure unit tests

Cover:

- root normalization and canonical identity;
- bounded discovery and exclusions;
- symlink non-traversal;
- duplicate-path handling;
- nested Git repositories within depth;
- missing/inaccessible roots;
- fuzzy matching and ranking;
- favorite/recent ordering;
- type detection;
- action composition and override precedence;
- disabled-action reasons;
- confirmation flags;
- config validation/default fallback;
- state persistence/corruption recovery;
- adapter selection;
- command argv construction and paths containing spaces/shell metacharacters;
- protocol serialization/parsing.

### Integration-style tests

Cover:

- `Super + R` binding registration without using `Super + H`;
- wrapper lifecycle behavior: IPC existing instance vs start new instance;
- generic install without Omarchy;
- Omarchy install preserving existing v0.1/v0.2 components;
- reinstall reconciliation;
- rollback after launcher install failure;
- uninstall symmetry;
- Quickshell/plugin/config file syntax checks where tooling is available.

### Manual acceptance on the target desktop

Before v0.3 is considered complete:

1. install/reinstall on the user's Omarchy machine;
2. `Super + R` opens the centered launcher;
3. projects under `~/Repository` appear;
4. fuzzy search works;
5. favorite/recent ordering persists across launcher restarts;
6. Rust/Node/Python/Docker/Git actions appear only when applicable;
7. Open Shell opens the user's current default terminal at the selected project path;
8. switching the default terminal does not require launcher code changes;
9. Open Editor/File Manager/Copy Path use quick actions;
10. missing tools disable actions rather than crashing;
11. Mouse Mode still works;
12. System Monitor still works;
13. normal NumPad behavior still works with Num Lock on;
14. `hyprctl configerrors` reports no new configuration errors.

## Acceptance criteria

v0.3 is complete when all of the following are true:

- the launcher works on supported plain Hyprland without Omarchy;
- Omarchy is an optional adapter/capability, not a core dependency;
- `Super + R` toggles the launcher without blocking Hyprland on discovery;
- `Super + H` remains free;
- default discovery finds Git projects under `~/Repository`;
- extra roots and explicit projects work through config;
- favorites and recents persist outside config;
- two-pane keyboard navigation matches the approved interaction;
- action detection works for the declared v0.3 project types;
- manual overrides beat automatic actions predictably;
- terminal actions use an explicit selected-project cwd and do not hard-code Foot;
- quick actions run without a terminal;
- destructive actions can require confirmation;
- installer/reinstaller/uninstaller are safe on both generic Hyprland and Omarchy;
- existing v0.1/v0.2 behavior is not regressed;
- automated tests and fresh manual verification are green.

## Deferred work

The following are intentionally deferred:

- full project/workspace orchestration;
- automatic multi-pane/tmux layouts;
- launching coordinated editor + terminal + browser stacks;
- global command modes such as `>`, `@`, or `#`;
- a unified Command Center;
- deep Omarchy theme binding;
- legacy pre-0.55 Hyprland support;
- background daemon indexing;
- cloud/project synchronization.

These belong to later roadmap stages unless a concrete v0.3 requirement proves they are necessary.

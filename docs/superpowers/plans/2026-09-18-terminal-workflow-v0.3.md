# Hyprland-first Project Launcher / Terminal Workflow v0.3 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Hyprland-first, keyboard-driven Project Launcher on `Super + R` that discovers projects, resolves context-aware actions, launches the user's configured tools, and keeps Omarchy optional.

**Architecture:** A standalone Quickshell launcher owns only presentation and IPC. Pure Lua modules own discovery, search, project typing, state, action resolution, adapters, and the versioned JSON command protocol. Hyprland only launches/toggles the UI; Omarchy is selected as an optional adapter/capability and is never required by the core.

**Tech Stack:** Hyprland 0.55+ Lua configuration, Lua 5.1, Quickshell/QML, Linux `find`, Git, `xdg-terminal-exec`, optional Omarchy CLI/shell.

**Spec:** `docs/superpowers/specs/2026-09-18-terminal-workflow-v0.3-design.md`

## Global Constraints

- The feature is Hyprland-first; Omarchy is optional.
- Supported Hyprland baseline is 0.55+.
- `Super + R` opens/toggles the launcher.
- `Super + H` remains unused.
- Default project root is `~/Repository`.
- Recursive discovery defaults to 4 directory levels below each configured root.
- Automatic discovery is Git-root based; explicit config may add non-Git projects.
- The UI is a centered two-pane Quickshell launcher: Projects on the left, Actions on the right.
- Project search/ranking, project typing, action resolution, and state are Lua responsibilities, not QML responsibilities.
- The v0.3 backend protocol is versioned JSON and must not depend on Omarchy or `jq`.
- Terminal actions use an explicit selected-project cwd and do not hard-code Foot.
- Normal generated commands use argv-safe execution; shell execution is explicit custom configuration only.
- No `sudo`, `pkexec`, privileged daemon, system-file modification, or background indexing daemon.
- Existing Mouse Mode, NumPad passthrough, HUD, and System Monitor behavior must not regress.
- v0.4 workspace orchestration and v0.5 unified Command Center remain out of scope.

---

## File Structure

Create or extend these focused units:

```text
lua/workstation/
  json.lua                    pure JSON encode/decode
  project_model.lua           path normalization + stable project records
  project_config.lua          projects.lua loading/validation/defaults
  project_discovery.lua       bounded Git-root discovery
  project_search.lua          fuzzy ranking + favorite/recent boosts
  project_state.lua           favorites/recent persistence
  project_cache.lua           ephemeral discovered-project cache
  project_types.lua           Git/Rust/Node/Python/Compose detection
  project_actions.lua         universal + detected + override action model
  action_executor.lua         validate/dispatch resolved actions
  launcher_protocol.lua       versioned request/response envelopes
  adapters/
    generic.lua               terminal/editor/file-manager/clipboard adapter
    omarchy.lua               optional Omarchy-specific resolution

hypr/workstation/
  project_launcher.lua        Hyprland binding + floating/center rule ownership

quickshell/gendbyte-project-launcher/
  shell.qml                   standalone Quickshell entrypoint + IPC
  ProjectLauncher.qml         state machine and two-pane view
  components/SearchField.qml
  components/ProjectList.qml
  components/ActionList.qml
  components/ConfirmDialog.qml
  components/StatusMessage.qml

bin/
  hyprland-workstation-launcher

project-launcher.lua           Lua CLI/protocol entrypoint

tests/
  json_test.lua
  project_model_test.lua
  project_config_test.lua
  project_discovery_test.lua
  project_search_test.lua
  project_state_test.lua
  project_cache_test.lua
  project_types_test.lua
  project_actions_test.lua
  adapters_test.lua
  action_executor_test.lua
  launcher_protocol_test.lua
  project_launcher_cli_test.lua
  project_launcher_qml_test.lua
  project_launcher_binding_test.lua
  launcher_installer_test.lua
```

Existing lifecycle files remain authoritative and are modified rather than replaced:

```text
hypr/bindings.lua
lua/workstation/command.lua
lua/workstation/install_state.lua
lua/workstation/installer.lua
lua/workstation/uninstaller.lua
lua/workstation/verifier.lua
tests/run.lua
install.lua
reinstall.lua
uninstall.lua
verify.lua
README.md
```

### Task 1: Safe process primitives and JSON protocol foundation

**Files:**
- Modify: `lua/workstation/command.lua`
- Create: `lua/workstation/json.lua`
- Create: `tests/json_test.lua`
- Modify: `tests/run.lua`

**Interfaces:**
- Produces: `command.argv(args) -> string`
- Produces: `command.capture_argv(args) -> string|nil`
- Produces: `command.run_argv(args) -> boolean`
- Produces: `json.encode(value) -> string`
- Produces: `json.decode(text) -> value|nil, error_string|nil`
- Constraint: `command.argv` quotes every argv element with existing `command.quote`; no caller concatenates project paths into shell syntax.

- [ ] **Step 1: Write failing tests for argv quoting and pure-Lua JSON**

Add tests that prove metacharacters remain data and JSON round-trips without `jq`:

```lua
test("command argv quotes every argument", function()
  local command = require("workstation.command")
  testlib.eq(
    command.argv({ "printf", "%s", "/tmp/My Project;touch /tmp/pwn" }),
    "'printf' '%s' '/tmp/My Project;touch /tmp/pwn'"
  )
end)

test("json round trips launcher payload", function()
  local json = require("workstation.json")
  local encoded = json.encode({
    version = 1,
    ok = true,
    projects = { { id = "/tmp/a", name = "A" } },
  })
  local decoded, err = json.decode(encoded)
  testlib.eq(err, nil)
  testlib.eq(decoded.version, 1)
  testlib.eq(decoded.projects[1].id, "/tmp/a")
end)

test("json rejects trailing executable text", function()
  local json = require("workstation.json")
  local value, err = json.decode('{"ok":true} os.execute("touch /tmp/pwn")')
  testlib.eq(value, nil)
  testlib.truthy(err)
end)
```

- [ ] **Step 2: Run the suite and verify RED**

Run:

```bash
lua5.1 tests/run.lua
```

Expected: failures because `command.argv` and `workstation.json` do not exist.

- [ ] **Step 3: Implement the minimal safe primitives**

In `command.lua`, add:

```lua
function M.argv(args)
  local quoted = {}
  for index, value in ipairs(args) do
    quoted[index] = M.quote(value)
  end
  return table.concat(quoted, " ")
end

function M.run_argv(args)
  return M.run(M.argv(args))
end

function M.capture_argv(args)
  return M.capture(M.argv(args))
end
```

Implement `json.lua` as a small pure-Lua JSON encoder/recursive-descent decoder supporting the protocol's null/boolean/number/string/array/object types. Do not use `load`, `loadstring`, `dofile`, or shell commands for JSON parsing.

- [ ] **Step 4: Run focused and full tests**

Run:

```bash
lua5.1 tests/run.lua
luac5.1 -p lua/workstation/json.lua lua/workstation/command.lua
```

Expected: all existing tests plus the new JSON/argv tests pass.

- [ ] **Step 5: Commit**

```bash
git add lua/workstation/command.lua lua/workstation/json.lua tests/json_test.lua tests/run.lua
git commit -m "feat: add safe argv and JSON primitives"
```

### Task 2: Project model, config validation, and bounded discovery

**Files:**
- Create: `lua/workstation/project_model.lua`
- Create: `lua/workstation/project_config.lua`
- Create: `lua/workstation/project_discovery.lua`
- Create: `tests/project_model_test.lua`
- Create: `tests/project_config_test.lua`
- Create: `tests/project_discovery_test.lua`
- Modify: `tests/run.lua`

**Interfaces:**
- Produces: `project_model.normalize_path(path, home, runtime) -> canonical_path|nil`
- Produces: `project_model.new(path, options, runtime) -> project|nil, error_string|nil`
- Produces: `project_config.load(options) -> config, error_string|nil`
- Produces: `project_discovery.discover(config, runtime) -> { projects = {...}, warnings = {...} }`
- Project record: `{ id, path, name, source = "discovered"|"explicit", stale = boolean }`
- Config record: `{ roots, projects, hidden, apps, overrides, max_depth }`

- [ ] **Step 1: Write failing tests for defaults, explicit projects, hiding, depth, symlinks, and duplicate canonical paths**

Use injected discovery runtime rather than the real filesystem for unit tests:

```lua
test("config defaults to Repository and depth four", function()
  local config = require("workstation.project_config").defaults("/home/test")
  testlib.eq(config.roots[1], "/home/test/Repository")
  testlib.eq(config.max_depth, 4)
  testlib.eq(config.apps.terminal, "auto")
end)

test("discovery deduplicates canonical git roots", function()
  local discovery = require("workstation.project_discovery")
  local result = discovery.discover({
    roots = { "/r1", "/r2" },
    projects = {},
    hidden = {},
    max_depth = 4,
  }, fake_runtime({
    ["/r1"] = { "/work/a/.git" },
    ["/r2"] = { "/work/a/.git" },
  }))
  testlib.eq(#result.projects, 1)
  testlib.eq(result.projects[1].id, "/work/a")
end)

test("discovery does not follow symlink markers", function()
  local result = discovery.discover(config, runtime_with_symlink_git_marker())
  testlib.eq(#result.projects, 0)
end)
```

Also cover: missing root warning, nested repo within depth 4, repo below depth 4 excluded, explicit non-Git project included, hidden path excluded, same basename at two canonical paths remains two projects.

- [ ] **Step 2: Run the suite and verify RED**

```bash
lua5.1 tests/run.lua
```

Expected: module-not-found failures for the three project modules.

- [ ] **Step 3: Implement model/config/discovery**

Use `readlink -f` through injected runtime for canonical identity. The production discovery runtime uses Linux `find` without `-L`, NUL-separated output, and explicit pruning:

```text
.git
node_modules
target
.venv
dist
build
.cache
__pycache__
```

Search for a `.git` marker at maximum project depth 4, convert each marker to its parent directory, canonicalize, then merge explicit projects and hidden paths.

Load `~/.config/hyprland-workstation/projects.lua` with `pcall(dofile, path)`; validate the returned table strictly before use. Config is trusted user-authored Lua, but invalid shapes fall back to defaults with an error string and never get rewritten.

- [ ] **Step 4: Run focused and full verification**

```bash
lua5.1 tests/run.lua
luac5.1 -p lua/workstation/project_model.lua
luac5.1 -p lua/workstation/project_config.lua
luac5.1 -p lua/workstation/project_discovery.lua
```

Expected: green.

- [ ] **Step 5: Commit**

```bash
git add lua/workstation/project_*.lua tests/project_*_test.lua tests/run.lua
git commit -m "feat: add project discovery and config"
```

### Task 3: Favorites, recents, fuzzy ranking, and ephemeral cache

**Files:**
- Create: `lua/workstation/project_state.lua`
- Create: `lua/workstation/project_search.lua`
- Create: `lua/workstation/project_cache.lua`
- Create: `tests/project_state_test.lua`
- Create: `tests/project_search_test.lua`
- Create: `tests/project_cache_test.lua`
- Modify: `tests/run.lua`

**Interfaces:**
- Produces: `project_state.load(options) -> { favorites = {}, recent = {} }`
- Produces: `project_state.toggle_favorite(state, project_id) -> boolean now_favorite`
- Produces: `project_state.mark_recent(state, project_id, now) -> state`
- Produces: `project_state.save(state, options) -> true|nil, error_string`
- Produces: `project_search.rank(projects, query, state) -> ranked_projects`
- Produces: `project_cache.write(projects, options) -> true|nil, error_string`
- Produces: `project_cache.read(options) -> projects|nil, error_string`
- Cache path: `${XDG_CACHE_HOME:-~/.cache}/hyprland-workstation/project-launcher/projects.json`
- State path: `${XDG_STATE_HOME:-~/.local/state}/hyprland-workstation/project-launcher/state.json`

- [ ] **Step 1: Write failing state/ranking/cache tests**

```lua
test("empty query orders favorite then recent then remaining", function()
  local search = require("workstation.project_search")
  local projects = {
    { id = "/a", name = "Alpha" },
    { id = "/b", name = "Beta" },
    { id = "/c", name = "Gamma" },
  }
  local ranked = search.rank(projects, "", {
    favorites = { ["/c"] = true },
    recent = { { id = "/b", used_at = 20 } },
  })
  testlib.eq(ranked[1].id, "/c")
  testlib.eq(ranked[2].id, "/b")
end)

test("strong fuzzy match beats favorite boost", function()
  local ranked = search.rank({
    { id = "/num", name = "NumFlow" },
    { id = "/vox", name = "Voxelyra" },
  }, "num", { favorites = { ["/vox"] = true }, recent = {} })
  testlib.eq(ranked[1].id, "/num")
end)

test("corrupt state returns empty state", function()
  local state, warning = project_state.load(fake_state_options("{oops"))
  testlib.eq(next(state.favorites), nil)
  testlib.truthy(warning)
end)
```

Also test favorite persistence, recent dedupe/update, cache round-trip, corrupt cache rejection, stale path preservation in state only.

- [ ] **Step 2: Verify RED**

```bash
lua5.1 tests/run.lua
```

- [ ] **Step 3: Implement deterministic state/search/cache**

Keep state JSON data-only. Fuzzy score should reward ordered character matches, consecutive matches, word/basename boundaries, and shorter distance; favorite/recent boosts apply only after textual relevance so an unrelated favorite cannot beat a clear query match.

Cap recent history to 50 project IDs to prevent unbounded state growth.

- [ ] **Step 4: Verify GREEN**

```bash
lua5.1 tests/run.lua
```

Expected: full suite green.

- [ ] **Step 5: Commit**

```bash
git add lua/workstation/project_state.lua lua/workstation/project_search.lua lua/workstation/project_cache.lua tests/project_state_test.lua tests/project_search_test.lua tests/project_cache_test.lua tests/run.lua
git commit -m "feat: add project search and launcher state"
```

### Task 4: Project type detection and action resolution

**Files:**
- Create: `lua/workstation/project_types.lua`
- Create: `lua/workstation/project_actions.lua`
- Create: `tests/project_types_test.lua`
- Create: `tests/project_actions_test.lua`
- Modify: `tests/run.lua`

**Interfaces:**
- Produces: `project_types.detect(project, runtime) -> types`
- Types: `{ git, rust, node, python, compose, package_manager, node_scripts, compose_file }`
- Produces: `project_actions.resolve(project, types, config, capabilities) -> actions`
- Action record: `{ id, label, argv, terminal, enabled, reason, confirm, shell }`
- Stable IDs: `open-shell`, `open-editor`, `open-file-manager`, `favorite`, `copy-path`, `git-status`, `git-log`, `rust-test`, `rust-run`, `node-dev`, `node-test`, `node-build`, `python-test`, `compose-up`, `compose-logs`, `compose-down`.

- [ ] **Step 1: Write RED tests for multi-type projects and override precedence**

```lua
test("node actions only expose declared scripts", function()
  local actions = resolve_node({
    scripts = { dev = "next dev", build = "next build" },
    package_manager = "pnpm",
  })
  assert_action(actions, "node-dev", { "pnpm", "run", "dev" })
  assert_action(actions, "node-build", { "pnpm", "run", "build" })
  assert_no_action(actions, "node-test")
end)

test("compose down requires confirmation", function()
  local action = find_action(resolve_compose(), "compose-down")
  testlib.eq(action.confirm, true)
  testlib.eq(action.terminal, true)
end)

test("manual override replaces auto action by stable id", function()
  local actions = project_actions.resolve(project, types, {
    overrides = {
      [project.path] = {
        actions = {
          { id = "node-dev", label = "Dev", argv = { "bun", "dev" }, terminal = true },
        },
      },
    },
  }, capabilities)
  testlib.eq(find_action(actions, "node-dev").argv[1], "bun")
end)
```

Also test Git, Rust, Python conservative behavior, lockfile package-manager resolution, missing executable disabled reasons, universal actions, and Favorite/Unfavorite label from state/capability input.

- [ ] **Step 2: Verify RED**

```bash
lua5.1 tests/run.lua
```

- [ ] **Step 3: Implement project typing and action merge pipeline**

Parse `package.json` with `workstation.json`. Detect package manager in this order: `pnpm-lock.yaml`, `yarn.lock`, `bun.lockb`/`bun.lock`, `package-lock.json`, otherwise npm. Only create Node `dev/test/build` actions when that script exists.

Python auto-action remains conservative: expose `python-test` only when a supported test runner is resolvable; project-specific run/dev comes from overrides.

Merge in the exact order from the spec: universal -> auto actions -> overrides by ID -> custom actions -> capability disable pass.

- [ ] **Step 4: Verify GREEN**

```bash
lua5.1 tests/run.lua
```

- [ ] **Step 5: Commit**

```bash
git add lua/workstation/project_types.lua lua/workstation/project_actions.lua tests/project_types_test.lua tests/project_actions_test.lua tests/run.lua
git commit -m "feat: resolve project-aware launcher actions"
```

### Task 5: Generic/Omarchy adapters and action executor

**Files:**
- Create: `lua/workstation/adapters/generic.lua`
- Create: `lua/workstation/adapters/omarchy.lua`
- Create: `lua/workstation/action_executor.lua`
- Create: `tests/adapters_test.lua`
- Create: `tests/action_executor_test.lua`
- Modify: `tests/run.lua`

**Interfaces:**
- Produces: `generic.detect(config, runtime) -> adapter`
- Produces: `omarchy.detect(config, runtime) -> adapter|nil`
- Adapter methods:
  - `capabilities() -> table`
  - `terminal_argv(cwd, argv) -> argv_array|nil, reason`
  - `editor_argv(path) -> argv_array|nil, reason`
  - `file_manager_argv(path) -> argv_array|nil, reason`
  - `clipboard_argv(text) -> argv_array|nil, stdin_text|nil, reason`
- Produces: `action_executor.run(project, action, adapter, runtime) -> { ok, error, requires_confirmation }`

- [ ] **Step 1: Write failing adapter/executor tests**

```lua
test("generic adapter prefers xdg-terminal-exec in auto mode", function()
  local adapter = generic.detect({ apps = { terminal = "auto" } }, runtime_with({
    ["xdg-terminal-exec"] = true,
  }))
  local argv = adapter.terminal_argv("/tmp/My Project", { "git", "status" })
  testlib.eq(argv[1], "xdg-terminal-exec")
  testlib.eq(argv[2], "--dir=/tmp/My Project")
  testlib.eq(argv[3], "git")
end)

test("explicit foot adapter stays cwd-safe", function()
  local adapter = generic.detect({ apps = { terminal = "foot" } }, runtime_with({
    foot = true,
  }))
  local argv = adapter.terminal_argv("/tmp/a;echo bad", { "git", "status" })
  testlib.eq(argv[1], "foot")
  testlib.eq(argv[2], "--working-directory=/tmp/a;echo bad")
end)

test("executor refuses confirm action until confirmed", function()
  local result = executor.run(project, {
    id = "compose-down",
    argv = { "docker", "compose", "down" },
    terminal = true,
    confirm = true,
  }, adapter, runtime, { confirmed = false })
  testlib.eq(result.requires_confirmation, true)
  testlib.eq(runtime.spawn_count, 0)
end)
```

Also cover Ghostty/Kitty/Alacritty adapter argv, editor/file-manager explicit config, clipboard availability, Omarchy selection only when available, and missing project path rejection before spawn.

- [ ] **Step 2: Verify RED**

```bash
lua5.1 tests/run.lua
```

- [ ] **Step 3: Implement adapters and executor**

Generic terminal rules:

```text
apps.terminal != "auto" -> selected known adapter
else xdg-terminal-exec  -> xdg-terminal-exec --dir=<cwd> [command...]
else known preferred env/executable -> Foot/Ghostty/Kitty/Alacritty adapter
else unavailable
```

Keep terminal-specific cwd/exec flags inside `generic.lua`. Omarchy may reuse `xdg-terminal-exec` and Omarchy default selection, but must fall back when an Omarchy helper would inherit the active terminal cwd.

The executor canonicalizes/rechecks the project path immediately before dispatch, refuses disabled actions, returns confirmation state without executing, and calls only argv-safe runtime spawning for normal actions.

- [ ] **Step 4: Verify GREEN and metacharacter safety**

```bash
lua5.1 tests/run.lua
```

Expected: no test creates side-effect files from path metacharacters.

- [ ] **Step 5: Commit**

```bash
git add lua/workstation/adapters lua/workstation/action_executor.lua tests/adapters_test.lua tests/action_executor_test.lua tests/run.lua
git commit -m "feat: add launcher adapters and action execution"
```

### Task 6: Versioned launcher CLI protocol

**Files:**
- Create: `lua/workstation/launcher_protocol.lua`
- Create: `project-launcher.lua`
- Create: `tests/launcher_protocol_test.lua`
- Create: `tests/project_launcher_cli_test.lua`
- Modify: `tests/run.lua`

**Interfaces:**
- Protocol envelope: `{ version = 1, ok = boolean, data = any, error = string|nil }`
- CLI commands:
  - `refresh`
  - `query <text>`
  - `actions <project_id>`
  - `favorite <project_id>`
  - `run <project_id> <action_id> [--confirmed]`
- `refresh` discovers and writes cache, then returns ranked empty-query projects.
- `query` reads cache; if cache is absent, performs one refresh first.
- `actions` resolves types/actions for one cached project.
- `run` revalidates project path and action before dispatch.

- [ ] **Step 1: Write RED protocol and CLI tests with injected runtime**

```lua
test("protocol success envelope is version one", function()
  local protocol = require("workstation.launcher_protocol")
  local payload = protocol.success({ projects = {} })
  testlib.eq(payload.version, 1)
  testlib.eq(payload.ok, true)
end)

test("query reads cache instead of rescanning", function()
  local result = cli.run({ "query", "num" }, fake_context({
    cache_projects = {
      { id = "/r/NumFlow", path = "/r/NumFlow", name = "NumFlow" },
    },
  }))
  testlib.eq(result.ok, true)
  testlib.eq(result.data.projects[1].name, "NumFlow")
  testlib.eq(result.context.discovery_calls, 0)
end)

test("run returns confirmation request without spawn", function()
  local result = cli.run({ "run", "/r/a", "compose-down" }, context)
  testlib.eq(result.data.requires_confirmation, true)
  testlib.eq(context.spawn_count, 0)
end)
```

- [ ] **Step 2: Verify RED**

```bash
lua5.1 tests/run.lua
```

- [ ] **Step 3: Implement protocol/CLI orchestration**

Keep `project-launcher.lua` thin: parse argv, build real context, call exported `run(args, context)`, write exactly one JSON object to stdout, exit non-zero only for transport/internal CLI failure. Domain failures such as missing tool remain valid JSON with `ok=false`.

Mark recent only after a successful action dispatch. Favorite toggles persist immediately.

- [ ] **Step 4: Verify GREEN and real CLI shape**

```bash
lua5.1 tests/run.lua
lua5.1 project-launcher.lua refresh | lua5.1 -e 'local j=require("workstation.json")'
```

For the second command, run from a shell with `LUA_PATH="./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;;"` or use the project's normal launcher entrypoint setup. Expected stdout is one JSON envelope and no debug text.

- [ ] **Step 5: Commit**

```bash
git add lua/workstation/launcher_protocol.lua project-launcher.lua tests/launcher_protocol_test.lua tests/project_launcher_cli_test.lua tests/run.lua
git commit -m "feat: add project launcher protocol"
```

### Task 7: Standalone Quickshell launcher and process wrapper

**Files:**
- Create: `quickshell/gendbyte-project-launcher/shell.qml`
- Create: `quickshell/gendbyte-project-launcher/ProjectLauncher.qml`
- Create: `quickshell/gendbyte-project-launcher/components/SearchField.qml`
- Create: `quickshell/gendbyte-project-launcher/components/ProjectList.qml`
- Create: `quickshell/gendbyte-project-launcher/components/ActionList.qml`
- Create: `quickshell/gendbyte-project-launcher/components/ConfirmDialog.qml`
- Create: `quickshell/gendbyte-project-launcher/components/StatusMessage.qml`
- Create: `bin/hyprland-workstation-launcher`
- Create: `tests/project_launcher_qml_test.lua`
- Modify: `tests/run.lua`

**Interfaces:**
- Quickshell IPC target: `gendbyte-project-launcher`
- IPC methods: `toggle()`, `show()`, `hide()`, `ping() -> "ok"`
- QML calls backend only through argv `["lua5.1", <repo>/project-launcher.lua, ...]`.
- Wrapper contract: try IPC first; if unavailable, launch standalone Quickshell config, poll `ping` for a bounded interval, then call `show`.

- [ ] **Step 1: Write RED structural tests for IPC, backend argv, and keyboard contract**

```lua
test("launcher qml exposes required ipc methods", function()
  local qml = read("quickshell/gendbyte-project-launcher/shell.qml")
  assert_contains(qml, 'target: "gendbyte-project-launcher"')
  assert_contains(qml, "function toggle()")
  assert_contains(qml, "function show()")
  assert_contains(qml, "function hide()")
  assert_contains(qml, "function ping()")
end)

test("launcher UI does not implement git or package detection", function()
  local qml = read_tree("quickshell/gendbyte-project-launcher")
  assert_not_contains(qml, "Cargo.toml")
  assert_not_contains(qml, "package.json")
  assert_not_contains(qml, "docker-compose")
end)

test("wrapper starts shell only after ipc miss", function()
  local script = read("bin/hyprland-workstation-launcher")
  assert_contains(script, "quickshell ipc")
  assert_contains(script, "quickshell -p")
end)
```

- [ ] **Step 2: Verify RED**

```bash
lua5.1 tests/run.lua
```

- [ ] **Step 3: Implement the UI state machine**

Use a regular standalone Quickshell window identified as `gendbyte-project-launcher`. On show:

1. make window visible;
2. focus search;
3. start backend `refresh`;
4. render returned projects;
5. request actions for the selected project.

On search text change, debounce about 80-120 ms, then call `query <text>`; do not rescan.

Keyboard behavior must exactly match the spec: Up/Down, Tab/Right, Left, Enter, Esc. Enter on a `confirm=true` action opens `ConfirmDialog`; the confirmed second call uses `--confirmed`.

The UI owns only display and selection state; all lists come from backend JSON.

- [ ] **Step 4: Implement wrapper and verify syntax/structure**

Wrapper outline:

```bash
#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="<resolved installed quickshell config>"

if quickshell ipc -p "$CONFIG_DIR" call gendbyte-project-launcher toggle >/dev/null 2>&1; then
  exit 0
fi

setsid quickshell -p "$CONFIG_DIR" >/dev/null 2>&1 &
for _ in {1..20}; do
  if quickshell ipc -p "$CONFIG_DIR" call gendbyte-project-launcher ping >/dev/null 2>&1; then
    exec quickshell ipc -p "$CONFIG_DIR" call gendbyte-project-launcher show
  fi
  sleep 0.05
done

echo "Project Launcher failed to start" >&2
exit 1
```

Do not hard-code the repository checkout path in the installed wrapper; installer materializes/references the active repo root safely.

Run:

```bash
lua5.1 tests/run.lua
bash -n bin/hyprland-workstation-launcher
```

If `quickshell` is available in CI/dev, also run its configuration syntax/load validation without showing a window.

- [ ] **Step 5: Commit**

```bash
git add quickshell/gendbyte-project-launcher bin/hyprland-workstation-launcher tests/project_launcher_qml_test.lua tests/run.lua
git commit -m "feat: add standalone project launcher UI"
```

### Task 8: Hyprland `Super + R` binding and centered floating window ownership

**Files:**
- Create: `hypr/workstation/project_launcher.lua`
- Modify: `hypr/bindings.lua`
- Create: `tests/project_launcher_binding_test.lua`
- Modify: `tests/run.lua`

**Interfaces:**
- Produces: `project_launcher.register(hl, o, options)`
- Binding: `Super + R` -> installed launcher wrapper.
- Window rule: launcher app/class/title is floated and centered without Omarchy.
- Constraint: no `Super + H` registration anywhere in this module.

- [ ] **Step 1: Write RED binding tests with fake Hyprland API**

```lua
test("project launcher binds Super R", function()
  local calls = fake_hyprland()
  require("hypr.workstation.project_launcher").register(calls.hl, calls.o, {
    launcher = "/home/test/.local/bin/hyprland-workstation-launcher",
  })
  assert_bound(calls, "SUPER", "R")
end)

test("project launcher never binds Super H", function()
  local source = read("hypr/workstation/project_launcher.lua")
  assert_not_contains(source, '"H"')
  assert_not_contains(source, "SUPER,H")
end)
```

Also assert the callback only dispatches an exec/launcher command and does not invoke discovery modules.

- [ ] **Step 2: Verify RED**

```bash
lua5.1 tests/run.lua
```

- [ ] **Step 3: Implement binding + window rule**

Keep `hypr/bindings.lua` ordering:

```lua
require("hypr.workstation.compat").apply(hl)
require("hypr.workstation.mouse").register(hl, o)
require("hypr.workstation.project_launcher").register(hl, o)
```

Use the Hyprland 0.55+ Lua API already used by the repo. Give the Quickshell toplevel a stable app/class identifier and register a narrow floating/center rule for only that identifier.

- [ ] **Step 4: Run full suite and syntax checks**

```bash
lua5.1 tests/run.lua
luac5.1 -p hypr/bindings.lua hypr/workstation/project_launcher.lua
```

- [ ] **Step 5: Commit**

```bash
git add hypr/bindings.lua hypr/workstation/project_launcher.lua tests/project_launcher_binding_test.lua tests/run.lua
git commit -m "feat: bind project launcher to Super R"
```

### Task 9: Install-state v2 and capability-based installer migration

**Files:**
- Modify: `lua/workstation/install_state.lua`
- Modify: `lua/workstation/installer.lua`
- Create: `tests/launcher_installer_test.lua`
- Modify: `tests/installer_test.lua`
- Modify: `tests/reinstall_safety_test.lua`
- Modify: `tests/run.lua`

**Interfaces:**
- Install state v2 preserves all v1 fields and adds component flags:
  - `launcher = boolean`
  - `omarchy_hud = boolean`
  - `omarchy_system_monitor = boolean`
- v1 read migration defaults flags from safely observable existing owned targets; it never rewrites state until install/reconcile succeeds.
- Generic install requires Hyprland config target, Lua 5.1, and Quickshell for v0.3 launcher.
- Missing Omarchy skips Omarchy-only plugin components rather than failing generic install.

- [ ] **Step 1: Write RED migration/capability tests**

```lua
test("v1 state remains readable before migration", function()
  local state = install_state.read(v1_state_path)
  testlib.eq(state.version, 1)
  testlib.eq(state.repo_root, repo_root)
end)

test("plain hyprland install does not require omarchy", function()
  local result = installer.install({
    home = home,
    repo_root = repo,
    runtime = runtime_with({
      quickshell = true,
      omarchy = false,
    }),
  })
  testlib.eq(result.changed, true)
  testlib.truthy(path_is_owned_launcher(home, repo))
  testlib.eq(path_exists(omarchy_monitor_target(home)), false)
end)

test("existing v0.2 install upgrades without replacing healthy links", function()
  local before = snapshot_owned_links(home)
  installer.install({ home = home, repo_root = repo, runtime = omarchy_runtime() })
  local after = snapshot_owned_links(home)
  testlib.eq(after.bindings_inode, before.bindings_inode)
  testlib.eq(after.monitor_inode, before.monitor_inode)
  testlib.truthy(after.launcher)
end)
```

Also test Quickshell missing -> clear failure and rollback of only new changes, occupied launcher target refusal, and state v2 write/read.

- [ ] **Step 2: Verify RED**

```bash
lua5.1 tests/run.lua
```

- [ ] **Step 3: Implement component-aware reconcile**

Install launcher-owned targets under user boundaries, for example:

```text
~/.local/bin/hyprland-workstation-launcher
~/.config/quickshell/gendbyte-project-launcher -> repo quickshell config
```

Preserve current Hyprland `bindings.lua` / `workstation` backup behavior.

Refactor Omarchy plugin operations behind capability checks. On plain Hyprland, do not create `~/.config/omarchy/plugins` solely for this project.

Only enable/disable System Monitor/HUD when Omarchy is present and the corresponding component is actually managed.

Write v2 state only after all required generic components reconcile successfully.

- [ ] **Step 4: Verify migration and rollback**

```bash
lua5.1 tests/run.lua
```

Expected: existing installer tests remain green, new generic-Hyprland path green, v0.2 migration green.

- [ ] **Step 5: Commit**

```bash
git add lua/workstation/install_state.lua lua/workstation/installer.lua tests/launcher_installer_test.lua tests/installer_test.lua tests/reinstall_safety_test.lua tests/run.lua
git commit -m "feat: make workstation install capability based"
```

### Task 10: Symmetric uninstall, verification, and reinstall lifecycle

**Files:**
- Modify: `lua/workstation/uninstaller.lua`
- Modify: `lua/workstation/verifier.lua`
- Modify: `reinstall.lua`
- Modify: `tests/uninstaller_test.lua`
- Modify: `tests/verifier_test.lua`
- Modify: `tests/reinstall_safety_test.lua`

**Interfaces:**
- Uninstall removes only state-v2 components marked as managed and still pointing to repository-owned sources.
- Verification distinguishes required generic checks from optional Omarchy checks.
- Verification requires Quickshell for installed launcher capability but does not fail merely because Omarchy is absent on a generic install.

- [ ] **Step 1: Write RED lifecycle tests**

```lua
test("generic uninstall removes launcher and restores preserved hypr files", function()
  install_generic_fixture()
  local result = uninstaller.uninstall({ home = home })
  testlib.eq(result.changed, true)
  testlib.eq(path_exists(launcher_target(home)), false)
  testlib.eq(read(original_bindings_target(home)), original_bindings)
end)

test("generic verification passes without omarchy", function()
  local result = verifier.verify({
    home = home,
    repo_root = repo,
    runtime = runtime_with({
      ["lua5.1"] = true,
      ["luac5.1"] = true,
      quickshell = true,
      omarchy = false,
    }),
  })
  assert_check_ok(result, "project launcher")
  assert_no_required_failure(result, "Omarchy CLI")
end)
```

Also test refusal when launcher symlink is replaced by another file, Omarchy uninstall only disables components recorded as installed, and reinstall does not delete healthy components.

- [ ] **Step 2: Verify RED**

```bash
lua5.1 tests/run.lua
```

- [ ] **Step 3: Implement symmetric lifecycle behavior**

Verifier required checks on every v0.3 install:

```text
repository safety
lua5.1
luac5.1
quickshell
Hyprland managed links
launcher wrapper
launcher Quickshell config
launcher/backend required files
Lua syntax
install-state consistency
```

Omarchy plugin validation is conditional: validate when Omarchy is installed and those plugin components are managed; otherwise report them as skipped/optional rather than global failure.

Update `reinstall.lua` messaging to say "reconcile" and report skipped optional Omarchy components explicitly.

- [ ] **Step 4: Run full lifecycle tests**

```bash
lua5.1 tests/run.lua
lua5.1 verify.lua
```

On a generic test fixture, verifier must pass without Omarchy. On Omarchy, existing plugin validation must still run.

- [ ] **Step 5: Commit**

```bash
git add lua/workstation/uninstaller.lua lua/workstation/verifier.lua reinstall.lua tests/uninstaller_test.lua tests/verifier_test.lua tests/reinstall_safety_test.lua
git commit -m "feat: complete launcher install lifecycle"
```

### Task 11: Documentation, full regression gate, and live acceptance

**Files:**
- Modify: `README.md`
- Modify: `docs/superpowers/specs/2026-09-18-terminal-workflow-v0.3-design.md` only if implementation reveals a true spec correction; otherwise leave it unchanged.
- No production code changes unless a failing verification exposes a bug; bug fixes must return to the responsible task's tests first.

**Interfaces:**
- README documents Hyprland-first positioning, Quickshell dependency, `Super + R`, project config, actions, adapter behavior, and generic-vs-Omarchy install semantics.
- Issue #4 tracks final acceptance evidence.

- [ ] **Step 1: Update README from v0.2-era assumptions**

Document:

```text
v0.3 Project Launcher
- Hyprland 0.55+
- Quickshell
- Super + R
- ~/Repository default root
- ~/.config/hyprland-workstation/projects.lua
- favorites/recent
- Git/Rust/Node/Python/Compose action detection
- terminal/editor/file-manager configuration
- Omarchy optional
```

Also fix stale installer language that says reinstall "uninstalls and reinstalls"; v0.3 uses reconciliation.

- [ ] **Step 2: Run the fresh automated release gate**

Run exactly:

```bash
lua5.1 tests/run.lua
find . -name '*.lua' -type f -print0 | xargs -0 -r -n1 luac5.1 -p
bash -n bin/hyprland-workstation-launcher
lua5.1 verify.lua
```

Expected: zero failures.

If Quickshell exposes a non-interactive config validation command in the installed version, run it against `quickshell/gendbyte-project-launcher` and record the exact command/output in the PR/issue evidence. Do not invent a validator flag if the local Quickshell version does not provide one.

- [ ] **Step 3: Perform live Omarchy/Hyprland acceptance before claiming completion**

On the user's machine:

```bash
git checkout <implementation-branch>
lua5.1 reinstall.lua
hyprctl reload
hyprctl configerrors
```

Then verify all of these manually:

```text
Super + R opens centered launcher
Esc closes it
typing fuzzy-filters projects
Tab/Right enters Actions; Left returns
Favorite persists after launcher restart
recent ordering updates after successful launch
Open Shell starts the current default terminal at selected project cwd
Open Editor/File Manager/Copy Path work or show a clear disabled reason
Git/Rust/Node/Python/Compose actions appear only when applicable
Compose Down asks for confirmation
missing executable disables only affected action
Mouse Mode still works with Num Lock off
normal NumPad digits still work with Num Lock on
System Monitor still updates and opens btop
Super + H remains free
hyprctl configerrors is empty/ok
```

- [ ] **Step 4: Re-run automated tests after any live fix**

Any live bug gets a regression test first, then a fix, then:

```bash
lua5.1 tests/run.lua
lua5.1 verify.lua
```

Do not claim v0.3 complete from manual behavior alone.

- [ ] **Step 5: Commit docs/evidence-ready state**

```bash
git add README.md
git commit -m "docs: document Hyprland project launcher v0.3"
```

Then prepare a PR that references `Closes #4`, includes the exact fresh test count, verification commands, and live acceptance evidence. Do not merge or delete the implementation branch without explicit user authorization.

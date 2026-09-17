# Omarchy Workstation v0.1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Lua-first Omarchy/Hyprland workstation foundation with a NumFlow-like Mouse Mode and safe install/verify/uninstall tooling.

**Architecture:** Hyprland handles runtime input through its native Lua API; no ydotool/uinput daemon is used. Standalone Lua 5.1 tools manage only user config symlinks and installation state, preserving pre-existing bindings before installing the repository-owned wrapper.

**Tech Stack:** Omarchy 4.x, Hyprland Lua API, Lua 5.1 (`lua5.1`, `luac5.1`), Linux coreutils.

**Spec:** `docs/superpowers/specs/2026-09-17-omarchy-workstation-v0.1-design.md`

## Global Constraints

- Project-owned behavior is Lua-first; no Bash/Python/Rust runtime for v0.1.
- Target standalone interpreter is Lua 5.1.
- Never modify `/usr/share/omarchy`.
- Normal install/uninstall requires no sudo, pkexec, input group, or `/dev/uinput` access.
- Hyprland bind callbacks must perform no blocking I/O.
- Existing `~/.config/hypr/bindings.lua` must be preserved and loaded while installed.
- `SUPER + M` is reserved for Mouse Mode via `o.rebind`.

---

### Task 1: Test harness and acceleration state

**Files:**
- Create: `tests/testlib.lua`
- Create: `tests/run.lua`
- Create: `tests/mouse_state_test.lua`
- Create: `hypr/workstation/mouse_state.lua`

**Interfaces:**
- Produces: `mouse_state.new() -> state`
- Produces: `mouse_state.next_step(state, direction) -> integer`
- Produces: `mouse_state.release(state, direction)`
- Produces: `mouse_state.reset(state)`

- [ ] **Step 1: Create a dependency-free Lua 5.1 test harness** with `test(name, fn)`, `eq(actual, expected)`, and a non-zero process exit when any test fails.
- [ ] **Step 2: Write failing tests** proving the acceleration sequence is `3, 3, 6, 6, 6, 12...`, counters are independent per direction, release resets one direction, and reset clears all directions.
- [ ] **Step 3: Run `lua5.1 tests/run.lua`** and verify failure is caused by the missing `hypr.workstation.mouse_state` module.
- [ ] **Step 4: Implement the minimal state module** using a table of repeat counters and thresholds 2/5/10 with steps 3/6/12/24.
- [ ] **Step 5: Run `lua5.1 tests/run.lua`** and verify all Task 1 tests pass.

### Task 2: Native Hyprland Mouse Mode

**Files:**
- Create: `tests/mouse_test.lua`
- Create: `hypr/workstation/mouse.lua`
- Create: `hypr/bindings.lua`

**Interfaces:**
- Consumes: `mouse_state.*` from Task 1.
- Produces: `mouse.register(hl_api, omarchy_api)`.
- `hypr/bindings.lua` loads preserved user bindings and calls `mouse.register(hl, o)`.

- [ ] **Step 1: Build a fake Hyprland API in `tests/mouse_test.lua`** that records binds, submaps, dispatches, timers, notifications, and cursor position.
- [ ] **Step 2: Write failing tests** proving `register()` reserves `SUPER + M`, defines submap `mouse`, registers NumPad movement/click/hold/release/exit bindings, supports NumLock-on and NumLock-off aliases, and performs no external command execution.
- [ ] **Step 3: Add failing behavior tests** for cursor movement, normalized diagonals, acceleration reset on release, left/right/middle clicks, double-click timer, held-left release, and cleanup when leaving the submap/config unload.
- [ ] **Step 4: Run tests and confirm RED** because `hypr.workstation.mouse` does not exist.
- [ ] **Step 5: Implement `mouse.lua` minimally** using `hl.define_submap`, `hl.bind`, `hl.get_cursor_pos`, `hl.dispatch(hl.dsp.cursor.move(...))`, `hl.dsp.send_key_state`, `hl.timer`, `hl.on`, and notifications.
- [ ] **Step 6: Implement `hypr/bindings.lua`**: load `~/.local/state/hyprland_config/active.lua` with `dofile` when present, `dofile(state.preserved_bindings)` when recorded, then call `mouse.register(hl, o)`.
- [ ] **Step 7: Run all tests** and keep them green.

### Task 3: Lua install primitives and installer

**Files:**
- Create: `lua/workstation/command.lua`
- Create: `lua/workstation/paths.lua`
- Create: `lua/workstation/install_state.lua`
- Create: `lua/workstation/installer.lua`
- Create: `tests/installer_test.lua`
- Create: `install.lua`

**Interfaces:**
- Produces: `command.quote`, `command.run`, `command.capture`, `command.exists`, `command.is_symlink`, `command.realpath`.
- Produces: `paths.join`, `paths.dirname`.
- Produces: `install_state.write(path, state)` and `install_state.read(path)`.
- Produces: `installer.install({ home, repo_root, timestamp? }) -> result`.

- [ ] **Step 1: Write failing integration tests** using a temporary HOME directory. Cover fresh install, preservation of an existing `bindings.lua`, preservation of an existing `hypr/workstation`, correct symlink targets, generated active state, and a second idempotent install that creates no new backup.
- [ ] **Step 2: Add failure tests** for an inconsistent active state and for a managed target unexpectedly replaced by an unrelated file after installation.
- [ ] **Step 3: Run tests and confirm RED.**
- [ ] **Step 4: Implement shell-safe coreutils wrappers**. Every interpolated path must pass through single-quote escaping.
- [ ] **Step 5: Implement state serialization** as a generated Lua data table containing `repo_root`, `backup_dir`, `preserved_bindings`, and `preserved_workstation`.
- [ ] **Step 6: Implement installer behavior**: validate sources, create `~/.config/hypr` and state directories, preserve conflicts into one timestamped backup, create the two symlinks, write active state only after successful linking, and detect already-correct installation before backing up anything.
- [ ] **Step 7: Implement root `install.lua`** that prepends `<repo>/lua/?.lua` and `<repo>/lua/?/init.lua` to `package.path`, resolves repository root from its own path, and invokes `installer.install`.
- [ ] **Step 8: Run all tests.**

### Task 4: Safe uninstall and verification

**Files:**
- Create: `lua/workstation/uninstaller.lua`
- Create: `lua/workstation/verifier.lua`
- Create: `tests/uninstaller_test.lua`
- Create: `tests/verifier_test.lua`
- Create: `uninstall.lua`
- Create: `verify.lua`

**Interfaces:**
- Produces: `uninstaller.uninstall({ home, repo_root? }) -> result`.
- Produces: `verifier.verify({ home, repo_root }) -> { ok, checks }`.

- [ ] **Step 1: Write failing uninstall tests**: project-owned links are removed, preserved files/directories are restored, active state is removed, unrelated replacement targets cause an abort instead of deletion, and uninstall with no active state is harmless.
- [ ] **Step 2: Write failing verifier tests** for correct installation and for broken/misdirected links and inconsistent state.
- [ ] **Step 3: Run tests and confirm RED.**
- [ ] **Step 4: Implement uninstaller** with ownership checks based on resolved symlink targets before any deletion, then restore preserved paths from the recorded backup.
- [ ] **Step 5: Implement verifier** checking `lua5.1`, `luac5.1`, project files, active state, symlinks, and source/destination safety. Syntax validation runs `luac5.1 -p` on repository Lua files.
- [ ] **Step 6: Add root `uninstall.lua` and `verify.lua` launchers** using the same package-path/bootstrap pattern as `install.lua`.
- [ ] **Step 7: Run all tests.**

### Task 5: Documentation and final verification

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Document purpose, Lua-first architecture, requirements, install/verify/uninstall commands, Mouse Mode controls, and the explicit v0.2+ roadmap.**
- [ ] **Step 2: Run `lua5.1 tests/run.lua`.** Expected: all tests PASS.
- [ ] **Step 3: Run `lua5.1 verify.lua` in a test installation context** rather than mutating the developer's real `~/.config/hypr`.
- [ ] **Step 4: Run `luac5.1 -p` across every committed `.lua` file.** Expected: no syntax errors.
- [ ] **Step 5: Review the branch diff for accidental `/usr/share/omarchy` writes, Bash/Python implementation files, ydotool/uinput dependencies, and blocking I/O inside Mouse Mode callbacks.** Expected: none.
- [ ] **Step 6: Perform manual Omarchy acceptance after checkout on the target machine:** install, reload Hyprland, test all Mouse Mode mappings with NumLock both states, test held-button cleanup, rerun installer, verify, uninstall, and verify previous bindings are restored.

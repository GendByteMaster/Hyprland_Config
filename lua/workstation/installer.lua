local command = require("workstation.command")
local paths = require("workstation.paths")
local install_state = require("workstation.install_state")

local M = {}

local HUD_PLUGIN_ID = "gendbyte.mouse-hud"
local SYSTEM_MONITOR_PLUGIN_ID = "gendbyte.system-monitor"
local SYSTEM_MONITOR_SECTION = "right"

local function assert_ok(value, message)
  if not value then
    error(message, 2)
  end
  return value
end

local function target_is(target, source)
  if not command.is_symlink(target) then
    return false
  end

  local target_real = command.realpath(target)
  local source_real = command.realpath(source)
  return target_real ~= nil and source_real ~= nil and target_real == source_real
end

local function choose_backup_dir(backups_root, timestamp)
  local base = paths.join(backups_root, timestamp)
  if not command.exists_or_symlink(base) then
    return base
  end

  local index = 1
  while command.exists_or_symlink(base .. "-" .. index) do
    index = index + 1
  end
  return base .. "-" .. index
end

local function default_runtime()
  return {
    command_exists = command.command_exists,
  }
end

local function default_omarchy_runtime()
  return {
    available = function()
      return command.command_exists("omarchy") and command.command_exists("omarchy-shell")
    end,
    rescan_plugins = function()
      return command.run("omarchy-shell shell rescanPlugins")
    end,
    wait_for_plugin = function(id)
      local filter = "any(.[]; .id == $id)"
      local poll = "attempt=0; while [ \"$attempt\" -lt 40 ]; do "
        .. "if omarchy plugin list --json | jq -e --arg id " .. command.quote(id) .. " "
        .. command.quote(filter) .. " >/dev/null 2>&1; then exit 0; fi; "
        .. "attempt=$((attempt + 1)); sleep 0.05; done; exit 1"
      return command.run(poll)
    end,
    enable_plugin = function(id, section)
      return command.run(
        "omarchy plugin enable " .. command.quote(id)
          .. " --section " .. command.quote(section)
      )
    end,
    disable_plugin = function(id)
      return command.run("omarchy plugin disable " .. command.quote(id))
    end,
  }
end

local function rescan_plugins(runtime)
  if type(runtime.rescan_plugins) ~= "function" then
    return true
  end
  return runtime.rescan_plugins()
end

local function wait_for_plugin(runtime, id)
  if type(runtime.wait_for_plugin) ~= "function" then
    return true
  end
  return runtime.wait_for_plugin(id)
end

local function ensure_unoccupied_or_owned(target, source, label)
  if target_is(target, source) then
    return true
  end
  if command.exists_or_symlink(target) then
    error(label .. " path is occupied by another file", 2)
  end
  return false
end

local function state_changed(active, next_state)
  if not active or active.version ~= 2 then
    return true
  end

  return active.launcher ~= next_state.launcher
    or active.omarchy_hud ~= next_state.omarchy_hud
    or active.omarchy_system_monitor ~= next_state.omarchy_system_monitor
end

local function remove_created(created)
  for index = #created, 1, -1 do
    command.remove(created[index])
  end
end

local function link_component(source, target, label, created)
  if target_is(target, source) then
    return false
  end
  if command.exists_or_symlink(target) then
    error(label .. " path is occupied by another file", 2)
  end

  assert_ok(command.mkdir_p(paths.dirname(target)), "failed to create directory for " .. label)
  assert_ok(command.symlink(source, target), "failed to link " .. label)
  created[#created + 1] = target
  return true
end

function M.install(options)
  options = options or {}

  local home = assert(options.home, "home is required")
  local repo_root = assert_ok(
    command.realpath(assert(options.repo_root, "repo_root is required")),
    "repository root does not exist"
  )
  local timestamp = options.timestamp or os.date("%Y%m%d-%H%M%S")
  local runtime = options.runtime or default_runtime()
  local omarchy_runtime = options.omarchy_runtime or default_omarchy_runtime()

  assert_ok(
    type(runtime.command_exists) == "function" and runtime.command_exists("qs"),
    "Quickshell (qs) is required for the Project Launcher"
  )

  local source_bindings = paths.join(repo_root, "hypr", "bindings.lua")
  local source_workstation = paths.join(repo_root, "hypr", "workstation")
  local source_launcher = paths.join(repo_root, "bin", "hyprland-workstation-launcher")
  local source_quickshell = paths.join(repo_root, "quickshell", "gendbyte-project-launcher")
  local source_backend = paths.join(repo_root, "project-launcher.lua")
  local source_hud = paths.join(repo_root, "omarchy", "plugins", HUD_PLUGIN_ID)
  local source_system_monitor = paths.join(repo_root, "omarchy", "plugins", SYSTEM_MONITOR_PLUGIN_ID)

  assert_ok(command.exists(source_bindings), "managed bindings.lua is missing")
  assert_ok(command.exists(source_workstation), "managed workstation directory is missing")
  assert_ok(command.exists(source_launcher), "Project Launcher wrapper is missing")
  assert_ok(command.exists(source_quickshell), "Project Launcher Quickshell config is missing")
  assert_ok(command.exists(source_backend), "Project Launcher backend is missing")

  local config_dir = paths.join(home, ".config", "hypr")
  local target_bindings = paths.join(config_dir, "bindings.lua")
  local target_workstation = paths.join(config_dir, "workstation")
  local target_launcher = paths.join(home, ".local", "bin", "hyprland-workstation-launcher")
  local target_quickshell = paths.join(home, ".config", "quickshell", "gendbyte-project-launcher")
  local omarchy_plugins_dir = paths.join(home, ".config", "omarchy", "plugins")
  local target_hud = paths.join(omarchy_plugins_dir, HUD_PLUGIN_ID)
  local target_system_monitor = paths.join(omarchy_plugins_dir, SYSTEM_MONITOR_PLUGIN_ID)

  local state_dir = paths.join(home, ".local", "state", "hyprland_config")
  local backups_root = paths.join(state_dir, "backups")
  local state_path = paths.join(state_dir, "active.state")
  local preserved_bindings_link = paths.join(state_dir, "preserved_bindings.lua")

  local active, state_error = install_state.read(state_path)
  if state_error then
    error(state_error)
  end

  local omarchy_available = type(omarchy_runtime.available) == "function"
    and omarchy_runtime.available()
    or false

  if active then
    if active.repo_root ~= repo_root then
      error("another Hyprland_Config repository is already active")
    end

    if not target_is(target_bindings, source_bindings)
      or not target_is(target_workstation, source_workstation) then
      error("active installation state exists but managed Hyprland targets were modified")
    end

    local launcher_owned = ensure_unoccupied_or_owned(
      target_launcher,
      source_launcher,
      "Project Launcher wrapper"
    )
    local quickshell_owned = ensure_unoccupied_or_owned(
      target_quickshell,
      source_quickshell,
      "Project Launcher Quickshell config"
    )

    local hud_owned = target_is(target_hud, source_hud)
    local monitor_owned = target_is(target_system_monitor, source_system_monitor)

    if active.version == 1 then
      if command.exists_or_symlink(target_hud) and not hud_owned then
        error("managed Mouse Mode HUD plugin was modified")
      end
      if command.exists_or_symlink(target_system_monitor) and not monitor_owned then
        error("managed System Monitor plugin was modified")
      end
    else
      if active.omarchy_hud and command.exists_or_symlink(target_hud) and not hud_owned then
        error("managed Mouse Mode HUD plugin was modified")
      end
      if active.omarchy_system_monitor
        and command.exists_or_symlink(target_system_monitor)
        and not monitor_owned then
        error("managed System Monitor plugin was modified")
      end
    end

    if omarchy_available then
      assert_ok(command.exists(source_hud), "Mouse Mode HUD plugin is missing")
      assert_ok(command.exists(source_system_monitor), "System Monitor plugin is missing")

      if not hud_owned and command.exists_or_symlink(target_hud) then
        error("Mouse Mode HUD plugin path is occupied by another file")
      end
      if not monitor_owned and command.exists_or_symlink(target_system_monitor) then
        error("System Monitor plugin path is occupied by another file")
      end
    end

    local created = {}
    local changed = false

    local ok, err = pcall(function()
      if not launcher_owned then
        link_component(source_launcher, target_launcher, "Project Launcher wrapper", created)
        changed = true
      end
      if not quickshell_owned then
        link_component(source_quickshell, target_quickshell, "Project Launcher Quickshell config", created)
        changed = true
      end

      if omarchy_available then
        if not hud_owned then
          link_component(source_hud, target_hud, "Mouse Mode HUD plugin", created)
          hud_owned = true
          changed = true
        end

        if not monitor_owned then
          link_component(
            source_system_monitor,
            target_system_monitor,
            "System Monitor plugin",
            created
          )
          monitor_owned = true
          changed = true

          assert_ok(rescan_plugins(omarchy_runtime), "failed to rescan Omarchy plugins")
          assert_ok(
            wait_for_plugin(omarchy_runtime, SYSTEM_MONITOR_PLUGIN_ID),
            "System Monitor plugin was not discovered after rescan"
          )
          assert_ok(
            omarchy_runtime.enable_plugin(SYSTEM_MONITOR_PLUGIN_ID, SYSTEM_MONITOR_SECTION),
            "failed to enable System Monitor plugin"
          )
        end
      end

      launcher_owned = target_is(target_launcher, source_launcher)
        and target_is(target_quickshell, source_quickshell)
      hud_owned = target_is(target_hud, source_hud)
      monitor_owned = target_is(target_system_monitor, source_system_monitor)

      local next_state = {
        version = 2,
        repo_root = repo_root,
        backup_dir = active.backup_dir or "",
        preserved_bindings = active.preserved_bindings,
        preserved_workstation = active.preserved_workstation,
        launcher = launcher_owned,
        omarchy_hud = hud_owned,
        omarchy_system_monitor = monitor_owned,
      }

      if state_changed(active, next_state) then
        install_state.write(state_path, next_state)
        changed = true
      end
    end)

    if not ok then
      remove_created(created)
      error(err, 0)
    end

    return {
      changed = changed,
      state_path = state_path,
      backup_dir = active.backup_dir or "",
      components = {
        launcher = launcher_owned,
        omarchy_hud = hud_owned,
        omarchy_system_monitor = monitor_owned,
      },
      omarchy_available = omarchy_available,
    }
  end

  if target_is(target_bindings, source_bindings) or target_is(target_workstation, source_workstation) then
    error("managed Hyprland links exist without active installation state")
  end
  if command.exists_or_symlink(target_launcher) then
    error("Project Launcher wrapper path already exists")
  end
  if command.exists_or_symlink(target_quickshell) then
    error("Project Launcher Quickshell config path already exists")
  end
  if command.exists_or_symlink(preserved_bindings_link) then
    error("preserved bindings marker exists without active installation state")
  end

  if omarchy_available then
    assert_ok(command.exists(source_hud), "Mouse Mode HUD plugin is missing")
    assert_ok(command.exists(source_system_monitor), "System Monitor plugin is missing")
    if command.exists_or_symlink(target_hud) then
      error("Mouse Mode HUD plugin path already exists")
    end
    if command.exists_or_symlink(target_system_monitor) then
      error("System Monitor plugin path already exists")
    end
  end

  local has_bindings = command.exists_or_symlink(target_bindings)
  local has_workstation = command.exists_or_symlink(target_workstation)
  local backup_dir = choose_backup_dir(backups_root, timestamp)
  local backup_hypr = paths.join(backup_dir, "hypr")
  local backup_bindings = paths.join(backup_hypr, "bindings.lua")
  local backup_workstation = paths.join(backup_hypr, "workstation")

  assert_ok(command.mkdir_p(config_dir), "failed to create Hyprland config directory")
  assert_ok(command.mkdir_p(paths.dirname(target_launcher)), "failed to create launcher bin directory")
  assert_ok(command.mkdir_p(paths.dirname(target_quickshell)), "failed to create Quickshell config directory")
  assert_ok(command.mkdir_p(backups_root), "failed to create state directory")
  if omarchy_available then
    assert_ok(command.mkdir_p(omarchy_plugins_dir), "failed to create Omarchy plugins directory")
  end

  if has_bindings or has_workstation then
    assert_ok(command.mkdir_p(backup_hypr), "failed to create backup directory")
  end

  local moved_bindings = false
  local moved_workstation = false
  local preserved_linked = false
  local created = {}

  local hud_owned = false
  local monitor_owned = false

  local ok, err = pcall(function()
    if has_bindings then
      assert_ok(command.move(target_bindings, backup_bindings), "failed to preserve existing bindings.lua")
      moved_bindings = true
    end
    if has_workstation then
      assert_ok(
        command.move(target_workstation, backup_workstation),
        "failed to preserve existing workstation directory"
      )
      moved_workstation = true
    end

    link_component(source_bindings, target_bindings, "managed bindings.lua", created)
    link_component(source_workstation, target_workstation, "managed workstation directory", created)
    link_component(source_launcher, target_launcher, "Project Launcher wrapper", created)
    link_component(
      source_quickshell,
      target_quickshell,
      "Project Launcher Quickshell config",
      created
    )

    if moved_bindings then
      assert_ok(
        command.symlink(backup_bindings, preserved_bindings_link),
        "failed to expose preserved bindings"
      )
      preserved_linked = true
    end

    if omarchy_available then
      link_component(source_hud, target_hud, "Mouse Mode HUD plugin", created)
      hud_owned = true

      link_component(
        source_system_monitor,
        target_system_monitor,
        "System Monitor plugin",
        created
      )
      monitor_owned = true

      assert_ok(rescan_plugins(omarchy_runtime), "failed to rescan Omarchy plugins")
      assert_ok(
        wait_for_plugin(omarchy_runtime, SYSTEM_MONITOR_PLUGIN_ID),
        "System Monitor plugin was not discovered after rescan"
      )
      assert_ok(
        omarchy_runtime.enable_plugin(SYSTEM_MONITOR_PLUGIN_ID, SYSTEM_MONITOR_SECTION),
        "failed to enable System Monitor plugin"
      )
    end

    install_state.write(state_path, {
      version = 2,
      repo_root = repo_root,
      backup_dir = (has_bindings or has_workstation) and backup_dir or "",
      preserved_bindings = moved_bindings,
      preserved_workstation = moved_workstation,
      launcher = true,
      omarchy_hud = hud_owned,
      omarchy_system_monitor = monitor_owned,
    })
  end)

  if not ok then
    command.remove(state_path)
    if preserved_linked then
      command.remove(preserved_bindings_link)
    end
    remove_created(created)
    if moved_workstation then
      command.move(backup_workstation, target_workstation)
    end
    if moved_bindings then
      command.move(backup_bindings, target_bindings)
    end
    error(err, 0)
  end

  return {
    changed = true,
    state_path = state_path,
    backup_dir = (has_bindings or has_workstation) and backup_dir or "",
    components = {
      launcher = true,
      omarchy_hud = hud_owned,
      omarchy_system_monitor = monitor_owned,
    },
    omarchy_available = omarchy_available,
  }
end

return M

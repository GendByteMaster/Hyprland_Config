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

local function default_omarchy_runtime()
  return {
    available = function()
      return command.command_exists("omarchy") and command.command_exists("omarchy-shell")
    end,
    rescan_plugins = function()
      return command.run("omarchy-shell shell rescanPlugins")
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

function M.install(options)
  local home = assert(options.home, "home is required")
  local repo_root = assert_ok(command.realpath(assert(options.repo_root, "repo_root is required")), "repository root does not exist")
  local timestamp = options.timestamp or os.date("%Y%m%d-%H%M%S")
  local omarchy_runtime = options.omarchy_runtime or default_omarchy_runtime()

  local source_bindings = paths.join(repo_root, "hypr", "bindings.lua")
  local source_workstation = paths.join(repo_root, "hypr", "workstation")
  local source_hud = paths.join(repo_root, "omarchy", "plugins", HUD_PLUGIN_ID)
  local source_system_monitor = paths.join(repo_root, "omarchy", "plugins", SYSTEM_MONITOR_PLUGIN_ID)
  assert_ok(command.exists(source_bindings), "managed bindings.lua is missing")
  assert_ok(command.exists(source_workstation), "managed workstation directory is missing")
  assert_ok(command.exists(source_hud), "Mouse Mode HUD plugin is missing")
  assert_ok(command.exists(source_system_monitor), "System Monitor plugin is missing")

  local config_dir = paths.join(home, ".config", "hypr")
  local target_bindings = paths.join(config_dir, "bindings.lua")
  local target_workstation = paths.join(config_dir, "workstation")
  local omarchy_plugins_dir = paths.join(home, ".config", "omarchy", "plugins")
  local target_hud = paths.join(omarchy_plugins_dir, HUD_PLUGIN_ID)
  local target_system_monitor = paths.join(omarchy_plugins_dir, SYSTEM_MONITOR_PLUGIN_ID)
  local state_dir = paths.join(home, ".local", "state", "hyprland_config")
  local backups_root = paths.join(state_dir, "backups")
  local state_path = paths.join(state_dir, "active.state")
  local preserved_bindings_link = paths.join(state_dir, "preserved_bindings.lua")

  assert_ok(command.mkdir_p(config_dir), "failed to create Hyprland config directory")
  assert_ok(command.mkdir_p(omarchy_plugins_dir), "failed to create Omarchy plugins directory")
  assert_ok(command.mkdir_p(backups_root), "failed to create state directory")

  local active, state_error = install_state.read(state_path)
  if state_error then
    error(state_error)
  end

  if active then
    if active.repo_root ~= repo_root then
      error("another Hyprland_Config repository is already active")
    end
    if not target_is(target_bindings, source_bindings) or not target_is(target_workstation, source_workstation) then
      error("active installation state exists but managed Hyprland targets were modified")
    end

    local hud_installed = target_is(target_hud, source_hud)
    local monitor_installed = target_is(target_system_monitor, source_system_monitor)

    if not hud_installed and command.exists_or_symlink(target_hud) then
      error("Mouse Mode HUD plugin path is occupied by another file")
    end
    if not monitor_installed and command.exists_or_symlink(target_system_monitor) then
      error("System Monitor plugin path is occupied by another file")
    end
    if hud_installed and monitor_installed then
      return { changed = false, state_path = state_path, backup_dir = active.backup_dir }
    end
    if not monitor_installed then
      assert_ok(omarchy_runtime.available(), "Omarchy CLI and shell are required to enable the System Monitor plugin")
    end

    local linked_hud = false
    local linked_monitor = false
    local ok, err = pcall(function()
      if not hud_installed then
        assert_ok(command.symlink(source_hud, target_hud), "failed to link Mouse Mode HUD plugin")
        linked_hud = true
      end
      if not monitor_installed then
        assert_ok(command.symlink(source_system_monitor, target_system_monitor), "failed to link System Monitor plugin")
        linked_monitor = true
        assert_ok(rescan_plugins(omarchy_runtime), "failed to rescan Omarchy plugins")
        assert_ok(
          omarchy_runtime.enable_plugin(SYSTEM_MONITOR_PLUGIN_ID, SYSTEM_MONITOR_SECTION),
          "failed to enable System Monitor plugin"
        )
      end
    end)

    if not ok then
      if linked_monitor then command.remove(target_system_monitor) end
      if linked_hud then command.remove(target_hud) end
      error(err, 0)
    end

    return { changed = true, state_path = state_path, backup_dir = active.backup_dir }
  end

  if target_is(target_bindings, source_bindings) or target_is(target_workstation, source_workstation) then
    error("managed Hyprland links exist without active installation state")
  end
  if command.exists_or_symlink(target_hud) then
    error("Mouse Mode HUD plugin path already exists")
  end
  if command.exists_or_symlink(target_system_monitor) then
    error("System Monitor plugin path already exists")
  end
  if command.exists_or_symlink(preserved_bindings_link) then
    error("preserved bindings marker exists without active installation state")
  end
  assert_ok(omarchy_runtime.available(), "Omarchy CLI and shell are required to enable the System Monitor plugin")

  local has_bindings = command.exists_or_symlink(target_bindings)
  local has_workstation = command.exists_or_symlink(target_workstation)
  local backup_dir = choose_backup_dir(backups_root, timestamp)
  local backup_hypr = paths.join(backup_dir, "hypr")
  local backup_bindings = paths.join(backup_hypr, "bindings.lua")
  local backup_workstation = paths.join(backup_hypr, "workstation")

  if has_bindings or has_workstation then
    assert_ok(command.mkdir_p(backup_hypr), "failed to create backup directory")
  end

  local moved_bindings = false
  local moved_workstation = false
  local linked_bindings = false
  local linked_workstation = false
  local linked_hud = false
  local linked_monitor = false
  local preserved_linked = false

  local ok, err = pcall(function()
    if has_bindings then
      assert_ok(command.move(target_bindings, backup_bindings), "failed to preserve existing bindings.lua")
      moved_bindings = true
    end
    if has_workstation then
      assert_ok(command.move(target_workstation, backup_workstation), "failed to preserve existing workstation directory")
      moved_workstation = true
    end

    assert_ok(command.symlink(source_bindings, target_bindings), "failed to link managed bindings.lua")
    linked_bindings = true
    assert_ok(command.symlink(source_workstation, target_workstation), "failed to link managed workstation directory")
    linked_workstation = true
    assert_ok(command.symlink(source_hud, target_hud), "failed to link Mouse Mode HUD plugin")
    linked_hud = true
    assert_ok(command.symlink(source_system_monitor, target_system_monitor), "failed to link System Monitor plugin")
    linked_monitor = true

    if moved_bindings then
      assert_ok(command.symlink(backup_bindings, preserved_bindings_link), "failed to expose preserved bindings")
      preserved_linked = true
    end

    install_state.write(state_path, {
      version = 1,
      repo_root = repo_root,
      backup_dir = (has_bindings or has_workstation) and backup_dir or "",
      preserved_bindings = moved_bindings,
      preserved_workstation = moved_workstation,
    })

    assert_ok(rescan_plugins(omarchy_runtime), "failed to rescan Omarchy plugins")
    assert_ok(
      omarchy_runtime.enable_plugin(SYSTEM_MONITOR_PLUGIN_ID, SYSTEM_MONITOR_SECTION),
      "failed to enable System Monitor plugin"
    )
  end)

  if not ok then
    command.remove(state_path)
    if preserved_linked then command.remove(preserved_bindings_link) end
    if linked_monitor then command.remove(target_system_monitor) end
    if linked_hud then command.remove(target_hud) end
    if linked_workstation then command.remove(target_workstation) end
    if linked_bindings then command.remove(target_bindings) end
    if moved_workstation then command.move(backup_workstation, target_workstation) end
    if moved_bindings then command.move(backup_bindings, target_bindings) end
    error(err, 0)
  end

  return {
    changed = true,
    state_path = state_path,
    backup_dir = (has_bindings or has_workstation) and backup_dir or "",
  }
end

return M

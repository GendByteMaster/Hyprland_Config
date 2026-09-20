local command = require("workstation.command")
local paths = require("workstation.paths")
local install_state = require("workstation.install_state")

local M = {}

local HUD_PLUGIN_ID = "gendbyte.mouse-hud"
local SYSTEM_MONITOR_PLUGIN_ID = "gendbyte.system-monitor"

local function target_is(target, source)
  if not command.is_symlink(target) then
    return false
  end

  local target_real = command.realpath(target)
  local source_real = command.realpath(source)
  return target_real ~= nil and source_real ~= nil and target_real == source_real
end

local function default_omarchy_runtime()
  return {
    available = function()
      return command.command_exists("omarchy")
    end,
    disable_plugin = function(id)
      return command.run("omarchy plugin disable " .. command.quote(id))
    end,
  }
end

local function require_owned(target, source, message)
  if not target_is(target, source) then
    error(message, 3)
  end
end

function M.uninstall(options)
  options = options or {}

  local home = assert(options.home, "home is required")
  local state_dir = paths.join(home, ".local", "state", "hyprland_config")
  local state_path = paths.join(state_dir, "active.state")
  local preserved_bindings_link = paths.join(state_dir, "preserved_bindings.lua")
  local state, state_error = install_state.read(state_path)

  if state_error then
    error(state_error)
  end
  if not state then
    return { changed = false }
  end

  local omarchy_runtime = options.omarchy_runtime or default_omarchy_runtime()
  local repo_root = state.repo_root

  local source_bindings = paths.join(repo_root, "hypr", "bindings.lua")
  local source_workstation = paths.join(repo_root, "hypr", "workstation")
  local source_launcher = paths.join(repo_root, "bin", "hyprland-workstation-launcher")
  local source_quickshell = paths.join(repo_root, "quickshell", "gendbyte-project-launcher")
  local source_overview_launcher = paths.join(repo_root, "bin", "hyprland-workspace-overview")
  local source_overview_quickshell = paths.join(repo_root, "quickshell", "gendbyte-workspace-overview")
  local source_hud = paths.join(repo_root, "omarchy", "plugins", HUD_PLUGIN_ID)
  local source_system_monitor = paths.join(repo_root, "omarchy", "plugins", SYSTEM_MONITOR_PLUGIN_ID)

  local target_bindings = paths.join(home, ".config", "hypr", "bindings.lua")
  local target_workstation = paths.join(home, ".config", "hypr", "workstation")
  local target_launcher = paths.join(home, ".local", "bin", "hyprland-workstation-launcher")
  local target_quickshell = paths.join(home, ".config", "quickshell", "gendbyte-project-launcher")
  local target_overview_launcher = paths.join(home, ".local", "bin", "hyprland-workspace-overview")
  local target_overview_quickshell = paths.join(home, ".config", "quickshell", "gendbyte-workspace-overview")
  local target_hud = paths.join(home, ".config", "omarchy", "plugins", HUD_PLUGIN_ID)
  local target_system_monitor = paths.join(home, ".config", "omarchy", "plugins", SYSTEM_MONITOR_PLUGIN_ID)

  local backup_bindings = state.backup_dir ~= "" and paths.join(state.backup_dir, "hypr", "bindings.lua") or nil
  local backup_workstation = state.backup_dir ~= "" and paths.join(state.backup_dir, "hypr", "workstation") or nil

  require_owned(
    target_bindings,
    source_bindings,
    "managed bindings.lua was modified; refusing to remove it"
  )
  require_owned(
    target_workstation,
    source_workstation,
    "managed workstation directory was modified; refusing to remove it"
  )

  local launcher_owned = state.version >= 2 and state.launcher == true
  if launcher_owned then
    require_owned(
      target_launcher,
      source_launcher,
      "managed Project Launcher wrapper was modified; refusing to remove it"
    )
    require_owned(
      target_quickshell,
      source_quickshell,
      "managed Project Launcher Quickshell config was modified; refusing to remove it"
    )
  end

  local overview_owned = state.version >= 3 and state.workspace_overview == true
  if overview_owned then
    require_owned(
      target_overview_launcher,
      source_overview_launcher,
      "managed Workspace Overview wrapper was modified; refusing to remove it"
    )
    require_owned(
      target_overview_quickshell,
      source_overview_quickshell,
      "managed Workspace Overview Quickshell config was modified; refusing to remove it"
    )
  end

  local hud_owned
  local monitor_owned
  if state.version >= 2 then
    hud_owned = state.omarchy_hud == true
    monitor_owned = state.omarchy_system_monitor == true
  else
    -- v1 predates component flags. Infer only repository-owned legacy links.
    hud_owned = target_is(target_hud, source_hud)
    monitor_owned = target_is(target_system_monitor, source_system_monitor)
  end

  if hud_owned then
    require_owned(
      target_hud,
      source_hud,
      "managed Mouse Mode HUD plugin was modified; refusing to remove it"
    )
  end

  local monitor_present = command.exists_or_symlink(target_system_monitor)
  if monitor_owned and monitor_present then
    require_owned(
      target_system_monitor,
      source_system_monitor,
      "managed System Monitor plugin was modified; refusing to remove it"
    )
  end

  if state.preserved_bindings then
    if not backup_bindings or not command.exists_or_symlink(backup_bindings) then
      error("preserved bindings backup is missing")
    end
    if not target_is(preserved_bindings_link, backup_bindings) then
      error("preserved bindings marker is inconsistent")
    end
  end
  if state.preserved_workstation
    and (not backup_workstation or not command.exists_or_symlink(backup_workstation)) then
    error("preserved workstation backup is missing")
  end

  -- Disable Omarchy integration before deleting anything. Generic installs
  -- never enter this branch and therefore do not require Omarchy at uninstall.
  if monitor_owned and monitor_present then
    if type(omarchy_runtime.available) ~= "function" or not omarchy_runtime.available() then
      error("Omarchy CLI is required to disable the System Monitor plugin")
    end
    if type(omarchy_runtime.disable_plugin) ~= "function"
      or not omarchy_runtime.disable_plugin(SYSTEM_MONITOR_PLUGIN_ID) then
      error("failed to disable System Monitor plugin")
    end
  end

  assert(command.remove(target_bindings), "failed to remove managed bindings.lua")
  assert(command.remove(target_workstation), "failed to remove managed workstation directory")

  if launcher_owned then
    assert(command.remove(target_launcher), "failed to remove Project Launcher wrapper")
    assert(command.remove(target_quickshell), "failed to remove Project Launcher Quickshell config")
  end

  if overview_owned then
    assert(command.remove(target_overview_launcher), "failed to remove Workspace Overview wrapper")
    assert(
      command.remove(target_overview_quickshell),
      "failed to remove Workspace Overview Quickshell config"
    )
  end

  if hud_owned then
    assert(command.remove(target_hud), "failed to remove Mouse Mode HUD plugin")
  end
  if monitor_owned and monitor_present then
    assert(command.remove(target_system_monitor), "failed to remove System Monitor plugin")
  end

  if state.preserved_bindings then
    assert(
      command.move(backup_bindings, target_bindings),
      "failed to restore previous bindings.lua"
    )
  end
  if state.preserved_workstation then
    assert(
      command.move(backup_workstation, target_workstation),
      "failed to restore previous workstation directory"
    )
  end

  if command.exists_or_symlink(preserved_bindings_link) then
    assert(
      command.remove(preserved_bindings_link),
      "failed to remove preserved bindings marker"
    )
  end
  assert(command.remove(state_path), "failed to remove active install state")

  return {
    changed = true,
    restored_from = state.backup_dir,
  }
end

return M

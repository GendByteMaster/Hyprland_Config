local command = require("workstation.command")
local paths = require("workstation.paths")
local install_state = require("workstation.install_state")

local M = {}

local HUD_PLUGIN_ID = "gendbyte.mouse-hud"

local function target_is(target, source)
  if not command.is_symlink(target) then
    return false
  end

  local target_real = command.realpath(target)
  local source_real = command.realpath(source)
  return target_real ~= nil and source_real ~= nil and target_real == source_real
end

function M.uninstall(options)
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

  local repo_root = state.repo_root
  local source_bindings = paths.join(repo_root, "hypr", "bindings.lua")
  local source_workstation = paths.join(repo_root, "hypr", "workstation")
  local source_hud = paths.join(repo_root, "omarchy", "plugins", HUD_PLUGIN_ID)
  local config_dir = paths.join(home, ".config", "hypr")
  local target_bindings = paths.join(config_dir, "bindings.lua")
  local target_workstation = paths.join(config_dir, "workstation")
  local target_hud = paths.join(home, ".config", "omarchy", "plugins", HUD_PLUGIN_ID)
  local backup_bindings = state.backup_dir ~= "" and paths.join(state.backup_dir, "hypr", "bindings.lua") or nil
  local backup_workstation = state.backup_dir ~= "" and paths.join(state.backup_dir, "hypr", "workstation") or nil

  if not target_is(target_bindings, source_bindings) then
    error("managed bindings.lua was modified; refusing to remove it")
  end
  if not target_is(target_workstation, source_workstation) then
    error("managed workstation directory was modified; refusing to remove it")
  end
  if not target_is(target_hud, source_hud) then
    error("managed Mouse Mode HUD plugin was modified; refusing to remove it")
  end
  if state.preserved_bindings then
    if not backup_bindings or not command.exists_or_symlink(backup_bindings) then
      error("preserved bindings backup is missing")
    end
    if not target_is(preserved_bindings_link, backup_bindings) then
      error("preserved bindings marker is inconsistent")
    end
  end
  if state.preserved_workstation and (not backup_workstation or not command.exists_or_symlink(backup_workstation)) then
    error("preserved workstation backup is missing")
  end

  assert(command.remove(target_bindings), "failed to remove managed bindings.lua")
  assert(command.remove(target_workstation), "failed to remove managed workstation directory")
  assert(command.remove(target_hud), "failed to remove Mouse Mode HUD plugin")

  if state.preserved_bindings then
    assert(command.move(backup_bindings, target_bindings), "failed to restore previous bindings.lua")
  end
  if state.preserved_workstation then
    assert(command.move(backup_workstation, target_workstation), "failed to restore previous workstation directory")
  end

  if command.exists_or_symlink(preserved_bindings_link) then
    assert(command.remove(preserved_bindings_link), "failed to remove preserved bindings marker")
  end
  assert(command.remove(state_path), "failed to remove active install state")

  return { changed = true, restored_from = state.backup_dir }
end

return M

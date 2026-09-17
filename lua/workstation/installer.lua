local command = require("workstation.command")
local paths = require("workstation.paths")
local install_state = require("workstation.install_state")

local M = {}

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

function M.install(options)
  local home = assert(options.home, "home is required")
  local repo_root = assert_ok(command.realpath(assert(options.repo_root, "repo_root is required")), "repository root does not exist")
  local timestamp = options.timestamp or os.date("%Y%m%d-%H%M%S")

  local source_bindings = paths.join(repo_root, "hypr", "bindings.lua")
  local source_workstation = paths.join(repo_root, "hypr", "workstation")
  assert_ok(command.exists(source_bindings), "managed bindings.lua is missing")
  assert_ok(command.exists(source_workstation), "managed workstation directory is missing")

  local config_dir = paths.join(home, ".config", "hypr")
  local target_bindings = paths.join(config_dir, "bindings.lua")
  local target_workstation = paths.join(config_dir, "workstation")
  local state_dir = paths.join(home, ".local", "state", "hyprland_config")
  local backups_root = paths.join(state_dir, "backups")
  local state_path = paths.join(state_dir, "active.state")
  local preserved_bindings_link = paths.join(state_dir, "preserved_bindings.lua")

  assert_ok(command.mkdir_p(config_dir), "failed to create Hyprland config directory")
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
      error("active installation state exists but managed targets were modified")
    end
    return { changed = false, state_path = state_path, backup_dir = active.backup_dir }
  end

  if target_is(target_bindings, source_bindings) or target_is(target_workstation, source_workstation) then
    error("managed links exist without active installation state")
  end
  if command.exists_or_symlink(preserved_bindings_link) then
    error("preserved bindings marker exists without active installation state")
  end

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
  end)

  if not ok then
    command.remove(state_path)
    if preserved_linked then command.remove(preserved_bindings_link) end
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

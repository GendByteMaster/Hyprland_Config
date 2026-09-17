local command = require("workstation.command")
local paths = require("workstation.paths")
local install_state = require("workstation.install_state")

local M = {}

local function target_is(target, source)
  if not command.is_symlink(target) then
    return false
  end

  local target_real = command.realpath(target)
  local source_real = command.realpath(source)
  return target_real ~= nil and source_real ~= nil and target_real == source_real
end

local function default_runtime()
  return {
    command_exists = command.command_exists,
    syntax_check = function(repo_root)
      local quoted_root = command.quote(repo_root)
      return command.run("find " .. quoted_root .. " -name '*.lua' -type f -print0 | xargs -0 -r -n1 luac5.1 -p")
    end,
  }
end

function M.verify(options)
  local home = assert(options.home, "home is required")
  local repo_root = command.realpath(assert(options.repo_root, "repo_root is required"))
  local runtime = options.runtime or default_runtime()
  local checks = {}
  local overall = true

  local function add(name, ok, detail)
    ok = not not ok
    table.insert(checks, { name = name, ok = ok, detail = detail })
    if not ok then
      overall = false
    end
  end

  add("repository root", repo_root ~= nil, repo_root or "repository does not exist")
  if not repo_root then
    return { ok = false, checks = checks }
  end

  add("repository safety", repo_root:sub(1, #"/usr/share/omarchy") ~= "/usr/share/omarchy", repo_root)
  add("lua5.1", runtime.command_exists("lua5.1"), "lua5.1 must be installed")
  add("luac5.1", runtime.command_exists("luac5.1"), "luac5.1 must be installed")

  local required = {
    paths.join(repo_root, "hypr", "bindings.lua"),
    paths.join(repo_root, "hypr", "workstation", "mouse.lua"),
    paths.join(repo_root, "hypr", "workstation", "mouse_state.lua"),
    paths.join(repo_root, "install.lua"),
    paths.join(repo_root, "uninstall.lua"),
    paths.join(repo_root, "verify.lua"),
  }

  for _, path in ipairs(required) do
    add("file: " .. path:sub(#repo_root + 2), command.exists(path), path)
  end

  local state_dir = paths.join(home, ".local", "state", "hyprland_config")
  local state_path = paths.join(state_dir, "active.state")
  local preserved_bindings_link = paths.join(state_dir, "preserved_bindings.lua")
  local state, state_error = install_state.read(state_path)
  add("install state", state ~= nil and state_error == nil, state_error or state_path)

  if state then
    add("state repository", state.repo_root == repo_root, state.repo_root)

    local source_bindings = paths.join(repo_root, "hypr", "bindings.lua")
    local source_workstation = paths.join(repo_root, "hypr", "workstation")
    local target_bindings = paths.join(home, ".config", "hypr", "bindings.lua")
    local target_workstation = paths.join(home, ".config", "hypr", "workstation")
    add("bindings link", target_is(target_bindings, source_bindings), target_bindings)
    add("workstation link", target_is(target_workstation, source_workstation), target_workstation)

    if state.preserved_bindings then
      local backup_bindings = paths.join(state.backup_dir, "hypr", "bindings.lua")
      add("preserved bindings", command.exists_or_symlink(backup_bindings) and target_is(preserved_bindings_link, backup_bindings), backup_bindings)
    else
      add("preserved bindings", not command.exists_or_symlink(preserved_bindings_link), preserved_bindings_link)
    end
  else
    add("bindings link", false, "cannot validate without install state")
    add("workstation link", false, "cannot validate without install state")
  end

  add("Lua syntax", runtime.syntax_check(repo_root), "luac5.1 -p")
  return { ok = overall, checks = checks }
end

return M

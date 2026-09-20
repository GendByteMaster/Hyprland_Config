local command = require("workstation.command")
local json = require("workstation.json")
local paths = require("workstation.paths")

local M = {}

local function valid_sha(value)
  return type(value) == "string" and #value == 40 and value:match("^%x+$") ~= nil
end

local function valid_repo(value)
  return type(value) == "string"
    and value:match("^https://github%.com/[%w%._%-]+/[%w%._%-]+%.git$") ~= nil
end

function M.validate_manifest(manifest)
  if type(manifest) ~= "table" then
    return nil, "external plugin manifest must be a table"
  end

  local seen = {}
  for index, plugin in ipairs(manifest) do
    if type(plugin) ~= "table" then
      return nil, "external plugin #" .. index .. " must be a table"
    end
    if type(plugin.id) ~= "string"
      or plugin.id:match("^[%w][%w%._%-]+$") == nil then
      return nil, "external plugin #" .. index .. " has an invalid id"
    end
    if seen[plugin.id] then
      return nil, "duplicate external plugin id: " .. plugin.id
    end
    seen[plugin.id] = true

    if not valid_repo(plugin.repo) then
      return nil, "external plugin " .. plugin.id .. " must use a GitHub HTTPS .git URL"
    end
    if not valid_sha(plugin.rev) then
      return nil, "external plugin " .. plugin.id .. " must pin an exact 40-character commit"
    end
    if plugin.enabled ~= nil and type(plugin.enabled) ~= "boolean" then
      return nil, "external plugin " .. plugin.id .. " enabled must be boolean"
    end
    if plugin.section ~= nil
      and (type(plugin.section) ~= "string" or plugin.section == "") then
      return nil, "external plugin " .. plugin.id .. " section must be a non-empty string"
    end
  end

  return true
end

function M.load_manifest(path)
  local ok, manifest = pcall(dofile, path)
  if not ok then
    return nil, "failed to load external plugin manifest: " .. tostring(manifest)
  end

  local valid, err = M.validate_manifest(manifest)
  if not valid then
    return nil, err
  end
  return manifest
end

local function read_manifest_id(directory)
  local file = io.open(paths.join(directory, "manifest.json"), "rb")
  if not file then
    return nil
  end
  local content = file:read("*a")
  file:close()

  local decoded = json.decode(content)
  if type(decoded) ~= "table" or type(decoded.id) ~= "string" then
    return nil
  end
  return decoded.id
end

local function default_runtime()
  return {
    available = function()
      return command.command_exists("omarchy")
        and command.command_exists("omarchy-shell")
    end,
    git_available = function()
      return command.command_exists("git")
    end,
    exists = command.exists_or_symlink,
    is_symlink = command.is_symlink,
    readlink = function(path)
      return command.capture_argv({ "readlink", "--", path })
    end,
    mkdir_p = command.mkdir_p,
    symlink = command.symlink,
    remove = command.remove,
    remove_tree = command.remove_tree,
    move = command.move,
    current_revision = function(directory)
      return command.capture_argv({ "git", "-C", directory, "rev-parse", "HEAD" })
    end,
    manifest_id = read_manifest_id,
    clone_pinned = function(repo, rev, directory)
      if not command.mkdir_p(directory) then
        return false
      end
      if not command.run_argv({ "git", "-C", directory, "init", "--quiet" }) then
        return false
      end
      if not command.run_argv({ "git", "-C", directory, "remote", "add", "origin", repo }) then
        return false
      end
      if not command.run_argv({
        "git", "-C", directory, "fetch", "--quiet", "--depth", "1", "origin", rev,
      }) then
        return false
      end
      return command.run_argv({
        "git", "-C", directory, "checkout", "--quiet", "--detach", "FETCH_HEAD",
      })
    end,
    rescan_plugins = function()
      return command.run_argv({ "omarchy-shell", "shell", "rescanPlugins" })
    end,
    enable_plugin = function(id, section)
      local args = { "omarchy", "plugin", "enable", id }
      if section then
        args[#args + 1] = "--section"
        args[#args + 1] = section
      end
      return command.run_argv(args)
    end,
    disable_plugin = function(id)
      return command.run_argv({ "omarchy", "plugin", "disable", id })
    end,
  }
end

local function owned_link(runtime, target, source)
  return runtime.is_symlink(target) and runtime.readlink(target) == source
end

local function replace_source(runtime, plugin, source)
  local staging = source .. ".staging"
  local previous = source .. ".previous"

  runtime.remove_tree(staging)
  runtime.remove_tree(previous)

  if not runtime.clone_pinned(plugin.repo, plugin.rev, staging) then
    runtime.remove_tree(staging)
    return nil, "failed to fetch pinned commit"
  end

  if runtime.current_revision(staging) ~= plugin.rev then
    runtime.remove_tree(staging)
    return nil, "fetched revision does not match pinned commit"
  end

  if runtime.manifest_id(staging) ~= plugin.id then
    runtime.remove_tree(staging)
    return nil, "upstream manifest id does not match configured plugin id"
  end

  local had_source = runtime.exists(source)
  if had_source and not runtime.move(source, previous) then
    runtime.remove_tree(staging)
    return nil, "failed to stage previous managed plugin source"
  end

  if not runtime.move(staging, source) then
    if had_source then
      runtime.move(previous, source)
    end
    runtime.remove_tree(staging)
    return nil, "failed to activate pinned plugin source"
  end

  if had_source then
    runtime.remove_tree(previous)
  end
  return true
end

local function sync_plugin(runtime, plugin, store_root, plugin_root)
  local source = paths.join(store_root, plugin.id)
  local target = paths.join(plugin_root, plugin.id)
  local result = {
    id = plugin.id,
    name = plugin.name or plugin.id,
    ok = false,
    changed = false,
    source = source,
    target = target,
  }

  if runtime.exists(target) and not owned_link(runtime, target, source) then
    result.error = "plugin target is already owned by the user or another manager"
    return result
  end

  local source_valid = runtime.exists(source)
    and runtime.current_revision(source) == plugin.rev
    and runtime.manifest_id(source) == plugin.id

  if not source_valid then
    local replaced, err = replace_source(runtime, plugin, source)
    if not replaced then
      result.error = err
      return result
    end
    result.changed = true
  end

  if not runtime.exists(target) then
    if not runtime.symlink(source, target) then
      result.error = "failed to expose managed plugin to Omarchy"
      return result
    end
    result.changed = true
  end

  result.ok = true
  result.enabled = plugin.enabled ~= false
  result.section = plugin.section
  return result
end

function M.sync(options)
  options = options or {}
  local home = assert(options.home, "home is required")
  local manifest = assert(options.manifest, "manifest is required")
  local runtime = options.runtime or default_runtime()

  local valid, validation_error = M.validate_manifest(manifest)
  if not valid then
    return {
      ok = false,
      changed = false,
      error = validation_error,
      results = {},
    }
  end

  if not runtime.available() then
    return {
      ok = true,
      changed = false,
      skipped = true,
      reason = "Omarchy is not available",
      results = {},
    }
  end

  if not runtime.git_available() then
    return {
      ok = false,
      changed = false,
      error = "git is required to sync external Omarchy plugins",
      results = {},
    }
  end

  local store_root = paths.join(
    home,
    ".local",
    "share",
    "hyprland_config",
    "external-plugins"
  )
  local plugin_root = paths.join(home, ".config", "omarchy", "plugins")

  if not runtime.mkdir_p(store_root) or not runtime.mkdir_p(plugin_root) then
    return {
      ok = false,
      changed = false,
      error = "failed to create external plugin directories",
      results = {},
    }
  end

  local results = {}
  local overall = true
  local changed = false
  local ready = {}

  for _, plugin in ipairs(manifest) do
    local result = sync_plugin(runtime, plugin, store_root, plugin_root)
    results[#results + 1] = result
    if result.ok then
      ready[#ready + 1] = {
        plugin = plugin,
        result = result,
      }
      if result.changed then
        changed = true
      end
    else
      overall = false
    end
  end

  if #ready > 0 then
    if not runtime.rescan_plugins() then
      overall = false
      for _, item in ipairs(ready) do
        item.result.ok = false
        item.result.error = "Omarchy plugin rescan failed"
      end
    else
      for _, item in ipairs(ready) do
        local plugin = item.plugin
        local action_ok
        if plugin.enabled == false then
          action_ok = runtime.disable_plugin(plugin.id)
        else
          action_ok = runtime.enable_plugin(plugin.id, plugin.section)
        end

        if not action_ok then
          overall = false
          item.result.ok = false
          item.result.error = plugin.enabled == false
            and "failed to disable plugin"
            or "failed to enable plugin"
        end
      end
    end
  end

  return {
    ok = overall,
    changed = changed,
    results = results,
  }
end

function M.remove(options)
  options = options or {}
  local home = assert(options.home, "home is required")
  local manifest = assert(options.manifest, "manifest is required")
  local runtime = options.runtime or default_runtime()

  local valid, validation_error = M.validate_manifest(manifest)
  if not valid then
    return {
      ok = false,
      changed = false,
      error = validation_error,
      results = {},
    }
  end

  local store_root = paths.join(
    home,
    ".local",
    "share",
    "hyprland_config",
    "external-plugins"
  )
  local plugin_root = paths.join(home, ".config", "omarchy", "plugins")
  local results = {}
  local overall = true
  local changed = false
  local omarchy_available = runtime.available()

  for _, plugin in ipairs(manifest) do
    local source = paths.join(store_root, plugin.id)
    local target = paths.join(plugin_root, plugin.id)
    local result = {
      id = plugin.id,
      name = plugin.name or plugin.id,
      ok = true,
      changed = false,
    }

    if runtime.exists(target) then
      if not owned_link(runtime, target, source) then
        result.ok = false
        result.error = "plugin target is not owned by Hyprland_Config"
        overall = false
      else
        if omarchy_available then
          runtime.disable_plugin(plugin.id)
        end
        if not runtime.remove(target) then
          result.ok = false
          result.error = "failed to remove managed plugin link"
          overall = false
        else
          result.changed = true
          changed = true
        end
      end
    end

    if result.ok and runtime.exists(source) then
      if not runtime.remove_tree(source) then
        result.ok = false
        result.error = "failed to remove managed plugin source"
        overall = false
      else
        result.changed = true
        changed = true
      end
    end

    runtime.remove_tree(source .. ".staging")
    runtime.remove_tree(source .. ".previous")
    results[#results + 1] = result
  end

  if omarchy_available and changed and not runtime.rescan_plugins() then
    overall = false
    return {
      ok = false,
      changed = changed,
      error = "Omarchy plugin rescan failed after removal",
      results = results,
    }
  end

  return {
    ok = overall,
    changed = changed,
    results = results,
  }
end

return M

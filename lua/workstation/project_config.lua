local command = require("workstation.command")
local paths = require("workstation.paths")
local project_model = require("workstation.project_model")

local M = {}

local function clone_defaults(home)
  return {
    roots = { paths.join(home, "Repository") },
    projects = {},
    hidden = {},
    apps = {
      terminal = "auto",
    },
    overrides = {},
    max_depth = 4,
  }
end

function M.defaults(home)
  return clone_defaults(assert(home, "home is required"))
end

local function is_dense_array(value, item_check)
  if type(value) ~= "table" then
    return false
  end

  local count = 0
  local max = 0
  for key, item in pairs(value) do
    if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
      return false
    end
    if not item_check(item) then
      return false
    end
    count = count + 1
    if key > max then
      max = key
    end
  end

  return count == max
end

local function string_array(value)
  return is_dense_array(value, function(item)
    return type(item) == "string" and item ~= ""
  end)
end

local function expand(path, home)
  return project_model.expand_path(path, home)
end

local function validate(raw, home)
  if type(raw) ~= "table" then
    return nil, "project config must return a table"
  end

  local config = clone_defaults(home)

  if raw.roots ~= nil then
    if not string_array(raw.roots) then
      return nil, "roots must be an array of non-empty strings"
    end
    if #raw.roots > 0 then
      config.roots = {}
      for index, root in ipairs(raw.roots) do
        config.roots[index] = expand(root, home)
      end
    end
  end

  if raw.projects ~= nil then
    if not is_dense_array(raw.projects, function(item)
      return type(item) == "table"
        and type(item.path) == "string"
        and item.path ~= ""
        and (item.name == nil or type(item.name) == "string")
    end) then
      return nil, "projects must be an array of { path, name? } tables"
    end

    config.projects = {}
    for index, project in ipairs(raw.projects) do
      config.projects[index] = {
        path = expand(project.path, home),
        name = project.name,
      }
    end
  end

  if raw.hidden ~= nil then
    if not string_array(raw.hidden) then
      return nil, "hidden must be an array of non-empty strings"
    end
    config.hidden = {}
    for index, hidden in ipairs(raw.hidden) do
      config.hidden[index] = expand(hidden, home)
    end
  end

  if raw.apps ~= nil then
    if type(raw.apps) ~= "table" then
      return nil, "apps must be a table"
    end
    if raw.apps.terminal ~= nil and type(raw.apps.terminal) ~= "string" then
      return nil, "apps.terminal must be a string"
    end
    if raw.apps.editor ~= nil and not string_array(raw.apps.editor) then
      return nil, "apps.editor must be an argv array"
    end
    if raw.apps.file_manager ~= nil and not string_array(raw.apps.file_manager) then
      return nil, "apps.file_manager must be an argv array"
    end

    config.apps = {
      terminal = raw.apps.terminal or "auto",
      editor = raw.apps.editor,
      file_manager = raw.apps.file_manager,
    }
  end

  if raw.max_depth ~= nil then
    if type(raw.max_depth) ~= "number"
      or raw.max_depth % 1 ~= 0
      or raw.max_depth < 1 then
      return nil, "max_depth must be a positive integer"
    end
    config.max_depth = raw.max_depth
  end

  if raw.overrides ~= nil then
    if type(raw.overrides) ~= "table" then
      return nil, "overrides must be a table"
    end

    config.overrides = {}
    for key, value in pairs(raw.overrides) do
      if type(key) ~= "string" or key == "" or type(value) ~= "table" then
        return nil, "override keys must be paths and values must be tables"
      end
      if value.actions ~= nil and type(value.actions) ~= "table" then
        return nil, "override actions must be a table"
      end
      config.overrides[expand(key, home)] = value
    end
  end

  return config
end

local function default_runtime()
  return {
    exists = command.exists,
    load_config = function(path)
      local ok, value = pcall(dofile, path)
      if not ok then
        return nil, tostring(value)
      end
      return value
    end,
  }
end

function M.load(options)
  options = options or {}
  local home = assert(options.home or os.getenv("HOME"), "home is required")
  local config_path = options.config_path
    or paths.join(home, ".config", "hyprland-workstation", "projects.lua")
  local runtime = options.runtime or default_runtime()

  if not runtime.exists(config_path) then
    return clone_defaults(home), nil
  end

  local raw, load_error = runtime.load_config(config_path)
  if raw == nil then
    return clone_defaults(home), load_error or "failed to load project config"
  end

  local config, validation_error = validate(raw, home)
  if not config then
    return clone_defaults(home), validation_error
  end
  return config, nil
end

return M

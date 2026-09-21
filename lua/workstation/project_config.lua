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
    monitors = {},
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

local function contains_nul(value)
  return type(value) == "string" and value:find(string.char(0), 1, true) ~= nil
end

local function safe_string(value)
  return type(value) == "string" and value ~= "" and not contains_nul(value)
end

local function safe_string_array(value)
  return is_dense_array(value, function(item)
    return safe_string(item)
  end)
end

local function valid_workspace_selector(value)
  if type(value) == "number" then
    return value % 1 == 0 and value >= 1 and value <= 2147483647
  end
  return safe_string(value)
end

local function validate_workspace_target(target)
  if type(target) ~= "table" then
    return nil, "workspace targets must be tables"
  end
  if not safe_string(target.name) then
    return nil, "workspace target name must be a non-empty string"
  end
  if target.workspace ~= nil and not valid_workspace_selector(target.workspace) then
    return nil, "workspace target workspace must be a positive id or non-empty selector"
  end
  if target.monitor ~= nil and not safe_string(target.monitor) then
    return nil, "workspace target monitor must be a non-empty string"
  end
  if target.terminal ~= nil and type(target.terminal) ~= "boolean" then
    return nil, "workspace target terminal must be boolean"
  end
  if target.shell ~= nil then
    return nil, "workspace targets do not support shell execution"
  end
  if target.singleton ~= nil and type(target.singleton) ~= "boolean" then
    return nil, "workspace target singleton must be boolean"
  end
  if target.wait_ms ~= nil then
    if type(target.wait_ms) ~= "number"
      or target.wait_ms % 1 ~= 0
      or target.wait_ms < 0
      or target.wait_ms > 5000 then
      return nil, "workspace target wait_ms must be an integer between 0 and 5000"
    end
  end

  if target.match ~= nil then
    if type(target.match) ~= "table" then
      return nil, "workspace target match must be a table"
    end

    local match_fields = {
      "class",
      "initial_class",
      "title",
      "initial_title",
    }
    local matched = 0
    for _, field in ipairs(match_fields) do
      local value = target.match[field]
      if value ~= nil then
        if not safe_string(value) then
          return nil, "workspace target match fields must be non-empty strings"
        end
        matched = matched + 1
      end
    end

    if matched == 0 then
      return nil, "workspace target match requires at least one selector"
    end
  elseif target.singleton == true or target.wait_ms ~= nil then
    return nil, "workspace target singleton/wait_ms requires match selectors"
  end

  local has_argv = target.argv ~= nil
  local has_url = target.url ~= nil
  local is_editor = target.operation == "editor"
  local is_url = target.operation == "url" or has_url

  if target.operation ~= nil
    and target.operation ~= "editor"
    and target.operation ~= "url" then
    return nil, "unsupported workspace target operation"
  end

  if is_editor then
    if has_argv or has_url or target.terminal == true then
      return nil, "editor workspace target cannot define argv, url, or terminal"
    end
    return true
  end

  if is_url then
    if not safe_string(target.url) then
      return nil, "URL workspace target requires a non-empty url"
    end
    if has_argv or target.terminal == true then
      return nil, "URL workspace target cannot define argv or terminal"
    end
    return true
  end

  if not has_argv or not safe_string_array(target.argv) or #target.argv == 0 then
    return nil, "workspace target requires a non-empty argv array"
  end

  return true
end

local function validate_workspace(workspace)
  if type(workspace) ~= "table" then
    return nil, "workspace override must be a table"
  end
  if not is_dense_array(workspace.targets, function(item)
    return type(item) == "table"
  end) or #workspace.targets == 0 then
    return nil, "workspace.targets must be a non-empty array"
  end

  for _, target in ipairs(workspace.targets) do
    local ok, err = validate_workspace_target(target)
    if not ok then
      return nil, err
    end
  end

  return true
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

  if raw.monitors ~= nil then
    if type(raw.monitors) ~= "table" then
      return nil, "monitors must be a role-to-monitor table"
    end

    config.monitors = {}
    for role, monitor in pairs(raw.monitors) do
      if not safe_string(role) or not safe_string(monitor) then
        return nil, "monitor aliases must use non-empty string roles and monitor names"
      end
      config.monitors[role] = monitor
    end
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
      if value.workspace ~= nil then
        local workspace_ok, workspace_error = validate_workspace(value.workspace)
        if not workspace_ok then
          return nil, workspace_error
        end
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

local command = require("workstation.command")

local M = {}

local MAX_WORKSPACE_ID = 2147483647

local function copy_argv(argv)
  local result = {}
  for index, value in ipairs(argv or {}) do
    result[index] = value
  end
  return result
end

local function failure(message)
  return {
    ok = false,
    started = 0,
    skipped = 0,
    failed = 1,
    error = tostring(message or "workspace orchestration failed"),
    results = {},
  }
end

local function project_override(project, config)
  local overrides = config and config.overrides or {}
  return overrides[project.path] or overrides[project.id]
end

local function normalize_workspace(value)
  if type(value) == "number" then
    if value % 1 ~= 0 or value < 1 or value > MAX_WORKSPACE_ID then
      return nil, "workspace id must be an integer between 1 and " .. tostring(MAX_WORKSPACE_ID)
    end
    return tostring(value)
  end

  if type(value) == "string" and value ~= "" and not value:find(string.char(0), 1, true) then
    return value
  end

  return nil, "workspace must be a positive id or non-empty selector"
end

local function normalize_monitor(value)
  if value == nil then
    return nil
  end
  if type(value) ~= "string" or value == "" or value:find(string.char(0), 1, true) then
    return nil, "monitor must be a non-empty string"
  end
  return value
end

local function target_argv(project, target, adapter)
  if target.operation == "editor" then
    if type(adapter.editor_argv) ~= "function" then
      return nil, "editor adapter is unavailable"
    end
    return adapter.editor_argv(project.path)
  end

  if target.url ~= nil then
    if type(adapter.url_argv) ~= "function" then
      return nil, "URL opener is unavailable"
    end
    return adapter.url_argv(target.url)
  end

  if type(target.argv) ~= "table" or #target.argv == 0 then
    return nil, "workspace target has no executable"
  end

  if target.terminal == true then
    if type(adapter.terminal_argv) ~= "function" then
      return nil, "terminal adapter is unavailable"
    end
    return adapter.terminal_argv(project.path, target.argv)
  end

  return copy_argv(target.argv)
end

local function normalize_target(project, target, adapter, index)
  if type(target) ~= "table" then
    return {
      name = "target-" .. tostring(index),
      enabled = false,
      reason = "workspace target must be a table",
    }
  end

  local name = target.name
  if type(name) ~= "string" or name == "" or name:find(string.char(0), 1, true) then
    return {
      name = "target-" .. tostring(index),
      enabled = false,
      reason = "workspace target name must be a non-empty string",
    }
  end

  local normalized = {
    name = name,
    enabled = true,
  }

  if target.workspace ~= nil then
    local workspace, workspace_error = normalize_workspace(target.workspace)
    if not workspace then
      normalized.enabled = false
      normalized.reason = workspace_error
      return normalized
    end
    normalized.workspace = workspace
  end

  local monitor, monitor_error = normalize_monitor(target.monitor)
  if monitor_error then
    normalized.enabled = false
    normalized.reason = monitor_error
    return normalized
  end
  normalized.monitor = monitor

  local argv, argv_error = target_argv(project, target, adapter)
  if not argv then
    normalized.enabled = false
    normalized.reason = argv_error or "workspace target is unavailable"
    return normalized
  end

  normalized.argv = copy_argv(argv)
  return normalized
end

function M.plan(project, config, adapter)
  if type(project) ~= "table"
    or type(project.id) ~= "string"
    or type(project.path) ~= "string" then
    return nil, "invalid project"
  end
  if type(adapter) ~= "table" then
    return nil, "launcher adapter is unavailable"
  end

  local override = project_override(project, config or {})
  local workspace = override and override.workspace
  local targets = workspace and workspace.targets

  if type(targets) ~= "table" or #targets == 0 then
    return nil, "workspace is not configured for project"
  end

  local plan = {
    project_id = project.id,
    project_path = project.path,
    targets = {},
  }

  for index, target in ipairs(targets) do
    plan.targets[index] = normalize_target(project, target, adapter, index)
  end

  return plan
end

local function lua_quote(value)
  return string.format("%q", tostring(value))
end

local function hyprland_exec_argv(argv, workspace, monitor)
  local effects = {}

  if workspace then
    effects[#effects + 1] = "workspace = " .. lua_quote(workspace .. " silent")
  end
  if monitor then
    effects[#effects + 1] = "monitor = " .. lua_quote(monitor .. " silent")
  end

  local expression = "hl.dsp.exec_cmd("
    .. lua_quote(command.argv(argv))
    .. ", { "
    .. table.concat(effects, ", ")
    .. " })"

  return { "hyprctl", "dispatch", expression }
end

M.hyprland_exec_argv = hyprland_exec_argv

local function default_runtime()
  return {
    realpath = command.realpath,
    command_exists = command.command_exists,
    spawn_argv = command.spawn_argv,
    run_argv = command.run_argv,
  }
end

local function resolve_project(project, runtime)
  local canonical = runtime.realpath(project.path)
  if not canonical then
    return nil, "project path no longer exists"
  end
  if canonical ~= project.id then
    return nil, "project identity changed since discovery"
  end
  return canonical
end

local function execute_target(target, runtime)
  if target.enabled == false then
    return {
      target = target.name,
      status = "failed",
      error = target.reason or "workspace target is unavailable",
    }
  end

  if target.workspace or target.monitor then
    if not runtime.command_exists("hyprctl") then
      return {
        target = target.name,
        status = "failed",
        error = "hyprctl is unavailable for workspace placement",
      }
    end

    if not runtime.run_argv(hyprland_exec_argv(target.argv, target.workspace, target.monitor)) then
      return {
        target = target.name,
        status = "failed",
        error = "Hyprland failed to dispatch workspace target",
      }
    end

    return {
      target = target.name,
      status = "started",
      workspace = target.workspace,
      monitor = target.monitor,
    }
  end

  if not runtime.spawn_argv(target.argv) then
    return {
      target = target.name,
      status = "failed",
      error = "failed to dispatch workspace target",
    }
  end

  return {
    target = target.name,
    status = "started",
  }
end

function M.execute(plan, runtime)
  if type(plan) ~= "table" or type(plan.targets) ~= "table" then
    return failure("invalid workspace plan")
  end

  runtime = runtime or default_runtime()

  local summary = {
    ok = true,
    started = 0,
    skipped = 0,
    failed = 0,
    results = {},
  }

  for _, target in ipairs(plan.targets) do
    local result = execute_target(target, runtime)
    summary.results[#summary.results + 1] = result

    if result.status == "started" then
      summary.started = summary.started + 1
    elseif result.status == "skipped" then
      summary.skipped = summary.skipped + 1
    else
      summary.failed = summary.failed + 1
      summary.ok = false
    end
  end

  if summary.started == 0 and summary.failed == 0 then
    summary.ok = false
    summary.error = "workspace plan did not contain executable targets"
  end

  return summary
end

function M.run(project, config, adapter, runtime)
  runtime = runtime or default_runtime()

  local _, project_error = resolve_project(project, runtime)
  if project_error then
    return failure(project_error)
  end

  local plan, plan_error = M.plan(project, config, adapter)
  if not plan then
    return failure(plan_error)
  end

  return M.execute(plan, runtime)
end

return M

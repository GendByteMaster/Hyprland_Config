local command = require("workstation.command")
local hyprland_state = require("workstation.hyprland_state")

local M = {}

local MAX_WORKSPACE_ID = 2147483647
local DEFAULT_WAIT_MS = 1200
local POLL_MS = 50

local LOGICAL_MONITOR_INDEX = {
  primary = 1,
  secondary = 2,
  tertiary = 3,
}

local function copy_argv(argv)
  local result = {}
  for index, value in ipairs(argv or {}) do
    result[index] = value
  end
  return result
end

local function copy_map(value)
  local result = {}
  for key, item in pairs(value or {}) do
    result[key] = item
  end
  return result
end

local function failure(message)
  return {
    ok = false,
    started = 0,
    skipped = 0,
    failed = 1,
    degraded = 0,
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

local function copy_match(match)
  if type(match) ~= "table" then
    return nil
  end

  local result = {}
  for _, key in ipairs({ "class", "initial_class", "title", "initial_title" }) do
    if match[key] ~= nil then
      result[key] = match[key]
    end
  end
  return result
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
    singleton = target.singleton == true,
    match = copy_match(target.match),
    wait_ms = target.wait_ms == nil and DEFAULT_WAIT_MS or target.wait_ms,
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
    monitor_aliases = copy_map(config and config.monitors or {}),
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

local function sleep_ms(milliseconds)
  if milliseconds <= 0 then
    return true
  end
  return command.run_argv({ "sleep", string.format("%.3f", milliseconds / 1000) })
end

local function default_runtime()
  return {
    realpath = command.realpath,
    command_exists = command.command_exists,
    spawn_argv = command.spawn_argv,
    run_argv = command.run_argv,
    clients = hyprland_state.clients,
    monitors = hyprland_state.monitors,
    find_match = hyprland_state.find_match,
    address_set = hyprland_state.address_set,
    place_client = hyprland_state.place_client,
    sleep_ms = sleep_ms,
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

local function ordered_monitors(monitors)
  local result = {}
  for index, monitor in ipairs(monitors or {}) do
    result[index] = monitor
  end

  table.sort(result, function(left, right)
    if left.focused ~= right.focused then
      return left.focused == true
    end
    if (left.x or 0) ~= (right.x or 0) then
      return (left.x or 0) < (right.x or 0)
    end
    if (left.y or 0) ~= (right.y or 0) then
      return (left.y or 0) < (right.y or 0)
    end
    return tostring(left.name or "") < tostring(right.name or "")
  end)

  return result
end

local function monitor_by_name(monitors, name)
  for _, monitor in ipairs(monitors or {}) do
    if monitor.name == name then
      return monitor
    end
  end
  return nil
end

function M.resolve_monitor(requested, aliases, monitors)
  if requested == nil then
    return nil, false, nil
  end

  aliases = aliases or {}
  local aliased = aliases[requested]
  local desired = aliased or requested

  if type(monitors) ~= "table" or #monitors == 0 then
    if aliased then
      return aliased, false, nil
    end
    if LOGICAL_MONITOR_INDEX[requested] then
      return nil, true, "logical monitor role cannot be resolved without monitor state"
    end
    return requested, false, nil
  end

  if monitor_by_name(monitors, desired) then
    return desired, false, nil
  end

  local role_index = aliased and nil or LOGICAL_MONITOR_INDEX[requested]
  local ordered = ordered_monitors(monitors)
  if role_index and ordered[role_index] then
    return ordered[role_index].name, false, nil
  end

  if ordered[1] then
    return ordered[1].name, true,
      "requested monitor " .. tostring(desired) .. " is unavailable; using " .. tostring(ordered[1].name)
  end

  return nil, true, "no Hyprland monitors are available"
end

local function monitor_id(monitors, name)
  local monitor = monitor_by_name(monitors, name)
  return monitor and monitor.id or nil
end

local function workspace_matches(client, selector)
  if selector == nil then
    return true
  end

  local numeric = tonumber(selector)
  if numeric and tostring(math.floor(numeric)) == tostring(selector) then
    return tonumber(client.workspace_id) == numeric
  end

  if selector:sub(1, 5) == "name:" then
    return tostring(client.workspace_name or "") == selector:sub(6)
  end

  return true
end

local function monitor_matches(client, name, monitors)
  if name == nil then
    return true
  end

  local expected_id = monitor_id(monitors, name)
  if expected_id == nil then
    return true
  end

  return tonumber(client.monitor_id) == tonumber(expected_id)
end

local function await_new_match(target, before, runtime)
  if type(target.match) ~= "table" then
    return nil, nil
  end

  local wait_ms = math.max(0, math.min(5000, tonumber(target.wait_ms) or DEFAULT_WAIT_MS))
  local attempts = math.max(1, math.floor(wait_ms / POLL_MS) + 1)
  local last_error

  for attempt = 1, attempts do
    local clients, clients_error = runtime.clients()
    if clients then
      local matched = runtime.find_match(clients, target.match, before)
      if matched then
        return matched, nil
      end
    else
      last_error = clients_error
    end

    if attempt < attempts and wait_ms > 0 then
      runtime.sleep_ms(POLL_MS)
    end
  end

  return nil, last_error or ("matching window did not appear within " .. tostring(wait_ms) .. "ms")
end

local function result_started(target, extra)
  local result = {
    target = target.name,
    status = "started",
    workspace = target.workspace,
    monitor = target.monitor,
  }
  for key, value in pairs(extra or {}) do
    result[key] = value
  end
  return result
end

local function execute_target(target, plan, runtime)
  if target.enabled == false then
    return {
      target = target.name,
      status = "failed",
      error = target.reason or "workspace target is unavailable",
    }
  end

  local monitors
  local monitor_error
  if target.monitor ~= nil then
    monitors, monitor_error = runtime.monitors()
  end

  local resolved_monitor, monitor_degraded, monitor_reason = M.resolve_monitor(
    target.monitor,
    plan.monitor_aliases,
    monitors
  )

  if target.monitor ~= nil and not resolved_monitor then
    return {
      target = target.name,
      status = "failed",
      error = monitor_reason or monitor_error or "target monitor cannot be resolved",
    }
  end

  local before_clients = {}
  local before_set = {}
  if type(target.match) == "table" then
    local clients, clients_error = runtime.clients()
    if not clients then
      if target.singleton then
        return {
          target = target.name,
          status = "failed",
          error = clients_error or "cannot inspect Hyprland clients for singleton target",
        }
      end
      before_clients = {}
    else
      before_clients = clients
      before_set = runtime.address_set(clients)

      if target.singleton then
        local existing = runtime.find_match(clients, target.match, {})
        if existing then
          return {
            target = target.name,
            status = "skipped",
            reason = "already running",
            address = existing.address,
          }
        end
      end
    end
  end

  local placed = target.workspace ~= nil or resolved_monitor ~= nil

  if placed then
    if not runtime.command_exists("hyprctl") then
      return {
        target = target.name,
        status = "failed",
        error = "hyprctl is unavailable for workspace placement",
      }
    end

    if not runtime.run_argv(hyprland_exec_argv(target.argv, target.workspace, resolved_monitor)) then
      return {
        target = target.name,
        status = "failed",
        error = "Hyprland failed to dispatch workspace target",
      }
    end
  elseif not runtime.spawn_argv(target.argv) then
    return {
      target = target.name,
      status = "failed",
      error = "failed to dispatch workspace target",
    }
  end

  local started = result_started(target, {
    monitor = resolved_monitor,
    requested_monitor = target.monitor,
  })

  if monitor_degraded then
    started.degraded = true
    started.warning = monitor_reason
  end

  if type(target.match) ~= "table" then
    return started
  end

  local matched, match_error = await_new_match(target, before_set, runtime)
  if not matched then
    started.degraded = true
    started.warning = match_error
    return started
  end

  started.address = matched.address

  local workspace_ok = workspace_matches(matched, target.workspace)
  local monitor_ok = monitor_matches(matched, resolved_monitor, monitors)

  if workspace_ok and monitor_ok then
    return started
  end

  if target.workspace ~= nil and resolved_monitor ~= nil then
    started.degraded = true
    started.warning = "combined workspace+monitor placement could not be verified safely"
    return started
  end

  local corrected, correction_error = runtime.place_client(
    matched.address,
    workspace_ok and nil or target.workspace,
    monitor_ok and nil or resolved_monitor
  )

  if not corrected then
    started.degraded = true
    started.warning = correction_error or "post-launch placement correction failed"
    return started
  end

  started.corrected = true
  return started
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
    degraded = 0,
    results = {},
  }

  for _, target in ipairs(plan.targets) do
    local result = execute_target(target, plan, runtime)
    summary.results[#summary.results + 1] = result

    if result.status == "started" then
      summary.started = summary.started + 1
      if result.degraded == true then
        summary.degraded = summary.degraded + 1
        summary.ok = false
      end
    elseif result.status == "skipped" then
      summary.skipped = summary.skipped + 1
    else
      summary.failed = summary.failed + 1
      summary.ok = false
    end
  end

  if summary.started == 0 and summary.skipped == 0 and summary.failed == 0 then
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

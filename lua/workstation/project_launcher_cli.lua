local protocol = require("workstation.launcher_protocol")

local M = {}

local function append_warning(warnings, value)
  if type(value) == "string" and value ~= "" then
    warnings[#warnings + 1] = value
  end
end

local function append_warnings(warnings, values)
  for _, value in ipairs(values or {}) do
    append_warning(warnings, value)
  end
end

local function find_project(projects, project_id)
  for _, project in ipairs(projects or {}) do
    if project.id == project_id then
      return project
    end
  end
end

local function find_action(actions, action_id)
  for _, action in ipairs(actions or {}) do
    if action.id == action_id then
      return action
    end
  end
end

local function load_state(ctx, warnings)
  local state, warning = ctx.load_state()
  if not state then
    return nil, warning or "failed to load launcher state"
  end
  append_warning(warnings, warning)
  return state
end

local function discover_projects(ctx, warnings)
  local config, config_warning = ctx.load_config()
  if not config then
    return nil, config_warning or "failed to load project config"
  end
  append_warning(warnings, config_warning)

  local result = ctx.discover(config)
  if type(result) ~= "table" or type(result.projects) ~= "table" then
    return nil, "project discovery returned invalid data"
  end
  append_warnings(warnings, result.warnings)

  local ok, cache_error = ctx.cache_write(result.projects)
  if not ok then
    return nil, cache_error or "failed to write project cache"
  end
  return result.projects
end

local function cached_or_discover(ctx, warnings)
  local projects, cache_warning = ctx.cache_read()
  if projects then
    append_warning(warnings, cache_warning)
    return projects
  end

  append_warning(warnings, cache_warning)
  return discover_projects(ctx, warnings)
end

local function refresh(ctx)
  local warnings = {}
  local projects, discovery_error = discover_projects(ctx, warnings)
  if not projects then
    return protocol.failure(discovery_error)
  end

  local state, state_error = load_state(ctx, warnings)
  if not state then
    return protocol.failure(state_error)
  end

  return protocol.success({
    projects = protocol.list(ctx.rank(projects, "", state)),
    warnings = protocol.list(warnings),
  })
end

local function query(ctx, text)
  local warnings = {}
  local projects, cache_error = cached_or_discover(ctx, warnings)
  if not projects then
    return protocol.failure(cache_error)
  end

  local state, state_error = load_state(ctx, warnings)
  if not state then
    return protocol.failure(state_error)
  end

  return protocol.success({
    projects = protocol.list(ctx.rank(projects, text or "", state)),
    warnings = protocol.list(warnings),
  })
end

local function actions(ctx, project_id)
  local warnings = {}
  local projects, cache_error = cached_or_discover(ctx, warnings)
  if not projects then
    return protocol.failure(cache_error)
  end

  local project = find_project(projects, project_id)
  if not project then
    return protocol.failure("project is not present in launcher cache")
  end

  local state, state_error = load_state(ctx, warnings)
  if not state then
    return protocol.failure(state_error)
  end

  local resolved, resolve_error = ctx.resolve_actions(project, state)
  if not resolved then
    return protocol.failure(resolve_error or "failed to resolve project actions")
  end

  return protocol.success({
    project = project,
    actions = protocol.list(resolved),
    warnings = protocol.list(warnings),
  })
end

local function browse(ctx, path)
  if type(ctx.browse_directory) ~= "function" then
    return protocol.failure("folder browser is unavailable")
  end

  local result, browse_error = ctx.browse_directory(path)
  if not result then
    return protocol.failure(browse_error or "failed to browse folder")
  end

  return protocol.success({
    path = result.path,
    parent = result.parent,
    entries = protocol.list(result.entries or {}),
  })
end

local function add_root(ctx, path)
  if type(path) ~= "string" or path == "" then
    return protocol.failure("usage: add-root <path>")
  end
  if type(ctx.add_root) ~= "function" then
    return protocol.failure("project root selection is unavailable")
  end

  local root, add_error = ctx.add_root(path)
  if not root then
    return protocol.failure(add_error or "failed to add project root")
  end

  local warnings = {}
  local projects, discovery_error = discover_projects(ctx, warnings)
  if not projects then
    return protocol.failure(discovery_error)
  end

  local state, state_error = load_state(ctx, warnings)
  if not state then
    return protocol.failure(state_error)
  end

  return protocol.success({
    root = root,
    roots = protocol.list(state.roots or {}),
    projects = protocol.list(ctx.rank(projects, "", state)),
    warnings = protocol.list(warnings),
  })
end

local function toggle_favorite(ctx, project_id)
  local warnings = {}
  local projects, cache_error = cached_or_discover(ctx, warnings)
  if not projects then
    return protocol.failure(cache_error)
  end
  if not find_project(projects, project_id) then
    return protocol.failure("project is not present in launcher cache")
  end

  local state, state_error = load_state(ctx, warnings)
  if not state then
    return protocol.failure(state_error)
  end

  local favorite = ctx.toggle_favorite(state, project_id)
  local ok, save_error = ctx.save_state(state)
  if not ok then
    return protocol.failure(save_error or "failed to save favorite state")
  end

  return protocol.success({
    favorite = favorite,
    warnings = protocol.list(warnings),
  })
end

local function run_action(ctx, args)
  local project_id = args[2]
  local action_id = args[3]
  if type(project_id) ~= "string" or project_id == ""
    or type(action_id) ~= "string" or action_id == "" then
    return protocol.failure("usage: run <project_id> <action_id> [--confirmed]")
  end

  local confirmed = false
  for index = 4, #args do
    if args[index] == "--confirmed" then
      confirmed = true
    else
      return protocol.failure("unknown run option: " .. tostring(args[index]))
    end
  end

  local warnings = {}
  local projects, cache_error = cached_or_discover(ctx, warnings)
  if not projects then
    return protocol.failure(cache_error)
  end

  local project = find_project(projects, project_id)
  if not project then
    return protocol.failure("project is not present in launcher cache")
  end

  local state, state_error = load_state(ctx, warnings)
  if not state then
    return protocol.failure(state_error)
  end

  local resolved, resolve_error = ctx.resolve_actions(project, state)
  if not resolved then
    return protocol.failure(resolve_error or "failed to resolve project actions")
  end

  local selected = find_action(resolved, action_id)
  if not selected then
    return protocol.failure("action is not available for project")
  end

  if selected.operation == "favorite" or selected.id == "favorite" then
    local favorite = ctx.toggle_favorite(state, project.id)
    local ok, save_error = ctx.save_state(state)
    if not ok then
      return protocol.failure(save_error or "failed to save favorite state")
    end
    return protocol.success({
      favorite = favorite,
      warnings = protocol.list(warnings),
    })
  end

  local execution = ctx.execute(project, selected, confirmed)
  if type(execution) ~= "table" then
    return protocol.failure("action executor returned invalid data")
  end
  if execution.requires_confirmation then
    return protocol.success({
      requires_confirmation = true,
      project = project,
      action = selected,
      warnings = protocol.list(warnings),
    })
  end
  if not execution.ok then
    return protocol.failure(execution.error or "action dispatch failed")
  end

  ctx.mark_recent(state, project.id, ctx.now())
  local ok, save_error = ctx.save_state(state)
  if not ok then
    return protocol.failure(save_error or "action launched but recent state could not be saved", {
      dispatched = true,
    })
  end

  return protocol.success({
    dispatched = true,
    warnings = protocol.list(warnings),
  })
end

function M.run(args, ctx)
  args = args or {}
  assert(type(ctx) == "table", "launcher context is required")

  local command = args[1]
  if command == "refresh" then
    return refresh(ctx)
  end
  if command == "query" then
    return query(ctx, args[2] or "")
  end
  if command == "actions" then
    if type(args[2]) ~= "string" or args[2] == "" then
      return protocol.failure("usage: actions <project_id>")
    end
    return actions(ctx, args[2])
  end
  if command == "favorite" then
    if type(args[2]) ~= "string" or args[2] == "" then
      return protocol.failure("usage: favorite <project_id>")
    end
    return toggle_favorite(ctx, args[2])
  end
  if command == "browse" then
    return browse(ctx, args[2])
  end
  if command == "add-root" then
    return add_root(ctx, args[2])
  end
  if command == "run" then
    return run_action(ctx, args)
  end
  if command == nil then
    return protocol.failure("usage: refresh | query <text> | actions <project_id> | favorite <project_id> | browse [path] | add-root <path> | run <project_id> <action_id> [--confirmed]")
  end
  return protocol.failure("unknown launcher command: " .. tostring(command))
end

return M

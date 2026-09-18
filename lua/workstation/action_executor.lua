local command = require("workstation.command")

local M = {}

local function default_runtime()
  return {
    realpath = command.realpath,
    spawn_argv = command.spawn_argv,
    run_argv_with_stdin = command.run_argv_with_stdin,
  }
end

local function failure(message)
  return {
    ok = false,
    error = message,
  }
end

local function spawn(runtime, argv)
  if type(argv) ~= "table" or #argv == 0 then
    return failure("action could not resolve an executable")
  end
  if not runtime.spawn_argv(argv) then
    return failure("failed to dispatch action")
  end
  return { ok = true }
end

local function resolve_project(project, runtime)
  if type(project) ~= "table"
    or type(project.id) ~= "string"
    or type(project.path) ~= "string" then
    return nil, "invalid project"
  end

  local canonical = runtime.realpath(project.path)
  if not canonical then
    return nil, "project path no longer exists"
  end
  if canonical ~= project.id then
    return nil, "project identity changed since discovery"
  end
  return canonical
end

function M.run(project, action, adapter, runtime, options)
  runtime = runtime or default_runtime()
  options = options or {}

  local cwd, project_error = resolve_project(project, runtime)
  if not cwd then
    return failure(project_error)
  end

  if type(action) ~= "table" or type(action.id) ~= "string" then
    return failure("invalid action")
  end
  if action.enabled == false then
    return failure(action.reason or "action is unavailable")
  end
  if action.confirm == true and options.confirmed ~= true then
    return {
      ok = false,
      requires_confirmation = true,
    }
  end
  if type(adapter) ~= "table" then
    return failure("launcher adapter is unavailable")
  end

  if action.operation == "favorite" then
    return failure("favorite state must be handled by the launcher state layer")
  end

  if action.operation == "editor" then
    local argv, reason = adapter.editor_argv(cwd)
    if not argv then
      return failure(reason or "editor is unavailable")
    end
    return spawn(runtime, argv)
  end

  if action.operation == "file-manager" then
    local argv, reason = adapter.file_manager_argv(cwd)
    if not argv then
      return failure(reason or "file manager is unavailable")
    end
    return spawn(runtime, argv)
  end

  if action.operation == "clipboard" then
    local argv, input, reason = adapter.clipboard_argv(cwd)
    if not argv then
      return failure(reason or "clipboard utility is unavailable")
    end
    if not runtime.run_argv_with_stdin(argv, input) then
      return failure("failed to copy project path")
    end
    return { ok = true }
  end

  if action.terminal == true or action.operation == "terminal" then
    local argv, reason = adapter.terminal_argv(cwd, action.argv or {})
    if not argv then
      return failure(reason or "terminal is unavailable")
    end
    return spawn(runtime, argv)
  end

  if type(action.argv) == "table" and #action.argv > 0 then
    return spawn(runtime, action.argv)
  end

  return failure("action has no executable operation")
end

return M

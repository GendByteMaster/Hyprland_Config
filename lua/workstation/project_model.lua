local command = require("workstation.command")

local M = {}

function M.expand_path(path, home)
  if type(path) ~= "string" or path == "" then
    return nil
  end

  home = home or os.getenv("HOME") or ""
  if path == "~" then
    return home
  end
  if path:sub(1, 2) == "~/" then
    return home .. path:sub(2)
  end
  return path
end

function M.normalize_path(path, home, runtime)
  local expanded = M.expand_path(path, home)
  if not expanded then
    return nil
  end

  runtime = runtime or {}
  local realpath = runtime.realpath or command.realpath
  return realpath(expanded)
end

local function basename(path)
  if path == "/" then
    return "/"
  end
  return path:match("([^/]+)$") or path
end

function M.new(path, options, runtime)
  options = options or {}
  local canonical = M.normalize_path(path, options.home, runtime)
  if not canonical then
    return nil, "project path cannot be resolved: " .. tostring(path)
  end

  return {
    id = canonical,
    path = canonical,
    name = options.name or basename(canonical),
    source = options.source or "explicit",
    stale = false,
  }
end

return M

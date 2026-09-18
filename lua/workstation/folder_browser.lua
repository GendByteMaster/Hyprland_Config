local command = require("workstation.command")
local paths = require("workstation.paths")
local project_model = require("workstation.project_model")

local M = {}

local function default_runtime()
  return {
    canonical_directory = function(path)
      return command.capture("cd -- " .. command.quote(path) .. " && pwd -P")
    end,
    list_directories = function(path)
      local output = command.capture(
        "find " .. command.quote(path)
          .. " -mindepth 1 -maxdepth 1 -type d -printf '%f\\0'"
      )
      if output == nil then
        return nil, "failed to list directory"
      end

      local entries = {}
      for name in output:gmatch("([^%z]+)%z") do
        if name ~= "" and name:sub(1, 1) ~= "." then
          entries[#entries + 1] = name
        end
      end
      return entries
    end,
  }
end

local function canonicalize(path, home, runtime)
  local candidate = project_model.local_path(path)
  if not candidate or candidate == "" then
    candidate = home
  end

  candidate = project_model.expand_path(candidate, home)
  if not candidate or candidate == "" then
    return nil, "folder path is invalid"
  end

  local canonical = runtime.canonical_directory(candidate)
  if type(canonical) ~= "string" or canonical == "" then
    return nil, "folder is not available: " .. tostring(candidate)
  end
  return canonical
end

function M.canonical_directory(path, options)
  options = options or {}
  local home = assert(options.home or os.getenv("HOME"), "home is required")
  local runtime = options.runtime or default_runtime()
  return canonicalize(path, home, runtime)
end

function M.list(path, options)
  options = options or {}
  local home = assert(options.home or os.getenv("HOME"), "home is required")
  local runtime = options.runtime or default_runtime()

  local canonical, canonical_error = canonicalize(path, home, runtime)
  if not canonical then
    return nil, canonical_error
  end

  local names, list_error = runtime.list_directories(canonical)
  if not names then
    return nil, list_error or "failed to list folder"
  end

  table.sort(names, function(left, right)
    local left_lower = left:lower()
    local right_lower = right:lower()
    if left_lower == right_lower then
      return left < right
    end
    return left_lower < right_lower
  end)

  local entries = {}
  for _, name in ipairs(names) do
    entries[#entries + 1] = {
      name = name,
      path = paths.join(canonical, name),
    }
  end

  local parent = nil
  if canonical ~= "/" then
    parent = paths.dirname(canonical)
    if parent == "." then
      parent = "/"
    end
  end

  return {
    path = canonical,
    parent = parent,
    entries = entries,
  }
end

return M

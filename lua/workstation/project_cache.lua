local command = require("workstation.command")
local atomic_write = require("workstation.atomic_write")
local json = require("workstation.json")
local paths = require("workstation.paths")

local M = {}

local function cache_path(options)
  if options.cache_path then
    return options.cache_path
  end
  local home = assert(options.home or os.getenv("HOME"), "home is required")
  local cache_home = options.cache_home or os.getenv("XDG_CACHE_HOME")
    or paths.join(home, ".cache")
  return paths.join(cache_home, "hyprland-workstation", "project-launcher", "projects.json")
end

local function read_file(path)
  local file = io.open(path, "rb")
  if not file then
    return nil
  end
  local content = file:read("*a")
  file:close()
  return content
end

local function write_atomic(path, content)
  return atomic_write.write(path, content)
end

local function default_runtime()
  return {
    exists = command.exists,
    read = read_file,
    write_atomic = write_atomic,
  }
end

local function valid_project(project)
  return type(project) == "table"
    and type(project.id) == "string"
    and project.id ~= ""
    and type(project.path) == "string"
    and project.path ~= ""
    and type(project.name) == "string"
    and project.name ~= ""
    and (project.source == nil or type(project.source) == "string")
    and (project.stale == nil or type(project.stale) == "boolean")
end

local function dense_projects(value)
  if type(value) ~= "table" then
    return false
  end

  local count = 0
  local max = 0
  for key, project in pairs(value) do
    if type(key) ~= "number" or key < 1 or key % 1 ~= 0 or not valid_project(project) then
      return false
    end
    count = count + 1
    if key > max then
      max = key
    end
  end
  return count == max
end

function M.write(projects, options)
  options = options or {}
  if not dense_projects(projects or {}) then
    return nil, "invalid project cache records"
  end

  local encoded_projects = json.array({})
  for index, project in ipairs(projects) do
    encoded_projects[index] = {
      id = project.id,
      path = project.path,
      name = project.name,
      source = project.source or "discovered",
      stale = project.stale == true,
    }
  end

  local payload = json.encode({
    version = 1,
    projects = encoded_projects,
  })

  local runtime = options.runtime or default_runtime()
  local ok, err = runtime.write_atomic(cache_path(options), payload)
  if not ok then
    return nil, err or "failed to write project cache"
  end
  return true
end

function M.read(options)
  options = options or {}
  local runtime = options.runtime or default_runtime()
  local path = cache_path(options)

  if not runtime.exists(path) then
    return nil, nil
  end

  local content = runtime.read(path)
  if type(content) ~= "string" then
    return nil, "failed to read project cache"
  end

  local decoded, decode_error = json.decode(content)
  if not decoded then
    return nil, "invalid project cache: " .. tostring(decode_error)
  end
  if type(decoded) ~= "table" or decoded.version ~= 1 or not dense_projects(decoded.projects) then
    return nil, "invalid project cache shape"
  end

  local projects = {}
  for index, project in ipairs(decoded.projects) do
    projects[index] = {
      id = project.id,
      path = project.path,
      name = project.name,
      source = project.source or "discovered",
      stale = project.stale == true,
    }
  end
  return projects, nil
end

return M

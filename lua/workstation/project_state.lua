local command = require("workstation.command")
local atomic_write = require("workstation.atomic_write")
local json = require("workstation.json")
local paths = require("workstation.paths")

local M = {}

local function empty_state()
  return {
    favorites = {},
    recent = {},
    roots = {},
  }
end

local function state_path(options)
  if options.state_path then
    return options.state_path
  end
  local home = assert(options.home or os.getenv("HOME"), "home is required")
  local state_home = options.state_home or os.getenv("XDG_STATE_HOME")
    or paths.join(home, ".local", "state")
  return paths.join(state_home, "hyprland-workstation", "project-launcher", "state.json")
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

local function default_runtime()
  return {
    exists = command.exists,
    read = read_file,
    write_atomic = write_atomic,
  }
end

local function valid_favorites(value)
  if type(value) ~= "table" then
    return false
  end
  for key, item in pairs(value) do
    if type(key) ~= "string" or type(item) ~= "boolean" then
      return false
    end
  end
  return true
end

local function valid_roots(value)
  if value == nil then
    return true
  end
  if type(value) ~= "table" then
    return false
  end

  local count = 0
  local max = 0
  for key, item in pairs(value) do
    if type(key) ~= "number" or key < 1 or key % 1 ~= 0
      or type(item) ~= "string" or item == "" then
      return false
    end
    count = count + 1
    if key > max then
      max = key
    end
  end
  return count == max
end

local function valid_recent(value)
  if type(value) ~= "table" then
    return false
  end

  local count = 0
  local max = 0
  for key, item in pairs(value) do
    if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
      return false
    end
    if type(item) ~= "table"
      or type(item.id) ~= "string"
      or item.id == ""
      or type(item.used_at) ~= "number" then
      return false
    end
    count = count + 1
    if key > max then
      max = key
    end
  end
  return count == max
end

function M.load(options)
  options = options or {}
  local runtime = options.runtime or default_runtime()
  local path = state_path(options)

  if not runtime.exists(path) then
    return empty_state(), nil
  end

  local content = runtime.read(path)
  if type(content) ~= "string" then
    return empty_state(), "failed to read project launcher state"
  end

  local decoded, decode_error = json.decode(content)
  if not decoded then
    return empty_state(), "invalid project launcher state: " .. tostring(decode_error)
  end
  if type(decoded) ~= "table"
    or decoded.version ~= 1
    or not valid_favorites(decoded.favorites)
    or not valid_recent(decoded.recent)
    or not valid_roots(decoded.roots) then
    return empty_state(), "invalid project launcher state shape"
  end

  local state = empty_state()
  for id, favorite in pairs(decoded.favorites) do
    if favorite then
      state.favorites[id] = true
    end
  end
  for index, item in ipairs(decoded.recent) do
    if index > 50 then
      break
    end
    state.recent[index] = {
      id = item.id,
      used_at = item.used_at,
    }
  end
  for index, root in ipairs(decoded.roots or {}) do
    state.roots[index] = root
  end
  return state, nil
end

function M.toggle_favorite(state, project_id)
  assert(type(state) == "table", "state is required")
  assert(type(project_id) == "string" and project_id ~= "", "project id is required")

  if state.favorites[project_id] then
    state.favorites[project_id] = nil
    return false
  end

  state.favorites[project_id] = true
  return true
end

function M.add_root(state, root)
  assert(type(state) == "table", "state is required")
  assert(type(root) == "string" and root ~= "", "root is required")

  state.roots = state.roots or {}
  for _, existing in ipairs(state.roots) do
    if existing == root then
      return false
    end
  end

  state.roots[#state.roots + 1] = root
  return true
end

function M.mark_recent(state, project_id, now)
  assert(type(state) == "table", "state is required")
  assert(type(project_id) == "string" and project_id ~= "", "project id is required")
  assert(type(now) == "number", "timestamp is required")

  local recent = {
    { id = project_id, used_at = now },
  }

  for _, item in ipairs(state.recent or {}) do
    if item.id ~= project_id and #recent < 50 then
      recent[#recent + 1] = {
        id = item.id,
        used_at = item.used_at,
      }
    end
  end

  state.recent = recent
  return state
end

function M.save(state, options)
  options = options or {}
  local runtime = options.runtime or default_runtime()
  local path = state_path(options)

  local recent = json.array({})
  for index, item in ipairs(state.recent or {}) do
    if index > 50 then
      break
    end
    recent[index] = {
      id = item.id,
      used_at = item.used_at,
    }
  end

  local roots = json.array({})
  for index, root in ipairs(state.roots or {}) do
    roots[index] = root
  end

  local payload = json.encode({
    version = 1,
    favorites = state.favorites or {},
    recent = recent,
    roots = roots,
  })

  local ok, err = runtime.write_atomic(path, payload)
  if not ok then
    return nil, err or "failed to save project launcher state"
  end
  return true
end

return M

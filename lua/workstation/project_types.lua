local json = require("workstation.json")
local paths = require("workstation.paths")

local M = {}

local COMPOSE_FILES = {
  "compose.yaml",
  "compose.yml",
  "docker-compose.yaml",
  "docker-compose.yml",
}

local PACKAGE_MANAGERS = {
  { file = "pnpm-lock.yaml", name = "pnpm" },
  { file = "yarn.lock", name = "yarn" },
  { file = "bun.lockb", name = "bun" },
  { file = "bun.lock", name = "bun" },
  { file = "package-lock.json", name = "npm" },
}

local function default_runtime()
  return {
    exists = function(path)
      local file = io.open(path, "rb")
      if file then
        file:close()
        return true
      end
      local ok = os.execute("test -e " .. string.format("%q", path))
      return ok == true or ok == 0
    end,
    read = function(path)
      local file = io.open(path, "rb")
      if not file then
        return nil
      end
      local content = file:read("*a")
      file:close()
      return content
    end,
  }
end

local function join(root, name)
  return paths.join(root, name)
end

local function detect_node(root, runtime, result)
  local package_path = join(root, "package.json")
  if not runtime.exists(package_path) then
    return
  end

  result.node = true
  result.package_manager = "npm"
  result.node_scripts = {}

  for _, candidate in ipairs(PACKAGE_MANAGERS) do
    if runtime.exists(join(root, candidate.file)) then
      result.package_manager = candidate.name
      break
    end
  end

  local content = runtime.read(package_path)
  if type(content) ~= "string" then
    result.node_error = "package.json could not be read"
    return
  end

  local decoded, err = json.decode(content)
  if not decoded or type(decoded) ~= "table" then
    result.node_error = "package.json is invalid: " .. tostring(err or "expected object")
    return
  end

  local scripts = decoded.scripts
  if scripts == nil then
    return
  end
  if type(scripts) ~= "table" then
    result.node_error = "package.json scripts must be an object"
    return
  end

  for _, name in ipairs({ "dev", "test", "build" }) do
    if type(scripts[name]) == "string" and scripts[name] ~= "" then
      result.node_scripts[name] = true
    end
  end
end

function M.detect(project, runtime)
  assert(type(project) == "table" and type(project.path) == "string", "project path is required")
  runtime = runtime or default_runtime()

  local root = project.path
  local result = {
    git = runtime.exists(join(root, ".git")),
    rust = runtime.exists(join(root, "Cargo.toml")),
    python = runtime.exists(join(root, "pyproject.toml")),
    node = false,
    compose = false,
    node_scripts = {},
  }

  detect_node(root, runtime, result)

  for _, filename in ipairs(COMPOSE_FILES) do
    if runtime.exists(join(root, filename)) then
      result.compose = true
      result.compose_file = filename
      break
    end
  end

  return result
end

return M

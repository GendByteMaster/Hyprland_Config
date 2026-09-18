local command = require("workstation.command")
local paths = require("workstation.paths")
local project_model = require("workstation.project_model")

local M = {}

local EXCLUDED_DIRS = {
  ".git",
  "node_modules",
  "target",
  ".venv",
  "dist",
  "build",
  ".cache",
  "__pycache__",
}

local function default_runtime()
  return {
    exists = command.exists,
    realpath = command.realpath,
    is_symlink = command.is_symlink,
    find_git_markers = function(root, max_depth, excluded)
      local prune_names = {}
      for _, name in ipairs(excluded) do
        if name ~= ".git" then
          prune_names[#prune_names + 1] = "-name " .. command.quote(name)
        end
      end

      local heavy_prune = ""
      if #prune_names > 0 then
        heavy_prune = "\\( -type d \\( " .. table.concat(prune_names, " -o ")
          .. " \\) -prune \\) -o "
      end

      local shell = "find " .. command.quote(root)
        .. " -mindepth 1 -maxdepth " .. tostring(max_depth + 1)
        .. " \\( " .. heavy_prune
        .. "\\( -name '.git' \\( -type d -o -type f \\) -print0 -prune \\) \\)"

      local output = command.capture(shell)
      if output == nil then
        return nil, "scan failed"
      end

      local markers = {}
      for marker in output:gmatch("([^%z]+)%z") do
        markers[#markers + 1] = marker
      end
      return markers
    end,
  }
end

local function canonical_or_expanded(path, home, runtime)
  return project_model.normalize_path(path, home, runtime)
    or project_model.expand_path(path, home)
end

local function warning(result, message)
  result.warnings[#result.warnings + 1] = message
end

local function within_depth(root, project_path, max_depth)
  local normalized_root = tostring(root):gsub("/+$", "")
  local normalized_project = tostring(project_path):gsub("/+$", "")

  if normalized_project == normalized_root then
    return true
  end

  local prefix = normalized_root .. "/"
  if normalized_project:sub(1, #prefix) ~= prefix then
    return false
  end

  local relative = normalized_project:sub(#prefix + 1)
  local depth = 0
  for _ in relative:gmatch("[^/]+") do
    depth = depth + 1
  end
  return depth <= max_depth
end

function M.discover(config, runtime)
  assert(type(config) == "table", "config is required")
  runtime = runtime or default_runtime()

  local result = {
    projects = {},
    warnings = {},
  }
  local by_id = {}
  local home = config.home or os.getenv("HOME") or ""

  local hidden = {}
  for _, hidden_path in ipairs(config.hidden or {}) do
    local normalized = canonical_or_expanded(hidden_path, home, runtime)
    if normalized then
      hidden[normalized] = true
    end
  end

  for _, root in ipairs(config.roots or {}) do
    if not runtime.exists(root) then
      warning(result, "project root is unavailable: " .. tostring(root))
    else
      local markers, scan_error = runtime.find_git_markers(
        root,
        config.max_depth or 4,
        EXCLUDED_DIRS
      )

      if not markers then
        warning(result, "failed to scan " .. tostring(root) .. ": " .. tostring(scan_error))
      else
        for _, marker in ipairs(markers) do
          if not runtime.is_symlink(marker) then
            local project_path = paths.dirname(marker)
            if within_depth(root, project_path, config.max_depth or 4) then
              local project, project_error = project_model.new(project_path, {
                home = home,
                source = "discovered",
              }, runtime)

              if project then
                if not hidden[project.id] and not by_id[project.id] then
                  by_id[project.id] = project
                end
              else
                warning(result, project_error)
              end
            end
          end
        end
      end
    end
  end

  for _, explicit in ipairs(config.projects or {}) do
    local project, project_error = project_model.new(explicit.path, {
      home = home,
      name = explicit.name,
      source = "explicit",
    }, runtime)

    if project then
      if not hidden[project.id] then
        by_id[project.id] = project
      end
    else
      warning(result, project_error)
    end
  end

  for _, project in pairs(by_id) do
    result.projects[#result.projects + 1] = project
  end

  table.sort(result.projects, function(left, right)
    local left_name = left.name:lower()
    local right_name = right.name:lower()
    if left_name == right_name then
      return left.path < right.path
    end
    return left_name < right_name
  end)

  return result
end

return M

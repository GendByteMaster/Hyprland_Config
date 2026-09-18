local M = {}

local function copy_argv(argv)
  if argv == nil then
    return nil
  end
  local copy = {}
  for index, value in ipairs(argv) do
    copy[index] = value
  end
  return copy
end

local function command_available(capabilities, name)
  return capabilities.commands and capabilities.commands[name] == true
end

local function action(id, label, argv, terminal, extra)
  local value = {
    id = id,
    label = label,
    argv = copy_argv(argv),
    terminal = terminal == true,
    enabled = true,
    confirm = false,
    shell = false,
  }

  for key, item in pairs(extra or {}) do
    value[key] = item
  end
  return value
end

local function disable(value, reason)
  value.enabled = false
  value.reason = reason
  return value
end

local function universal_actions(capabilities)
  local result = {}

  local shell = action("open-shell", "Open Shell", {}, true, { operation = "terminal" })
  if capabilities.terminal == false then
    disable(shell, "terminal is unavailable")
  end
  result[#result + 1] = shell

  local editor = action("open-editor", "Open Editor", nil, false, { operation = "editor" })
  if capabilities.editor == false then
    disable(editor, "editor is unavailable")
  end
  result[#result + 1] = editor

  local file_manager = action("open-file-manager", "Open File Manager", nil, false, {
    operation = "file-manager",
  })
  if capabilities.file_manager == false then
    disable(file_manager, "file manager is unavailable")
  end
  result[#result + 1] = file_manager

  result[#result + 1] = action(
    "favorite",
    capabilities.is_favorite and "Unfavorite" or "Favorite",
    nil,
    false,
    { operation = "favorite" }
  )

  if capabilities.clipboard ~= false then
    result[#result + 1] = action("copy-path", "Copy Path", nil, false, {
      operation = "clipboard",
    })
  end

  return result
end

local function add_command_action(result, value, capabilities, executable)
  if not command_available(capabilities, executable) then
    disable(value, executable .. " is unavailable")
  end
  result[#result + 1] = value
end

local function auto_actions(types, capabilities)
  local result = {}

  if types.git then
    add_command_action(result, action("git-status", "Git Status", { "git", "status" }, true), capabilities, "git")
    add_command_action(result, action("git-log", "Git Log", { "git", "log", "--oneline", "--decorate", "--graph", "-30" }, true), capabilities, "git")
  end

  if types.rust then
    add_command_action(result, action("rust-test", "Cargo Test", { "cargo", "test" }, true), capabilities, "cargo")
    add_command_action(result, action("rust-run", "Cargo Run", { "cargo", "run" }, true), capabilities, "cargo")
  end

  if types.node then
    local manager = types.package_manager or "npm"
    for _, script in ipairs({ "dev", "test", "build" }) do
      if types.node_scripts and types.node_scripts[script] then
        local id = "node-" .. script
        local label = script:sub(1, 1):upper() .. script:sub(2)
        local argv = { manager, "run", script }
        add_command_action(result, action(id, label, argv, true), capabilities, manager)
      end
    end
  end

  if types.python and command_available(capabilities, "pytest") then
    result[#result + 1] = action("python-test", "Python Test", { "pytest" }, true)
  end

  if types.compose then
    add_command_action(result, action("compose-up", "Compose Up", { "docker", "compose", "up" }, true), capabilities, "docker")
    add_command_action(result, action("compose-logs", "Compose Logs", { "docker", "compose", "logs", "-f" }, true), capabilities, "docker")
    add_command_action(result, action("compose-down", "Compose Down", { "docker", "compose", "down" }, true, {
      confirm = true,
    }), capabilities, "docker")
  end

  return result
end

local function index_actions(actions)
  local positions = {}
  for index, value in ipairs(actions) do
    positions[value.id] = index
  end
  return positions
end

local function validate_override(raw)
  if type(raw) ~= "table" or type(raw.id) ~= "string" or raw.id == "" then
    return nil
  end
  if raw.visible == false then
    return {
      id = raw.id,
      visible = false,
    }
  end

  if raw.argv ~= nil then
    if type(raw.argv) ~= "table" then
      return nil
    end
    for index, item in ipairs(raw.argv) do
      if type(index) ~= "number" or type(item) ~= "string" then
        return nil
      end
    end
  end

  return raw
end

local function merge_override(base, raw)
  local merged = {}
  for key, value in pairs(base or {}) do
    if key == "argv" then
      merged.argv = copy_argv(value)
    else
      merged[key] = value
    end
  end

  for key, value in pairs(raw) do
    if key ~= "visible" then
      if key == "argv" then
        merged.argv = copy_argv(value)
      else
        merged[key] = value
      end
    end
  end

  merged.enabled = true
  merged.reason = nil
  if merged.confirm == nil then
    merged.confirm = false
  end
  if merged.shell == nil then
    merged.shell = false
  end
  if merged.terminal == nil then
    merged.terminal = false
  end
  return merged
end

local function apply_overrides(actions, project, config)
  local project_override = config.overrides and (
    config.overrides[project.path] or config.overrides[project.id]
  )
  if not project_override or type(project_override.actions) ~= "table" then
    return actions
  end

  local result = {}
  for _, value in ipairs(actions) do
    result[#result + 1] = value
  end

  local positions = index_actions(result)
  for _, raw in ipairs(project_override.actions) do
    local override = validate_override(raw)
    if override then
      local position = positions[override.id]
      if override.visible == false then
        if position then
          table.remove(result, position)
          positions = index_actions(result)
        end
      else
        local merged = merge_override(position and result[position] or {
          id = override.id,
          label = override.label or override.id,
        }, override)

        if position then
          result[position] = merged
        else
          result[#result + 1] = merged
          positions[merged.id] = #result
        end
      end
    end
  end
  return result
end

local function capability_pass(actions, capabilities)
  for _, value in ipairs(actions) do
    if value.operation == nil and value.argv and #value.argv > 0 then
      local executable = value.argv[1]
      if not command_available(capabilities, executable) then
        disable(value, executable .. " is unavailable")
      else
        value.enabled = true
        value.reason = nil
      end
    end
  end
  return actions
end

function M.resolve(project, types, config, capabilities)
  assert(type(project) == "table" and type(project.path) == "string", "project is required")
  types = types or {}
  config = config or {}
  capabilities = capabilities or {}

  local actions = universal_actions(capabilities)
  local detected = auto_actions(types, capabilities)
  for _, value in ipairs(detected) do
    actions[#actions + 1] = value
  end

  actions = apply_overrides(actions, project, config)
  return capability_pass(actions, capabilities)
end

return M

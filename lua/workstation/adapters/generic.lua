local command = require("workstation.command")

local M = {}

local KNOWN_TERMINALS = {
  "foot",
  "ghostty",
  "kitty",
  "alacritty",
}

local PROJECT_COMMANDS = {
  "git",
  "cargo",
  "pnpm",
  "yarn",
  "bun",
  "npm",
  "pytest",
  "docker",
  "bash",
}

local function append(base, extra)
  local result = {}
  for _, value in ipairs(base or {}) do
    result[#result + 1] = value
  end
  for _, value in ipairs(extra or {}) do
    result[#result + 1] = value
  end
  return result
end

local function copy(value)
  return append({}, value)
end

local function default_runtime()
  return {
    command_exists = command.command_exists,
    getenv = os.getenv,
  }
end

local function executable_name(argv)
  return type(argv) == "table" and argv[1] or nil
end

local function configured_argv(argv, runtime)
  local executable = executable_name(argv)
  if not executable or executable == "" then
    return nil, "application is not configured"
  end
  if not runtime.command_exists(executable) then
    return nil, executable .. " is unavailable"
  end
  return copy(argv)
end

local function exact_terminal_env(runtime)
  local preferred = runtime.getenv("TERMINAL")
  if type(preferred) ~= "string" or preferred == "" then
    return nil
  end

  for _, name in ipairs(KNOWN_TERMINALS) do
    if preferred == name and runtime.command_exists(name) then
      return name
    end
  end
  return nil
end

local function resolve_terminal(config, runtime)
  local requested = config.apps and config.apps.terminal or "auto"

  if requested ~= "auto" then
    for _, name in ipairs(KNOWN_TERMINALS) do
      if requested == name then
        if runtime.command_exists(name) then
          return name
        end
        return nil, name .. " is unavailable"
      end
    end
    return nil, "unsupported terminal adapter: " .. tostring(requested)
  end

  if runtime.command_exists("xdg-terminal-exec") then
    return "xdg-terminal-exec"
  end

  local preferred = exact_terminal_env(runtime)
  if preferred then
    return preferred
  end

  local installed = {}
  for _, name in ipairs(KNOWN_TERMINALS) do
    if runtime.command_exists(name) then
      installed[#installed + 1] = name
    end
  end

  if #installed == 1 then
    return installed[1]
  end
  if #installed > 1 then
    return nil, "terminal selection is ambiguous; configure apps.terminal"
  end
  return nil, "terminal is unavailable"
end

local function terminal_argv(kind, cwd, argv)
  argv = argv or {}

  if kind == "xdg-terminal-exec" then
    return append({ "xdg-terminal-exec", "--dir=" .. cwd }, argv)
  end
  if kind == "foot" then
    return append({ "foot", "--working-directory=" .. cwd }, argv)
  end
  if kind == "ghostty" then
    local base = { "ghostty", "--working-directory=" .. cwd }
    if #argv > 0 then
      base[#base + 1] = "-e"
    end
    return append(base, argv)
  end
  if kind == "kitty" then
    return append({ "kitty", "--directory", cwd }, argv)
  end
  if kind == "alacritty" then
    local base = { "alacritty", "--working-directory", cwd }
    if #argv > 0 then
      base[#base + 1] = "-e"
    end
    return append(base, argv)
  end
  return nil, "terminal is unavailable"
end

local function resolve_editor(config, runtime)
  if config.apps and config.apps.editor then
    return configured_argv(config.apps.editor, runtime)
  end

  for _, variable in ipairs({ "VISUAL", "EDITOR" }) do
    local preferred = runtime.getenv(variable)
    if type(preferred) == "string"
      and preferred ~= ""
      and not preferred:find("%s")
      and runtime.command_exists(preferred) then
      return { preferred }
    end
  end

  for _, name in ipairs({ "code", "codium", "zed", "cursor" }) do
    if runtime.command_exists(name) then
      return { name }
    end
  end
  return nil, "editor is unavailable"
end

local function resolve_file_manager(config, runtime)
  if config.apps and config.apps.file_manager then
    return configured_argv(config.apps.file_manager, runtime)
  end

  if runtime.command_exists("xdg-open") then
    return { "xdg-open" }
  end
  return nil, "file manager is unavailable"
end

local function resolve_clipboard(runtime)
  if runtime.command_exists("wl-copy") then
    return { "wl-copy" }
  end
  if runtime.command_exists("xclip") then
    return { "xclip", "-selection", "clipboard" }
  end
  return nil, "clipboard utility is unavailable"
end

function M.detect(config, runtime)
  config = config or { apps = { terminal = "auto" } }
  config.apps = config.apps or { terminal = "auto" }
  runtime = runtime or default_runtime()

  local terminal_kind, terminal_error = resolve_terminal(config, runtime)
  local editor, editor_error = resolve_editor(config, runtime)
  local file_manager, file_manager_error = resolve_file_manager(config, runtime)
  local clipboard, clipboard_error = resolve_clipboard(runtime)

  local adapter = {
    kind = "generic",
  }

  function adapter.capabilities()
    local commands = {}
    for _, name in ipairs(PROJECT_COMMANDS) do
      commands[name] = runtime.command_exists(name)
    end

    return {
      terminal = terminal_kind ~= nil,
      editor = editor ~= nil,
      file_manager = file_manager ~= nil,
      clipboard = clipboard ~= nil,
      commands = commands,
    }
  end

  function adapter.terminal_argv(cwd, argv)
    if not terminal_kind then
      return nil, terminal_error or "terminal is unavailable"
    end
    return terminal_argv(terminal_kind, cwd, argv)
  end

  function adapter.editor_argv(path)
    if not editor then
      return nil, editor_error or "editor is unavailable"
    end
    return append(editor, { path })
  end

  function adapter.file_manager_argv(path)
    if not file_manager then
      return nil, file_manager_error or "file manager is unavailable"
    end
    return append(file_manager, { path })
  end

  function adapter.clipboard_argv(text)
    if not clipboard then
      return nil, nil, clipboard_error or "clipboard utility is unavailable"
    end
    return copy(clipboard), text, nil
  end

  return adapter
end

return M

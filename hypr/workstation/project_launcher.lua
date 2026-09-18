local compat = require("hypr.workstation.compat")

local M = {}

local function launcher_path(options)
  if options and type(options.launcher) == "string" and options.launcher ~= "" then
    return options.launcher
  end

  local home = os.getenv("HOME") or ""
  return home .. "/.local/bin/hyprland-workstation-launcher"
end

local function register_binding(hl, keys, command, description)
  if type(hl.unbind) == "function" then
    hl.unbind(keys)
  end

  hl.bind(keys, hl.dsp.exec_cmd(command), {
    description = description,
  })
end

function M.register(hl, _o, options)
  options = options or {}

  assert(type(hl) == "table", "Hyprland API is required")
  assert(type(hl.bind) == "function", "Hyprland bind API is required")
  assert(type(hl.dsp) == "table" and type(hl.dsp.exec_cmd) == "function", "Hyprland exec dispatcher is required")

  local command = launcher_path(options)

  register_binding(hl, "SUPER + F8", command, "Project Launcher")

  if type(hl.window_rule) == "function" then
    hl.window_rule({
      name = "gendbyte-project-launcher",
      match = {
        class = "^gendbyte-project-launcher$",
      },
      float = true,
      center = true,
    })
  end
end

return M

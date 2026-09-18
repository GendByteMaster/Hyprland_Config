local M = {}

local function launcher_path(options)
  if options and type(options.launcher) == "string" and options.launcher ~= "" then
    return options.launcher
  end

  local home = os.getenv("HOME") or ""
  return home .. "/.local/bin/hyprland-workstation-launcher"
end

function M.register(hl, _o, options)
  assert(type(hl) == "table", "Hyprland API is required")
  assert(type(hl.bind) == "function", "Hyprland bind API is required")
  assert(type(hl.dsp) == "table" and type(hl.dsp.exec_cmd) == "function", "Hyprland exec dispatcher is required")

  local keys = "SUPER + R"
  if type(hl.unbind) == "function" then
    hl.unbind(keys)
  end

  hl.bind(keys, hl.dsp.exec_cmd(launcher_path(options)), {
    description = "Project Launcher",
  })

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

local testlib = require("tests.testlib")
local test = testlib.test

local function read_file(path)
  local file = assert(io.open(path, "rb"))
  local content = file:read("*a")
  file:close()
  return content
end

test("real projects TOML example parses and exposes Open Workspace targets", function()
  local config_module = require("workstation.project_config")
  local toml = require("workstation.toml")
  local content = read_file("examples/projects.toml")
  local raw, parse_error = toml.decode(content)

  testlib.eq(parse_error, nil)
  testlib.truthy(raw)

  local config, config_error = config_module.load({
    home = "/home/test",
    config_path = "/repo/examples/projects.toml",
    runtime = {
      exists = function(path)
        return path == "/repo/examples/projects.toml"
      end,
      load_config = function()
        return raw
      end,
    },
  })

  testlib.eq(config_error, nil)
  testlib.eq(config.roots[1], "/home/test/Repository")
  testlib.eq(config.max_depth, 4)
  testlib.eq(config.apps.terminal, "auto")

  local expected = {
    "Voxelyra_Nexus",
    "VoxClip",
    "ForgeGuard",
    "NumFlow",
    "Veridyn",
    "submart_backend",
    "Hyprland_Config",
  }

  for _, name in ipairs(expected) do
    local path = "/home/test/Repository/" .. name
    local override = config.overrides[path]
    testlib.truthy(override, "missing override for " .. name)
    testlib.eq(#override.workspace.targets, 2)
    testlib.eq(override.workspace.targets[1].operation, "editor")
    testlib.eq(override.workspace.targets[1].workspace, 1)
    testlib.eq(override.workspace.targets[2].terminal, true)
    testlib.eq(override.workspace.targets[2].workspace, 2)
    testlib.eq(override.workspace.targets[2].argv[1], "bash")
  end
end)

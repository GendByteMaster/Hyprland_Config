local testlib = require("tests.testlib")
local test = testlib.test

test("project config defaults to Repository and depth four", function()
  local config = require("workstation.project_config").defaults("/home/test")
  testlib.eq(config.roots[1], "/home/test/Repository")
  testlib.eq(config.max_depth, 4)
  testlib.eq(config.apps.terminal, "auto")
  testlib.eq(#config.projects, 0)
  testlib.eq(#config.hidden, 0)
end)

test("missing project config uses safe defaults", function()
  local module = require("workstation.project_config")
  local config, err = module.load({
    home = "/home/test",
    runtime = {
      exists = function() return false end,
    },
  })

  testlib.eq(err, nil)
  testlib.eq(config.roots[1], "/home/test/Repository")
end)

test("valid project config expands roots and preserves explicit projects", function()
  local module = require("workstation.project_config")
  local config, err = module.load({
    home = "/home/test",
    config_path = "/tmp/projects.lua",
    runtime = {
      exists = function(path) return path == "/tmp/projects.lua" end,
      load_config = function()
        return {
          roots = { "~/Repository", "~/Projects" },
          projects = {
            { path = "~/scratch/demo", name = "Demo" },
          },
          hidden = { "~/Repository/archive" },
          apps = {
            terminal = "ghostty",
            editor = { "code", "--reuse-window" },
          },
          max_depth = 3,
          overrides = {
            ["~/Repository/demo"] = { actions = {} },
          },
        }
      end,
    },
  })

  testlib.eq(err, nil)
  testlib.eq(config.roots[1], "/home/test/Repository")
  testlib.eq(config.roots[2], "/home/test/Projects")
  testlib.eq(config.projects[1].path, "/home/test/scratch/demo")
  testlib.eq(config.projects[1].name, "Demo")
  testlib.eq(config.hidden[1], "/home/test/Repository/archive")
  testlib.eq(config.apps.terminal, "ghostty")
  testlib.eq(config.apps.editor[1], "code")
  testlib.eq(config.max_depth, 3)
  testlib.truthy(config.overrides["/home/test/Repository/demo"])
end)

test("malformed project config falls back without rewriting it", function()
  local module = require("workstation.project_config")
  local writes = 0
  local config, err = module.load({
    home = "/home/test",
    config_path = "/tmp/projects.lua",
    runtime = {
      exists = function() return true end,
      load_config = function()
        return {
          roots = "not-an-array",
          max_depth = -1,
        }
      end,
      write = function()
        writes = writes + 1
      end,
    },
  })

  testlib.truthy(err)
  testlib.eq(config.roots[1], "/home/test/Repository")
  testlib.eq(config.max_depth, 4)
  testlib.eq(writes, 0)
end)

test("project config loader errors fall back to defaults", function()
  local module = require("workstation.project_config")
  local config, err = module.load({
    home = "/home/test",
    config_path = "/tmp/projects.lua",
    runtime = {
      exists = function() return true end,
      load_config = function()
        return nil, "syntax error"
      end,
    },
  })

  testlib.truthy(err)
  testlib.eq(config.roots[1], "/home/test/Repository")
end)

test("project config accepts validated workspace targets", function()
  local module = require("workstation.project_config")
  local config, err = module.load({
    home = "/home/test",
    config_path = "/tmp/projects.lua",
    runtime = {
      exists = function() return true end,
      load_config = function()
        return {
          overrides = {
            ["~/Repository/demo"] = {
              workspace = {
                targets = {
                  {
                    name = "editor",
                    workspace = 1,
                    operation = "editor",
                  },
                  {
                    name = "backend",
                    workspace = "name:backend",
                    monitor = "DP-1",
                    terminal = true,
                    argv = { "uv", "run", "fastapi", "dev" },
                  },
                  {
                    name = "browser",
                    workspace = 4,
                    operation = "url",
                    url = "http://localhost:3000",
                  },
                },
              },
            },
          },
        }
      end,
    },
  })

  testlib.eq(err, nil)
  local override = config.overrides["/home/test/Repository/demo"]
  testlib.truthy(override)
  testlib.eq(override.workspace.targets[1].operation, "editor")
  testlib.eq(override.workspace.targets[2].monitor, "DP-1")
  testlib.eq(override.workspace.targets[3].url, "http://localhost:3000")
end)

test("project config rejects malformed workspace target", function()
  local module = require("workstation.project_config")
  local config, err = module.load({
    home = "/home/test",
    config_path = "/tmp/projects.lua",
    runtime = {
      exists = function() return true end,
      load_config = function()
        return {
          overrides = {
            ["~/Repository/demo"] = {
              workspace = {
                targets = {
                  {
                    name = "backend",
                    workspace = 0,
                    terminal = true,
                    argv = { "uv", "run" },
                  },
                },
              },
            },
          },
        }
      end,
    },
  })

  testlib.truthy(err)
  testlib.truthy(err:match("workspace"))
  testlib.eq(config.roots[1], "/home/test/Repository")
  testlib.eq(config.overrides["/home/test/Repository/demo"], nil)
end)

test("project config rejects shell workspace targets", function()
  local module = require("workstation.project_config")
  local _, err = module.load({
    home = "/home/test",
    config_path = "/tmp/projects.lua",
    runtime = {
      exists = function() return true end,
      load_config = function()
        return {
          overrides = {
            ["~/Repository/demo"] = {
              workspace = {
                targets = {
                  {
                    name = "unsafe",
                    argv = { "bash", "-lc", "echo ok" },
                    shell = true,
                  },
                },
              },
            },
          },
        }
      end,
    },
  })

  testlib.truthy(err)
  testlib.truthy(err:match("shell"))
end)

test("project config accepts singleton match and monitor aliases", function()
  local module = require("workstation.project_config")
  local config, err = module.load({
    home = "/home/test",
    config_path = "/tmp/projects.lua",
    runtime = {
      exists = function() return true end,
      load_config = function()
        return {
          monitors = {
            primary = "DP-1",
            secondary = "HDMI-A-1",
          },
          overrides = {
            ["~/Repository/demo"] = {
              workspace = {
                targets = {
                  {
                    name = "editor",
                    workspace = 1,
                    monitor = "primary",
                    operation = "editor",
                    singleton = true,
                    wait_ms = 900,
                    match = {
                      class = "Code",
                      title = "Demo",
                    },
                  },
                },
              },
            },
          },
        }
      end,
    },
  })

  testlib.eq(err, nil)
  testlib.eq(config.monitors.primary, "DP-1")
  testlib.eq(config.monitors.secondary, "HDMI-A-1")
  local target = config.overrides["/home/test/Repository/demo"].workspace.targets[1]
  testlib.eq(target.singleton, true)
  testlib.eq(target.wait_ms, 900)
  testlib.eq(target.match.class, "Code")
end)

test("project config rejects singleton without match selectors", function()
  local module = require("workstation.project_config")
  local _, err = module.load({
    home = "/home/test",
    config_path = "/tmp/projects.lua",
    runtime = {
      exists = function() return true end,
      load_config = function()
        return {
          overrides = {
            ["~/Repository/demo"] = {
              workspace = {
                targets = {
                  {
                    name = "editor",
                    operation = "editor",
                    singleton = true,
                  },
                },
              },
            },
          },
        }
      end,
    },
  })

  testlib.truthy(err)
  testlib.truthy(err:match("requires match"))
end)

test("project config rejects excessive workspace wait", function()
  local module = require("workstation.project_config")
  local _, err = module.load({
    home = "/home/test",
    config_path = "/tmp/projects.lua",
    runtime = {
      exists = function() return true end,
      load_config = function()
        return {
          overrides = {
            ["~/Repository/demo"] = {
              workspace = {
                targets = {
                  {
                    name = "editor",
                    operation = "editor",
                    wait_ms = 6000,
                    match = { class = "Code" },
                  },
                },
              },
            },
          },
        }
      end,
    },
  })

  testlib.truthy(err)
  testlib.truthy(err:match("wait_ms"))
end)

test("project config default loader reads TOML without executing Lua", function()
  local module = require("workstation.project_config")
  local path = os.tmpname()
  local marker = path .. ".executed"
  os.remove(marker)

  local file = assert(io.open(path, "wb"))
  file:write([[
roots = ["~/Repository", "~/Projects"]
max_depth = 3
payload = os.execute("touch ]] .. marker .. [[")
]])
  file:close()

  local config, err = module.load({
    home = "/home/test",
    config_path = path,
  })

  os.remove(path)

  testlib.truthy(err)
  testlib.eq(config.roots[1], "/home/test/Repository")
  local marker_file = io.open(marker, "rb")
  if marker_file then
    marker_file:close()
    os.remove(marker)
    error("TOML config unexpectedly executed code")
  end
end)

test("project config default path is projects.toml and legacy Lua is ignored", function()
  local module = require("workstation.project_config")
  local seen = {}
  local config, err = module.load({
    home = "/home/test",
    runtime = {
      exists = function(path)
        seen[#seen + 1] = path
        return path == "/home/test/.config/hyprland-workstation/projects.lua"
      end,
      load_config = function()
        error("legacy Lua must never be loaded")
      end,
    },
  })

  testlib.eq(config.roots[1], "/home/test/Repository")
  testlib.truthy(err:match("legacy projects.lua is ignored"))
  testlib.eq(seen[1], "/home/test/.config/hyprland-workstation/projects.toml")
  testlib.eq(seen[2], "/home/test/.config/hyprland-workstation/projects.lua")
end)

test("project config rejects non HTTP URL targets", function()
  local module = require("workstation.project_config")
  local _, err = module.load({
    home = "/home/test",
    config_path = "/tmp/projects.toml",
    runtime = {
      exists = function() return true end,
      load_config = function()
        return {
          overrides = {
            ["/home/test/Repository/demo"] = {
              workspace = {
                targets = {
                  {
                    name = "unsafe-url",
                    operation = "url",
                    url = "file:///etc/passwd",
                  },
                },
              },
            },
          },
        }
      end,
    },
  })

  testlib.truthy(err)
  testlib.truthy(err:match("http:// or https://"))
end)

test("project config limits workspace target count", function()
  local module = require("workstation.project_config")
  local targets = {}
  for index = 1, 33 do
    targets[index] = {
      name = "target-" .. tostring(index),
      argv = { "true" },
    }
  end

  local _, err = module.load({
    home = "/home/test",
    config_path = "/tmp/projects.toml",
    runtime = {
      exists = function() return true end,
      load_config = function()
        return {
          overrides = {
            ["/home/test/Repository/demo"] = {
              workspace = { targets = targets },
            },
          },
        }
      end,
    },
  })

  testlib.truthy(err)
  testlib.truthy(err:match("limit of 32"))
end)

test("project config limits total workspace matching wait budget", function()
  local module = require("workstation.project_config")
  local targets = {}
  for index = 1, 9 do
    targets[index] = {
      name = "target-" .. tostring(index),
      argv = { "true" },
      match = { class = "App" .. tostring(index) },
    }
  end

  local _, err = module.load({
    home = "/home/test",
    config_path = "/tmp/projects.toml",
    runtime = {
      exists = function() return true end,
      load_config = function()
        return {
          overrides = {
            ["/home/test/Repository/demo"] = {
              workspace = { targets = targets },
            },
          },
        }
      end,
    },
  })

  testlib.truthy(err)
  testlib.truthy(err:match("wait budget"))
end)

test("project config limits monitor alias count", function()
  local module = require("workstation.project_config")
  local monitors = {}
  for index = 1, 17 do
    monitors["role" .. tostring(index)] = "DP-" .. tostring(index)
  end

  local _, err = module.load({
    home = "/home/test",
    config_path = "/tmp/projects.toml",
    runtime = {
      exists = function() return true end,
      load_config = function()
        return { monitors = monitors }
      end,
    },
  })

  testlib.truthy(err)
  testlib.truthy(err:match("limit of 16"))
end)

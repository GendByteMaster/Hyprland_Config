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

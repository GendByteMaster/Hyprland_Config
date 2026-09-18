local testlib = require("tests.testlib")
local test = testlib.test

local function fake_runtime(options)
  options = options or {}
  local realpaths = options.realpaths or {}
  local roots = options.roots or {}
  local symlinks = options.symlinks or {}

  return {
    exists = function(path)
      return roots[path] ~= nil
    end,
    realpath = function(path)
      return realpaths[path] or path
    end,
    is_symlink = function(path)
      return symlinks[path] == true
    end,
    find_git_markers = function(root, max_depth, excluded)
      local entry = roots[root]
      if type(entry) == "table" and entry.error then
        return nil, entry.error
      end
      return entry or {}
    end,
  }
end

local function base_config()
  return {
    roots = { "/r1" },
    projects = {},
    hidden = {},
    overrides = {},
    apps = { terminal = "auto" },
    max_depth = 4,
  }
end

local function find_project(projects, id)
  for _, project in ipairs(projects) do
    if project.id == id then
      return project
    end
  end
end

test("discovery deduplicates canonical git roots", function()
  local discovery = require("workstation.project_discovery")
  local config = base_config()
  config.roots = { "/r1", "/r2" }

  local result = discovery.discover(config, fake_runtime({
    roots = {
      ["/r1"] = { "/r1/a/.git" },
      ["/r2"] = { "/r2/a/.git" },
    },
    realpaths = {
      ["/r1/a"] = "/work/a",
      ["/r2/a"] = "/work/a",
    },
  }))

  testlib.eq(#result.projects, 1)
  testlib.eq(result.projects[1].id, "/work/a")
end)

test("discovery keeps nested git repositories returned within depth", function()
  local discovery = require("workstation.project_discovery")
  local result = discovery.discover(base_config(), fake_runtime({
    roots = {
      ["/r1"] = {
        "/r1/top/.git",
        "/r1/top/vendor/nested/.git",
      },
    },
  }))

  testlib.eq(#result.projects, 2)
  testlib.truthy(find_project(result.projects, "/r1/top"))
  testlib.truthy(find_project(result.projects, "/r1/top/vendor/nested"))
end)

test("discovery passes configured maximum depth to runtime", function()
  local discovery = require("workstation.project_discovery")
  local seen_depth
  local rt = fake_runtime({ roots = { ["/r1"] = {} } })
  local original = rt.find_git_markers
  rt.find_git_markers = function(root, max_depth, excluded)
    seen_depth = max_depth
    return original(root, max_depth, excluded)
  end

  local config = base_config()
  config.max_depth = 4
  discovery.discover(config, rt)
  testlib.eq(seen_depth, 4)
end)

test("discovery excludes repositories deeper than configured maximum", function()
  local discovery = require("workstation.project_discovery")
  local config = base_config()
  config.max_depth = 4

  local result = discovery.discover(config, fake_runtime({
    roots = {
      ["/r1"] = {
        "/r1/a/b/c/d/.git",
        "/r1/a/b/c/d/e/.git",
      },
    },
  }))

  testlib.eq(#result.projects, 1)
  testlib.eq(result.projects[1].id, "/r1/a/b/c/d")
end)

test("discovery rejects symlink git markers", function()
  local discovery = require("workstation.project_discovery")
  local result = discovery.discover(base_config(), fake_runtime({
    roots = {
      ["/r1"] = { "/r1/linked/.git" },
    },
    symlinks = {
      ["/r1/linked/.git"] = true,
    },
  }))

  testlib.eq(#result.projects, 0)
end)

test("discovery includes explicit non git project", function()
  local discovery = require("workstation.project_discovery")
  local config = base_config()
  config.projects = {
    { path = "/scratch/demo", name = "Demo" },
  }

  local result = discovery.discover(config, fake_runtime({
    roots = { ["/r1"] = {} },
    realpaths = { ["/scratch/demo"] = "/scratch/demo" },
  }))

  local project = find_project(result.projects, "/scratch/demo")
  testlib.truthy(project)
  testlib.eq(project.name, "Demo")
  testlib.eq(project.source, "explicit")
end)

test("discovery hides canonical project path", function()
  local discovery = require("workstation.project_discovery")
  local config = base_config()
  config.hidden = { "/work/hidden" }

  local result = discovery.discover(config, fake_runtime({
    roots = {
      ["/r1"] = {
        "/r1/visible/.git",
        "/r1/hidden/.git",
      },
    },
    realpaths = {
      ["/r1/visible"] = "/work/visible",
      ["/r1/hidden"] = "/work/hidden",
      ["/work/hidden"] = "/work/hidden",
    },
  }))

  testlib.eq(#result.projects, 1)
  testlib.eq(result.projects[1].id, "/work/visible")
end)

test("discovery reports missing root and continues", function()
  local discovery = require("workstation.project_discovery")
  local config = base_config()
  config.roots = { "/missing", "/present" }

  local result = discovery.discover(config, fake_runtime({
    roots = {
      ["/present"] = { "/present/project/.git" },
    },
  }))

  testlib.eq(#result.projects, 1)
  testlib.eq(#result.warnings, 1)
  testlib.truthy(result.warnings[1]:match("/missing"))
end)

test("discovery keeps other roots after one scan error", function()
  local discovery = require("workstation.project_discovery")
  local config = base_config()
  config.roots = { "/denied", "/present" }

  local result = discovery.discover(config, fake_runtime({
    roots = {
      ["/denied"] = { error = "permission denied" },
      ["/present"] = { "/present/project/.git" },
    },
  }))

  testlib.eq(#result.projects, 1)
  testlib.eq(#result.warnings, 1)
  testlib.truthy(result.warnings[1]:match("permission denied"))
end)

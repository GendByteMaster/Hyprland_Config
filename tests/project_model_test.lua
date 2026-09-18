local testlib = require("tests.testlib")
local test = testlib.test

local function runtime(realpaths)
  return {
    realpath = function(path)
      return realpaths[path]
    end,
  }
end

test("project model expands home and uses canonical path as stable id", function()
  local model = require("workstation.project_model")
  local rt = runtime({
    ["/home/test/Repository/NumFlow"] = "/srv/repos/NumFlow",
  })

  local project, err = model.new("~/Repository/NumFlow", {
    home = "/home/test",
    source = "discovered",
  }, rt)

  testlib.eq(err, nil)
  testlib.eq(project.id, "/srv/repos/NumFlow")
  testlib.eq(project.path, "/srv/repos/NumFlow")
  testlib.eq(project.name, "NumFlow")
  testlib.eq(project.source, "discovered")
end)

test("project model keeps same basenames distinct by canonical path", function()
  local model = require("workstation.project_model")
  local rt = runtime({
    ["/one/app"] = "/one/app",
    ["/two/app"] = "/two/app",
  })

  local first = assert(model.new("/one/app", { home = "/home/test" }, rt))
  local second = assert(model.new("/two/app", { home = "/home/test" }, rt))

  testlib.eq(first.name, "app")
  testlib.eq(second.name, "app")
  testlib.truthy(first.id ~= second.id)
end)

test("project model reports unresolved paths", function()
  local model = require("workstation.project_model")
  local project, err = model.new("~/missing", { home = "/home/test" }, runtime({}))
  testlib.eq(project, nil)
  testlib.truthy(err)
end)

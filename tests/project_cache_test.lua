local testlib = require("tests.testlib")
local test = testlib.test

local function memory_runtime(initial)
  local files = initial or {}
  return {
    exists = function(path)
      return files[path] ~= nil
    end,
    read = function(path)
      return files[path]
    end,
    write_atomic = function(path, content)
      files[path] = content
      return true
    end,
    files = files,
  }
end

test("project cache round trips project records", function()
  local cache = require("workstation.project_cache")
  local runtime = memory_runtime()
  local options = {
    home = "/home/test",
    cache_path = "/cache/projects.json",
    runtime = runtime,
  }

  local ok, err = cache.write({
    { id = "/repo/a", path = "/repo/a", name = "A", source = "discovered", stale = false },
  }, options)
  testlib.eq(err, nil)
  testlib.truthy(ok)

  local projects, read_error = cache.read(options)
  testlib.eq(read_error, nil)
  testlib.eq(projects[1].id, "/repo/a")
  testlib.eq(projects[1].name, "A")
end)

test("missing project cache returns nil without warning", function()
  local cache = require("workstation.project_cache")
  local projects, err = cache.read({
    home = "/home/test",
    cache_path = "/cache/projects.json",
    runtime = memory_runtime(),
  })

  testlib.eq(projects, nil)
  testlib.eq(err, nil)
end)

test("corrupt project cache is rejected", function()
  local cache = require("workstation.project_cache")
  local projects, err = cache.read({
    home = "/home/test",
    cache_path = "/cache/projects.json",
    runtime = memory_runtime({
      ["/cache/projects.json"] = '{"version":1,"projects":"bad"}',
    }),
  })

  testlib.eq(projects, nil)
  testlib.truthy(err)
end)

test("project cache rejects invalid project record", function()
  local cache = require("workstation.project_cache")
  local projects, err = cache.read({
    home = "/home/test",
    cache_path = "/cache/projects.json",
    runtime = memory_runtime({
      ["/cache/projects.json"] = '{"version":1,"projects":[{"id":3}]}',
    }),
  })

  testlib.eq(projects, nil)
  testlib.truthy(err)
end)

local testlib = require("tests.testlib")
local test = testlib.test

local function runtime(directories, listings)
  return {
    canonical_directory = function(path)
      return directories[path]
    end,
    list_directories = function(path)
      local values = listings[path]
      if values == nil then
        return nil, "missing listing"
      end
      local copy = {}
      for index, value in ipairs(values) do
        copy[index] = value
      end
      return copy
    end,
  }
end

test("folder browser defaults to home and sorts visible directories", function()
  local browser = require("workstation.folder_browser")
  local result, err = browser.list(nil, {
    home = "/home/test",
    runtime = runtime(
      { ["/home/test"] = "/home/test" },
      { ["/home/test"] = { "Work", ".cache", "projects", "Downloads" } }
    ),
  })

  testlib.eq(err, nil)
  testlib.eq(result.path, "/home/test")
  testlib.eq(result.parent, "/home")
  testlib.eq(#result.entries, 3)
  testlib.eq(result.entries[1].name, "Downloads")
  testlib.eq(result.entries[2].name, "projects")
  testlib.eq(result.entries[3].name, "Work")
  testlib.eq(result.entries[2].path, "/home/test/projects")
end)

test("folder browser accepts file URLs and returns canonical path", function()
  local browser = require("workstation.folder_browser")
  local result, err = browser.list("file:///home/test/My%20Projects", {
    home = "/home/test",
    runtime = runtime(
      { ["/home/test/My Projects"] = "/srv/projects" },
      { ["/srv/projects"] = {} }
    ),
  })

  testlib.eq(err, nil)
  testlib.eq(result.path, "/srv/projects")
  testlib.eq(result.parent, "/srv")
  testlib.eq(#result.entries, 0)
end)

test("folder browser reports unavailable directories", function()
  local browser = require("workstation.folder_browser")
  local result, err = browser.list("/missing", {
    home = "/home/test",
    runtime = runtime({}, {}),
  })

  testlib.eq(result, nil)
  testlib.truthy(err:match("not available"))
end)

test("folder browser root has no parent", function()
  local browser = require("workstation.folder_browser")
  local result = assert(browser.list("/", {
    home = "/home/test",
    runtime = runtime(
      { ["/"] = "/" },
      { ["/"] = { "home", "mnt" } }
    ),
  }))

  testlib.eq(result.path, "/")
  testlib.eq(result.parent, nil)
end)

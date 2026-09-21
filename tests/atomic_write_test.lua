local testlib = require("tests.testlib")
local test = testlib.test
local atomic_write = require("workstation.atomic_write")

test("atomic writer uses unique mktemp path and rename", function()
  local calls = {}
  local buffer = ""
  local runtime = {
    mkdir_p = function(path)
      calls.mkdir = path
      return true
    end,
    mktemp = function(template)
      calls.template = template
      return "/tmp/state.json.tmp.ABC123"
    end,
    open = function(path, mode)
      calls.open = { path, mode }
      return {
        write = function(_, content)
          buffer = content
          return true
        end,
        close = function()
          return true
        end,
      }
    end,
    rename = function(source, target)
      calls.rename = { source, target }
      return true
    end,
    remove = function(path)
      calls.remove = path
      return true
    end,
  }

  local ok, err = atomic_write.write("/tmp/state.json", "payload", runtime)

  testlib.eq(ok, true)
  testlib.eq(err, nil)
  testlib.eq(calls.mkdir, "/tmp")
  testlib.eq(calls.template, "/tmp/state.json.tmp.XXXXXX")
  testlib.eq(calls.open[1], "/tmp/state.json.tmp.ABC123")
  testlib.eq(calls.open[2], "wb")
  testlib.eq(buffer, "payload")
  testlib.eq(calls.rename[1], "/tmp/state.json.tmp.ABC123")
  testlib.eq(calls.rename[2], "/tmp/state.json")
  testlib.eq(calls.remove, nil)
end)

test("atomic writer rejects mktemp path escape", function()
  local removed
  local runtime = {
    mkdir_p = function() return true end,
    mktemp = function() return "/tmp/other-file" end,
    open = function() error("must not open escaped temp") end,
    rename = function() error("must not rename escaped temp") end,
    remove = function(path)
      removed = path
      return true
    end,
  }

  local ok, err = atomic_write.write("/tmp/state.json", "payload", runtime)

  testlib.eq(ok, nil)
  testlib.truthy(err:match("escaped"))
  testlib.eq(removed, "/tmp/other-file")
end)

test("atomic writer removes temp after write failure", function()
  local removed
  local runtime = {
    mkdir_p = function() return true end,
    mktemp = function() return "/tmp/state.json.tmp.FAIL01" end,
    open = function()
      return {
        write = function()
          return nil, "disk full"
        end,
        close = function()
          return true
        end,
      }
    end,
    rename = function() return true end,
    remove = function(path)
      removed = path
      return true
    end,
  }

  local ok, err = atomic_write.write("/tmp/state.json", "payload", runtime)

  testlib.eq(ok, nil)
  testlib.truthy(err:match("disk full"))
  testlib.eq(removed, "/tmp/state.json.tmp.FAIL01")
end)

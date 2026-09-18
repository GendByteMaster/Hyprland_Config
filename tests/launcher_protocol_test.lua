local testlib = require("tests.testlib")
local test = testlib.test

test("launcher protocol success envelope is version one", function()
  local protocol = require("workstation.launcher_protocol")
  local payload = protocol.success({ projects = {} })
  testlib.eq(payload.version, 1)
  testlib.eq(payload.ok, true)
  testlib.truthy(type(payload.data) == "table")
  testlib.eq(payload.error, nil)
end)

test("launcher protocol failure envelope is version one", function()
  local protocol = require("workstation.launcher_protocol")
  local payload = protocol.failure("missing project")
  testlib.eq(payload.version, 1)
  testlib.eq(payload.ok, false)
  testlib.eq(payload.data, nil)
  testlib.eq(payload.error, "missing project")
end)

test("launcher protocol encodes parseable JSON", function()
  local protocol = require("workstation.launcher_protocol")
  local json = require("workstation.json")
  local encoded = protocol.encode(protocol.success({
    projects = {
      { id = "/repo/a", name = "A" },
    },
  }))
  local decoded, err = json.decode(encoded)
  testlib.eq(err, nil)
  testlib.eq(decoded.version, 1)
  testlib.eq(decoded.ok, true)
  testlib.eq(decoded.data.projects[1].id, "/repo/a")
end)

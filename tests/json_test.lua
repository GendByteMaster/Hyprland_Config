local testlib = require("tests.testlib")
local test = testlib.test

test("command argv quotes every argument", function()
  local command = require("workstation.command")
  testlib.eq(
    command.argv({ "printf", "%s", "/tmp/My Project;touch /tmp/pwn" }),
    "'printf' '%s' '/tmp/My Project;touch /tmp/pwn'"
  )
end)

test("json round trips launcher payload", function()
  local json = require("workstation.json")
  local encoded = json.encode({
    version = 1,
    ok = true,
    projects = {
      { id = "/tmp/a", name = "A" },
    },
  })

  local decoded, err = json.decode(encoded)
  testlib.eq(err, nil)
  testlib.eq(decoded.version, 1)
  testlib.eq(decoded.ok, true)
  testlib.eq(decoded.projects[1].id, "/tmp/a")
  testlib.eq(decoded.projects[1].name, "A")
end)

test("json preserves string escapes and null sentinel", function()
  local json = require("workstation.json")
  local decoded, err = json.decode('{"message":"line\\nquote:\\\"","missing":null}')
  testlib.eq(err, nil)
  testlib.eq(decoded.message, "line\nquote:\"")
  testlib.truthy(decoded.missing == json.null)
end)

test("json rejects trailing executable text", function()
  local json = require("workstation.json")
  local value, err = json.decode('{"ok":true} os.execute("touch /tmp/pwn")')
  testlib.eq(value, nil)
  testlib.truthy(err)
end)

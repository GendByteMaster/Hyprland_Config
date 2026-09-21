local testlib = require("tests.testlib")
local test = testlib.test
local toml = require("workstation.toml")

test("toml decodes project config tables and arrays of tables", function()
  local value, err = toml.decode([=[
roots = [
  "~/Repository",
  "~/Projects",
]
hidden = ["~/Repository/archive"]
max_depth = 3

[[projects]]
path = "~/scratch/demo"
name = "Demo"

[apps]
terminal = "ghostty"
editor = ["code", "--reuse-window"]

[monitors]
primary = "DP-1"

[[overrides."~/Repository/demo".actions]]
id = "custom-dev"
label = "Custom Dev"
argv = ["pnpm", "dev"]
terminal = true
confirm = true

[[overrides."~/Repository/demo".workspace.targets]]
name = "editor"
workspace = 1
monitor = "primary"
operation = "editor"
singleton = true
wait_ms = 900
match.class = "Code"
match.title = "Demo"
]=])

  testlib.eq(err, nil)
  testlib.eq(value.roots[1], "~/Repository")
  testlib.eq(value.roots[2], "~/Projects")
  testlib.eq(value.hidden[1], "~/Repository/archive")
  testlib.eq(value.max_depth, 3)
  testlib.eq(value.projects[1].path, "~/scratch/demo")
  testlib.eq(value.projects[1].name, "Demo")
  testlib.eq(value.apps.terminal, "ghostty")
  testlib.eq(value.apps.editor[2], "--reuse-window")
  testlib.eq(value.monitors.primary, "DP-1")

  local override = value.overrides["~/Repository/demo"]
  testlib.eq(override.actions[1].id, "custom-dev")
  testlib.eq(override.actions[1].terminal, true)
  testlib.eq(override.workspace.targets[1].singleton, true)
  testlib.eq(override.workspace.targets[1].match.class, "Code")
  testlib.eq(override.workspace.targets[1].match.title, "Demo")
end)

test("toml treats comments and hash characters inside strings correctly", function()
  local value, err = toml.decode([[
roots = ["~/Repo#1"] # real comment
[monitors]
primary = 'DP-1#dock'
]])

  testlib.eq(err, nil)
  testlib.eq(value.roots[1], "~/Repo#1")
  testlib.eq(value.monitors.primary, "DP-1#dock")
end)

test("toml rejects unsupported executable syntax instead of evaluating it", function()
  local value, err = toml.decode([[
roots = ["~/Repository"]
payload = os.execute("touch /tmp/pwn")
]])

  testlib.eq(value, nil)
  testlib.truthy(err)
  testlib.truthy(err:match("unsupported value type"))
end)

test("toml rejects duplicate keys", function()
  local value, err = toml.decode([[
max_depth = 3
max_depth = 4
]])

  testlib.eq(value, nil)
  testlib.truthy(err:match("duplicate key"))
end)

test("toml rejects mixed type arrays", function()
  local value, err = toml.decode([=[roots = ["~/Repository", 42]]=])

  testlib.eq(value, nil)
  testlib.truthy(err:match("mixed%-type"))
end)

test("toml enforces input size bound", function()
  local value, err = toml.decode("x = \"" .. string.rep("a", 262145) .. "\"")

  testlib.eq(value, nil)
  testlib.truthy(err:match("256 KiB"))
end)

local t = require("tests.testlib")
local installer = require("workstation.installer")
local verifier = require("workstation.verifier")
local command = require("workstation.command")
local paths = require("workstation.paths")

local function temp_dir(label)
  local path = os.tmpname() .. "-" .. label
  os.remove(path)
  assert(command.mkdir_p(path))
  return path
end

local function write(path, content)
  assert(command.mkdir_p(paths.dirname(path)))
  local file = assert(io.open(path, "w"))
  file:write(content or "")
  file:close()
end

local function fake_repo(root)
  write(paths.join(root, "hypr", "bindings.lua"), "-- managed\n")
  write(paths.join(root, "hypr", "workstation", "mouse.lua"), "return {}\n")
  write(paths.join(root, "hypr", "workstation", "mouse_state.lua"), "return {}\n")
  write(paths.join(root, "install.lua"), "return true\n")
  write(paths.join(root, "uninstall.lua"), "return true\n")
  write(paths.join(root, "verify.lua"), "return true\n")
end

local function fake_runtime()
  return {
    command_exists = function() return true end,
    syntax_check = function() return true end,
  }
end

local function check(result, name)
  for _, item in ipairs(result.checks) do
    if item.name == name then return item end
  end
end

t.test("verifier accepts a consistent installation", function()
  local root = temp_dir("verify-ok")
  local home = paths.join(root, "home")
  local repo = paths.join(root, "repo")
  fake_repo(repo)
  installer.install({ home = home, repo_root = repo, timestamp = "backup" })

  local result = verifier.verify({ home = home, repo_root = repo, runtime = fake_runtime() })
  t.eq(result.ok, true)
  t.eq(check(result, "bindings link").ok, true)
  t.eq(check(result, "workstation link").ok, true)
  t.eq(check(result, "Lua syntax").ok, true)

  command.remove_tree(root)
end)

t.test("verifier reports a misdirected managed link", function()
  local root = temp_dir("verify-bad-link")
  local home = paths.join(root, "home")
  local repo = paths.join(root, "repo")
  local other = paths.join(root, "other")
  fake_repo(repo)
  write(paths.join(other, "mouse.lua"), "return {}\n")
  installer.install({ home = home, repo_root = repo, timestamp = "backup" })

  local workstation = paths.join(home, ".config", "hypr", "workstation")
  assert(command.remove(workstation))
  assert(command.symlink(other, workstation))

  local result = verifier.verify({ home = home, repo_root = repo, runtime = fake_runtime() })
  t.eq(result.ok, false)
  t.eq(check(result, "workstation link").ok, false)

  command.remove_tree(root)
end)

t.test("verifier reports missing Lua runtime", function()
  local root = temp_dir("verify-runtime")
  local home = paths.join(root, "home")
  local repo = paths.join(root, "repo")
  fake_repo(repo)
  installer.install({ home = home, repo_root = repo, timestamp = "backup" })

  local runtime = fake_runtime()
  runtime.command_exists = function(name) return name ~= "luac5.1" end
  local result = verifier.verify({ home = home, repo_root = repo, runtime = runtime })
  t.eq(result.ok, false)
  t.eq(check(result, "luac5.1").ok, false)

  command.remove_tree(root)
end)

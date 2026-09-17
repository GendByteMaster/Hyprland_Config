local t = require("tests.testlib")
local installer = require("workstation.installer")
local uninstaller = require("workstation.uninstaller")
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

local function read(path)
  local file = assert(io.open(path, "r"))
  local content = file:read("*a")
  file:close()
  return content
end

local function fake_repo(root)
  write(paths.join(root, "hypr", "bindings.lua"), "-- managed bindings\n")
  write(paths.join(root, "hypr", "workstation", "mouse.lua"), "return {}\n")
end

t.test("uninstall restores preserved configuration", function()
  local root = temp_dir("uninstall")
  local home = paths.join(root, "home")
  local repo = paths.join(root, "repo")
  fake_repo(repo)
  write(paths.join(home, ".config", "hypr", "bindings.lua"), "-- original\n")
  write(paths.join(home, ".config", "hypr", "workstation", "local.lua"), "return true\n")
  installer.install({ home = home, repo_root = repo, timestamp = "backup" })

  local result = uninstaller.uninstall({ home = home })
  t.truthy(result.changed)
  t.eq(command.is_symlink(paths.join(home, ".config", "hypr", "bindings.lua")), false)
  t.eq(read(paths.join(home, ".config", "hypr", "bindings.lua")), "-- original\n")
  t.eq(read(paths.join(home, ".config", "hypr", "workstation", "local.lua")), "return true\n")
  t.eq(command.exists(paths.join(home, ".local", "state", "hyprland_config", "active.state")), false)
  t.eq(command.exists_or_symlink(paths.join(home, ".local", "state", "hyprland_config", "preserved_bindings.lua")), false)

  command.remove_tree(root)
end)

t.test("uninstall without active state is harmless", function()
  local root = temp_dir("no-state")
  local result = uninstaller.uninstall({ home = paths.join(root, "home") })
  t.eq(result.changed, false)
  command.remove_tree(root)
end)

t.test("uninstall aborts before deleting an unrelated replacement", function()
  local root = temp_dir("uninstall-conflict")
  local home = paths.join(root, "home")
  local repo = paths.join(root, "repo")
  fake_repo(repo)
  installer.install({ home = home, repo_root = repo, timestamp = "backup" })

  local bindings = paths.join(home, ".config", "hypr", "bindings.lua")
  assert(command.remove(bindings))
  write(bindings, "-- keep me\n")

  local ok = pcall(function()
    uninstaller.uninstall({ home = home })
  end)
  t.eq(ok, false)
  t.eq(read(bindings), "-- keep me\n")
  t.truthy(command.is_symlink(paths.join(home, ".config", "hypr", "workstation")))

  command.remove_tree(root)
end)

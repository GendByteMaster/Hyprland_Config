local t = require("tests.testlib")
local installer = require("workstation.installer")
local install_state = require("workstation.install_state")
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
  write(paths.join(root, "omarchy", "plugins", "gendbyte.mouse-hud", "manifest.json"), "{}\n")
  write(paths.join(root, "omarchy", "plugins", "gendbyte.mouse-hud", "Panel.qml"), "import QtQuick\nItem {}\n")
end

t.test("fresh install creates Hyprland and HUD plugin links", function()
  local root = temp_dir("fresh")
  local home = paths.join(root, "home")
  local repo = paths.join(root, "repo")
  fake_repo(repo)

  local result = installer.install({ home = home, repo_root = repo, timestamp = "20260917-120000" })
  t.truthy(result.changed)
  t.eq(command.realpath(paths.join(home, ".config", "hypr", "bindings.lua")), command.realpath(paths.join(repo, "hypr", "bindings.lua")))
  t.eq(command.realpath(paths.join(home, ".config", "hypr", "workstation")), command.realpath(paths.join(repo, "hypr", "workstation")))
  t.eq(command.realpath(paths.join(home, ".config", "omarchy", "plugins", "gendbyte.mouse-hud")), command.realpath(paths.join(repo, "omarchy", "plugins", "gendbyte.mouse-hud")))

  local state = assert(install_state.read(paths.join(home, ".local", "state", "hyprland_config", "active.state")))
  t.eq(state.repo_root, command.realpath(repo))
  t.eq(state.preserved_bindings, false)
  t.eq(state.preserved_workstation, false)
  t.eq(command.exists(paths.join(home, ".local", "state", "hyprland_config", "preserved_bindings.lua")), false)

  command.remove_tree(root)
end)

t.test("install preserves existing bindings and workstation directory", function()
  local root = temp_dir("preserve")
  local home = paths.join(root, "home")
  local repo = paths.join(root, "repo")
  fake_repo(repo)
  write(paths.join(home, ".config", "hypr", "bindings.lua"), "-- original bindings\n")
  write(paths.join(home, ".config", "hypr", "workstation", "local.lua"), "return 'local'\n")

  local result = installer.install({ home = home, repo_root = repo, timestamp = "20260917-120100" })
  local state = assert(install_state.read(result.state_path))
  t.truthy(state.preserved_bindings)
  t.truthy(state.preserved_workstation)
  t.eq(read(paths.join(state.backup_dir, "hypr", "bindings.lua")), "-- original bindings\n")
  t.eq(read(paths.join(state.backup_dir, "hypr", "workstation", "local.lua")), "return 'local'\n")
  t.eq(command.realpath(paths.join(home, ".local", "state", "hyprland_config", "preserved_bindings.lua")), command.realpath(paths.join(state.backup_dir, "hypr", "bindings.lua")))

  command.remove_tree(root)
end)

t.test("second install is idempotent and keeps the first backup", function()
  local root = temp_dir("idempotent")
  local home = paths.join(root, "home")
  local repo = paths.join(root, "repo")
  fake_repo(repo)
  write(paths.join(home, ".config", "hypr", "bindings.lua"), "-- original\n")

  local first = installer.install({ home = home, repo_root = repo, timestamp = "first" })
  local first_state = assert(install_state.read(first.state_path))
  local second = installer.install({ home = home, repo_root = repo, timestamp = "second" })
  local second_state = assert(install_state.read(second.state_path))

  t.eq(second.changed, false)
  t.eq(second_state.backup_dir, first_state.backup_dir)
  t.eq(command.exists(paths.join(home, ".local", "state", "hyprland_config", "backups", "second")), false)

  command.remove_tree(root)
end)

t.test("installer adds missing HUD link to an existing active install", function()
  local root = temp_dir("hud-migration")
  local home = paths.join(root, "home")
  local repo = paths.join(root, "repo")
  fake_repo(repo)
  installer.install({ home = home, repo_root = repo, timestamp = "first" })

  local hud_target = paths.join(home, ".config", "omarchy", "plugins", "gendbyte.mouse-hud")
  assert(command.remove(hud_target))
  local result = installer.install({ home = home, repo_root = repo, timestamp = "second" })

  t.truthy(result.changed)
  t.eq(command.realpath(hud_target), command.realpath(paths.join(repo, "omarchy", "plugins", "gendbyte.mouse-hud")))
  command.remove_tree(root)
end)

t.test("installer refuses to replace an unrelated HUD plugin", function()
  local root = temp_dir("hud-conflict")
  local home = paths.join(root, "home")
  local repo = paths.join(root, "repo")
  fake_repo(repo)
  write(paths.join(home, ".config", "omarchy", "plugins", "gendbyte.mouse-hud", "manifest.json"), "{\"id\":\"other\"}\n")

  local ok = pcall(function()
    installer.install({ home = home, repo_root = repo, timestamp = "first" })
  end)
  t.eq(ok, false)
  t.eq(read(paths.join(home, ".config", "omarchy", "plugins", "gendbyte.mouse-hud", "manifest.json")), "{\"id\":\"other\"}\n")
  command.remove_tree(root)
end)

t.test("installer aborts when active managed target was replaced", function()
  local root = temp_dir("conflict")
  local home = paths.join(root, "home")
  local repo = paths.join(root, "repo")
  fake_repo(repo)
  installer.install({ home = home, repo_root = repo, timestamp = "first" })

  local bindings = paths.join(home, ".config", "hypr", "bindings.lua")
  assert(command.remove(bindings))
  write(bindings, "-- unrelated replacement\n")

  local ok = pcall(function()
    installer.install({ home = home, repo_root = repo, timestamp = "second" })
  end)
  t.eq(ok, false)
  t.eq(read(bindings), "-- unrelated replacement\n")

  command.remove_tree(root)
end)

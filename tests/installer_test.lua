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
  write(paths.join(root, "hypr", "workstation", "project_launcher.lua"), "return {}\n")
  write(paths.join(root, "bin", "hyprland-workstation-launcher"), "#!/usr/bin/env bash\nexit 0\n")
  write(paths.join(root, "quickshell", "gendbyte-project-launcher", "shell.qml"), "import Quickshell\nShellRoot {}\n")
  write(paths.join(root, "quickshell", "gendbyte-project-launcher", "ProjectLauncher.qml"), "import Quickshell\nFloatingWindow {}\n")
  write(paths.join(root, "project-launcher.lua"), "return true\n")
  write(paths.join(root, "omarchy", "plugins", "gendbyte.mouse-hud", "manifest.json"), "{}\n")
  write(paths.join(root, "omarchy", "plugins", "gendbyte.mouse-hud", "Panel.qml"), "import QtQuick\nItem {}\n")
  write(paths.join(root, "omarchy", "plugins", "gendbyte.system-monitor", "manifest.json"), "{}\n")
  write(paths.join(root, "omarchy", "plugins", "gendbyte.system-monitor", "Service.qml"), "import QtQuick\nItem {}\n")
  write(paths.join(root, "omarchy", "plugins", "gendbyte.system-monitor", "BarWidget.qml"), "import QtQuick\nItem {}\n")
  write(paths.join(root, "omarchy", "plugins", "gendbyte.system-monitor", "ServiceHost.js"), "function hostedService() {}\n")
  write(paths.join(root, "omarchy", "plugins", "gendbyte.system-monitor", "telemetry-collector.lua"), "return true\n")
end

local function fake_omarchy_runtime(calls, options)
  calls = calls or {}
  options = options or {}
  return {
    available = function()
      return options.available ~= false
    end,
    enable_plugin = function(id, section)
      calls[#calls + 1] = { action = "enable", id = id, section = section }
      return options.enable_ok ~= false
    end,
    disable_plugin = function(id)
      calls[#calls + 1] = { action = "disable", id = id }
      return true
    end,
  }
end

local function fake_generic_runtime()
  return {
    command_exists = function()
      return true
    end,
  }
end

local function install(options, runtime)
  options.runtime = options.runtime or fake_generic_runtime()
  options.omarchy_runtime = runtime or fake_omarchy_runtime()
  return installer.install(options)
end

t.test("fresh install creates Hyprland HUD and system monitor links", function()
  local root = temp_dir("fresh")
  local home = paths.join(root, "home")
  local repo = paths.join(root, "repo")
  local calls = {}
  fake_repo(repo)

  local result = install({ home = home, repo_root = repo, timestamp = "20260917-120000" }, fake_omarchy_runtime(calls))
  t.truthy(result.changed)
  t.eq(command.realpath(paths.join(home, ".config", "hypr", "bindings.lua")), command.realpath(paths.join(repo, "hypr", "bindings.lua")))
  t.eq(command.realpath(paths.join(home, ".config", "hypr", "workstation")), command.realpath(paths.join(repo, "hypr", "workstation")))
  t.eq(command.realpath(paths.join(home, ".config", "omarchy", "plugins", "gendbyte.mouse-hud")), command.realpath(paths.join(repo, "omarchy", "plugins", "gendbyte.mouse-hud")))
  t.eq(command.realpath(paths.join(home, ".config", "omarchy", "plugins", "gendbyte.system-monitor")), command.realpath(paths.join(repo, "omarchy", "plugins", "gendbyte.system-monitor")))
  t.eq(#calls, 1)
  t.eq(calls[1].action, "enable")
  t.eq(calls[1].id, "gendbyte.system-monitor")
  t.eq(calls[1].section, "right")

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

  local result = install({ home = home, repo_root = repo, timestamp = "20260917-120100" })
  local state = assert(install_state.read(result.state_path))
  t.truthy(state.preserved_bindings)
  t.truthy(state.preserved_workstation)
  t.eq(read(paths.join(state.backup_dir, "hypr", "bindings.lua")), "-- original bindings\n")
  t.eq(read(paths.join(state.backup_dir, "hypr", "workstation", "local.lua")), "return 'local'\n")
  t.eq(command.realpath(paths.join(home, ".local", "state", "hyprland_config", "preserved_bindings.lua")), command.realpath(paths.join(state.backup_dir, "hypr", "bindings.lua")))

  command.remove_tree(root)
end)

t.test("second install is idempotent and enables system monitor only once", function()
  local root = temp_dir("idempotent")
  local home = paths.join(root, "home")
  local repo = paths.join(root, "repo")
  local calls = {}
  local runtime = fake_omarchy_runtime(calls)
  fake_repo(repo)
  write(paths.join(home, ".config", "hypr", "bindings.lua"), "-- original\n")

  local first = install({ home = home, repo_root = repo, timestamp = "first" }, runtime)
  local first_state = assert(install_state.read(first.state_path))
  local second = install({ home = home, repo_root = repo, timestamp = "second" }, runtime)
  local second_state = assert(install_state.read(second.state_path))

  t.eq(second.changed, false)
  t.eq(second_state.backup_dir, first_state.backup_dir)
  t.eq(command.exists(paths.join(home, ".local", "state", "hyprland_config", "backups", "second")), false)
  t.eq(#calls, 1)

  command.remove_tree(root)
end)

t.test("installer adds missing HUD link to an existing active install", function()
  local root = temp_dir("hud-migration")
  local home = paths.join(root, "home")
  local repo = paths.join(root, "repo")
  fake_repo(repo)
  install({ home = home, repo_root = repo, timestamp = "first" })

  local hud_target = paths.join(home, ".config", "omarchy", "plugins", "gendbyte.mouse-hud")
  assert(command.remove(hud_target))
  local result = install({ home = home, repo_root = repo, timestamp = "second" })

  t.truthy(result.changed)
  t.eq(command.realpath(hud_target), command.realpath(paths.join(repo, "omarchy", "plugins", "gendbyte.mouse-hud")))
  command.remove_tree(root)
end)

t.test("installer adds and enables a missing system monitor link", function()
  local root = temp_dir("monitor-migration")
  local home = paths.join(root, "home")
  local repo = paths.join(root, "repo")
  local calls = {}
  local runtime = fake_omarchy_runtime(calls)
  fake_repo(repo)
  install({ home = home, repo_root = repo, timestamp = "first" }, runtime)

  local target = paths.join(home, ".config", "omarchy", "plugins", "gendbyte.system-monitor")
  assert(command.remove(target))
  calls = {}
  runtime = fake_omarchy_runtime(calls)
  local result = install({ home = home, repo_root = repo, timestamp = "second" }, runtime)

  t.truthy(result.changed)
  t.eq(command.realpath(target), command.realpath(paths.join(repo, "omarchy", "plugins", "gendbyte.system-monitor")))
  t.eq(#calls, 1)
  t.eq(calls[1].action, "enable")
  command.remove_tree(root)
end)

t.test("installer refuses to replace an unrelated HUD plugin", function()
  local root = temp_dir("hud-conflict")
  local home = paths.join(root, "home")
  local repo = paths.join(root, "repo")
  fake_repo(repo)
  write(paths.join(home, ".config", "omarchy", "plugins", "gendbyte.mouse-hud", "manifest.json"), "{\"id\":\"other\"}\n")

  local ok = pcall(function()
    install({ home = home, repo_root = repo, timestamp = "first" })
  end)
  t.eq(ok, false)
  t.eq(read(paths.join(home, ".config", "omarchy", "plugins", "gendbyte.mouse-hud", "manifest.json")), "{\"id\":\"other\"}\n")
  command.remove_tree(root)
end)

t.test("installer refuses to replace an unrelated system monitor plugin", function()
  local root = temp_dir("monitor-conflict")
  local home = paths.join(root, "home")
  local repo = paths.join(root, "repo")
  fake_repo(repo)
  write(paths.join(home, ".config", "omarchy", "plugins", "gendbyte.system-monitor", "manifest.json"), "{\"id\":\"other\"}\n")

  local ok = pcall(function()
    install({ home = home, repo_root = repo, timestamp = "first" })
  end)
  t.eq(ok, false)
  t.eq(read(paths.join(home, ".config", "omarchy", "plugins", "gendbyte.system-monitor", "manifest.json")), "{\"id\":\"other\"}\n")
  command.remove_tree(root)
end)

t.test("installer rolls back when Omarchy cannot enable the system monitor", function()
  local root = temp_dir("monitor-enable-failure")
  local home = paths.join(root, "home")
  local repo = paths.join(root, "repo")
  fake_repo(repo)
  write(paths.join(home, ".config", "omarchy", "shell.json"), "{\"keep\":true}\n")

  local ok = pcall(function()
    install({ home = home, repo_root = repo, timestamp = "first" }, fake_omarchy_runtime({}, { enable_ok = false }))
  end)
  t.eq(ok, false)
  t.eq(command.exists_or_symlink(paths.join(home, ".config", "omarchy", "plugins", "gendbyte.system-monitor")), false)
  t.eq(command.exists_or_symlink(paths.join(home, ".config", "hypr", "bindings.lua")), false)
  t.eq(command.exists(paths.join(home, ".local", "state", "hyprland_config", "active.state")), false)
  t.eq(read(paths.join(home, ".config", "omarchy", "shell.json")), "{\"keep\":true}\n")
  command.remove_tree(root)
end)

t.test("installer disables system monitor when state write fails after enable", function()
  local root = temp_dir("state-write-failure")
  local home = paths.join(root, "home")
  local repo = paths.join(root, "repo")
  local calls = {}
  fake_repo(repo)

  local original_write = install_state.write
  install_state.write = function()
    error("forced state write failure")
  end

  local ok, err = pcall(function()
    install(
      { home = home, repo_root = repo, timestamp = "first" },
      fake_omarchy_runtime(calls)
    )
  end)

  install_state.write = original_write

  t.eq(ok, false)
  t.truthy(tostring(err):match("forced state write failure"))
  t.eq(#calls, 2)
  t.eq(calls[1].action, "enable")
  t.eq(calls[1].id, "gendbyte.system-monitor")
  t.eq(calls[2].action, "disable")
  t.eq(calls[2].id, "gendbyte.system-monitor")
  t.eq(
    command.exists_or_symlink(
      paths.join(home, ".config", "omarchy", "plugins", "gendbyte.system-monitor")
    ),
    false
  )
  t.eq(
    command.exists(paths.join(home, ".local", "state", "hyprland_config", "active.state")),
    false
  )

  command.remove_tree(root)
end)

t.test("installer aborts when active managed target was replaced", function()
  local root = temp_dir("conflict")
  local home = paths.join(root, "home")
  local repo = paths.join(root, "repo")
  fake_repo(repo)
  install({ home = home, repo_root = repo, timestamp = "first" })

  local bindings = paths.join(home, ".config", "hypr", "bindings.lua")
  assert(command.remove(bindings))
  write(bindings, "-- unrelated replacement\n")

  local ok = pcall(function()
    install({ home = home, repo_root = repo, timestamp = "second" })
  end)
  t.eq(ok, false)
  t.eq(read(bindings), "-- unrelated replacement\n")

  command.remove_tree(root)
end)
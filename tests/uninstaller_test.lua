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
  write(paths.join(root, "hypr", "workstation", "project_launcher.lua"), "return {}\n")
  write(paths.join(root, "bin", "hyprland-workstation-launcher"), "#!/usr/bin/env bash\nexit 0\n")
  write(paths.join(root, "quickshell", "gendbyte-project-launcher", "shell.qml"), "import Quickshell\nShellRoot {}\n")
  write(paths.join(root, "quickshell", "gendbyte-project-launcher", "ProjectLauncher.qml"), "import Quickshell\nFloatingWindow {}\n")
  write(paths.join(root, "project-launcher.lua"), "return true\n")
  write(paths.join(root, "hypr", "workstation", "workspace_overview.lua"), "return {}\n")
  write(paths.join(root, "bin", "hyprland-workspace-overview"), "#!/usr/bin/env bash\nexit 0\n")
  write(paths.join(root, "quickshell", "gendbyte-workspace-overview", "shell.qml"), "import Quickshell\nShellRoot {}\n")
  write(paths.join(root, "quickshell", "gendbyte-workspace-overview", "Overview.qml"), "import QtQuick\nItem {}\n")
  write(paths.join(root, "quickshell", "gendbyte-workspace-overview", "components", "WindowPreview.qml"), "import QtQuick\nItem {}\n")
  write(paths.join(root, "quickshell", "gendbyte-workspace-overview", "components", "WorkspaceStrip.qml"), "import QtQuick\nItem {}\n")
  write(paths.join(root, "lua", "workstation", "overview_model.lua"), "return {}\n")
  write(paths.join(root, "omarchy", "plugins", "gendbyte.mouse-hud", "manifest.json"), "{}\n")
  write(paths.join(root, "omarchy", "plugins", "gendbyte.mouse-hud", "Panel.qml"), "import QtQuick\nItem {}\n")
  write(paths.join(root, "omarchy", "plugins", "gendbyte.system-monitor", "manifest.json"), "{}\n")
  write(paths.join(root, "omarchy", "plugins", "gendbyte.system-monitor", "Service.qml"), "import QtQuick\nItem {}\n")
  write(paths.join(root, "omarchy", "plugins", "gendbyte.system-monitor", "BarWidget.qml"), "import QtQuick\nItem {}\n")
  write(paths.join(root, "omarchy", "plugins", "gendbyte.system-monitor", "ServiceHost.js"), "function hostedService() {}\n")
  write(paths.join(root, "omarchy", "plugins", "gendbyte.system-monitor", "telemetry-collector.lua"), "return true\n")
end

local function fake_runtime(calls, options)
  calls = calls or {}
  options = options or {}
  return {
    available = function() return options.available ~= false end,
    enable_plugin = function(id, section)
      calls[#calls + 1] = { action = "enable", id = id, section = section }
      return true
    end,
    disable_plugin = function(id)
      calls[#calls + 1] = { action = "disable", id = id }
      return options.disable_ok ~= false
    end,
  }
end

local function generic_runtime()
  return {
    command_exists = function()
      return true
    end,
  }
end

local function install(options)
  options.runtime = generic_runtime()
  options.omarchy_runtime = fake_runtime()
  return installer.install(options)
end

local function install_generic(options)
  options.runtime = generic_runtime()
  options.omarchy_runtime = fake_runtime({}, { available = false })
  return installer.install(options)
end

t.test("uninstall restores configuration and removes project plugins", function()
  local root = temp_dir("uninstall")
  local home = paths.join(root, "home")
  local repo = paths.join(root, "repo")
  local calls = {}
  fake_repo(repo)
  write(paths.join(home, ".config", "hypr", "bindings.lua"), "-- original\n")
  write(paths.join(home, ".config", "hypr", "workstation", "local.lua"), "return true\n")
  install({ home = home, repo_root = repo, timestamp = "backup" })

  local result = uninstaller.uninstall({ home = home, omarchy_runtime = fake_runtime(calls) })
  t.truthy(result.changed)
  t.eq(command.is_symlink(paths.join(home, ".config", "hypr", "bindings.lua")), false)
  t.eq(read(paths.join(home, ".config", "hypr", "bindings.lua")), "-- original\n")
  t.eq(read(paths.join(home, ".config", "hypr", "workstation", "local.lua")), "return true\n")
  t.eq(command.exists_or_symlink(paths.join(home, ".config", "omarchy", "plugins", "gendbyte.mouse-hud")), false)
  t.eq(command.exists_or_symlink(paths.join(home, ".config", "omarchy", "plugins", "gendbyte.system-monitor")), false)
  t.eq(command.exists(paths.join(home, ".local", "state", "hyprland_config", "active.state")), false)
  t.eq(command.exists_or_symlink(paths.join(home, ".local", "state", "hyprland_config", "preserved_bindings.lua")), false)
  t.eq(#calls, 1)
  t.eq(calls[1].action, "disable")
  t.eq(calls[1].id, "gendbyte.system-monitor")

  command.remove_tree(root)
end)

t.test("uninstall without active state is harmless", function()
  local root = temp_dir("no-state")
  local result = uninstaller.uninstall({ home = paths.join(root, "home"), omarchy_runtime = fake_runtime() })
  t.eq(result.changed, false)
  command.remove_tree(root)
end)

t.test("uninstall tolerates a missing system monitor from legacy install state", function()
  local root = temp_dir("legacy-no-monitor")
  local home = paths.join(root, "home")
  local repo = paths.join(root, "repo")
  local calls = {}
  fake_repo(repo)
  install({ home = home, repo_root = repo, timestamp = "backup" })

  local monitor = paths.join(home, ".config", "omarchy", "plugins", "gendbyte.system-monitor")
  assert(command.remove(monitor))

  local result = uninstaller.uninstall({ home = home, omarchy_runtime = fake_runtime(calls) })
  t.truthy(result.changed)
  t.eq(#calls, 0)
  t.eq(command.exists(paths.join(home, ".local", "state", "hyprland_config", "active.state")), false)
  t.eq(command.exists_or_symlink(paths.join(home, ".config", "omarchy", "plugins", "gendbyte.mouse-hud")), false)

  command.remove_tree(root)
end)

t.test("uninstall aborts before deleting an unrelated replacement", function()
  local root = temp_dir("uninstall-conflict")
  local home = paths.join(root, "home")
  local repo = paths.join(root, "repo")
  fake_repo(repo)
  install({ home = home, repo_root = repo, timestamp = "backup" })

  local bindings = paths.join(home, ".config", "hypr", "bindings.lua")
  assert(command.remove(bindings))
  write(bindings, "-- keep me\n")

  local ok = pcall(function()
    uninstaller.uninstall({ home = home, omarchy_runtime = fake_runtime() })
  end)
  t.eq(ok, false)
  t.eq(read(bindings), "-- keep me\n")
  t.truthy(command.is_symlink(paths.join(home, ".config", "hypr", "workstation")))
  t.truthy(command.is_symlink(paths.join(home, ".config", "omarchy", "plugins", "gendbyte.mouse-hud")))
  t.truthy(command.is_symlink(paths.join(home, ".config", "omarchy", "plugins", "gendbyte.system-monitor")))

  command.remove_tree(root)
end)

t.test("uninstall refuses to remove a replaced HUD plugin", function()
  local root = temp_dir("hud-replaced")
  local home = paths.join(root, "home")
  local repo = paths.join(root, "repo")
  fake_repo(repo)
  install({ home = home, repo_root = repo, timestamp = "backup" })

  local hud = paths.join(home, ".config", "omarchy", "plugins", "gendbyte.mouse-hud")
  assert(command.remove(hud))
  write(paths.join(hud, "manifest.json"), "{\"id\":\"replacement\"}\n")

  local ok = pcall(function()
    uninstaller.uninstall({ home = home, omarchy_runtime = fake_runtime() })
  end)
  t.eq(ok, false)
  t.eq(read(paths.join(hud, "manifest.json")), "{\"id\":\"replacement\"}\n")
  command.remove_tree(root)
end)

t.test("uninstall refuses to remove a replaced system monitor plugin", function()
  local root = temp_dir("monitor-replaced")
  local home = paths.join(root, "home")
  local repo = paths.join(root, "repo")
  fake_repo(repo)
  install({ home = home, repo_root = repo, timestamp = "backup" })

  local monitor = paths.join(home, ".config", "omarchy", "plugins", "gendbyte.system-monitor")
  assert(command.remove(monitor))
  write(paths.join(monitor, "manifest.json"), "{\"id\":\"replacement\"}\n")

  local calls = {}
  local ok = pcall(function()
    uninstaller.uninstall({ home = home, omarchy_runtime = fake_runtime(calls) })
  end)
  t.eq(ok, false)
  t.eq(read(paths.join(monitor, "manifest.json")), "{\"id\":\"replacement\"}\n")
  t.eq(#calls, 0)
  command.remove_tree(root)
end)

t.test("uninstall leaves files intact when Omarchy disable fails", function()
  local root = temp_dir("monitor-disable-failure")
  local home = paths.join(root, "home")
  local repo = paths.join(root, "repo")
  fake_repo(repo)
  install({ home = home, repo_root = repo, timestamp = "backup" })

  local ok = pcall(function()
    uninstaller.uninstall({ home = home, omarchy_runtime = fake_runtime({}, { disable_ok = false }) })
  end)
  t.eq(ok, false)
  t.truthy(command.is_symlink(paths.join(home, ".config", "hypr", "bindings.lua")))
  t.truthy(command.is_symlink(paths.join(home, ".config", "omarchy", "plugins", "gendbyte.system-monitor")))
  t.truthy(command.exists(paths.join(home, ".local", "state", "hyprland_config", "active.state")))
  command.remove_tree(root)
end)


t.test("generic uninstall removes launcher and restores Hyprland config without Omarchy", function()
  local root = temp_dir("generic-uninstall")
  local home = paths.join(root, "home")
  local repo = paths.join(root, "repo")
  local calls = {}
  fake_repo(repo)
  write(paths.join(home, ".config", "hypr", "bindings.lua"), "-- generic original\n")
  write(paths.join(home, ".config", "hypr", "workstation", "local.lua"), "return 'generic'\n")

  install_generic({ home = home, repo_root = repo, timestamp = "backup" })
  t.truthy(command.is_symlink(paths.join(home, ".local", "bin", "hyprland-workstation-launcher")))
  t.truthy(command.is_symlink(paths.join(home, ".config", "quickshell", "gendbyte-project-launcher")))
  t.eq(command.exists_or_symlink(paths.join(home, ".config", "omarchy")), false)

  local result = uninstaller.uninstall({
    home = home,
    omarchy_runtime = fake_runtime(calls, { available = false }),
  })

  t.eq(result.changed, true)
  t.eq(#calls, 0)
  t.eq(command.exists_or_symlink(paths.join(home, ".local", "bin", "hyprland-workstation-launcher")), false)
  t.eq(command.exists_or_symlink(paths.join(home, ".config", "quickshell", "gendbyte-project-launcher")), false)
  t.eq(read(paths.join(home, ".config", "hypr", "bindings.lua")), "-- generic original\n")
  t.eq(read(paths.join(home, ".config", "hypr", "workstation", "local.lua")), "return 'generic'\n")
  t.eq(command.exists_or_symlink(paths.join(home, ".local", "state", "hyprland_config", "active.state")), false)

  command.remove_tree(root)
end)

t.test("generic uninstall refuses unrelated launcher replacement before removing managed files", function()
  local root = temp_dir("generic-launcher-conflict")
  local home = paths.join(root, "home")
  local repo = paths.join(root, "repo")
  fake_repo(repo)

  install_generic({ home = home, repo_root = repo, timestamp = "backup" })

  local launcher = paths.join(home, ".local", "bin", "hyprland-workstation-launcher")
  assert(command.remove(launcher))
  write(launcher, "#!/bin/sh\necho replacement\n")

  local ok, err = pcall(function()
    uninstaller.uninstall({
      home = home,
      omarchy_runtime = fake_runtime({}, { available = false }),
    })
  end)

  t.eq(ok, false)
  t.truthy(tostring(err):lower():find("launcher", 1, true))
  t.truthy(read(launcher):find("replacement", 1, true))
  t.truthy(command.is_symlink(paths.join(home, ".config", "hypr", "bindings.lua")))
  t.truthy(command.is_symlink(paths.join(home, ".config", "quickshell", "gendbyte-project-launcher")))
  t.truthy(command.exists(paths.join(home, ".local", "state", "hyprland_config", "active.state")))

  command.remove_tree(root)
end)

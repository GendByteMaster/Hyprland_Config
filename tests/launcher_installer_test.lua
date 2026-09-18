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

local function generic_runtime(has_qs)
  return {
    command_exists = function(name)
      if name == "qs" then
        return has_qs ~= false
      end
      return true
    end,
  }
end

local function omarchy_runtime(available, calls, options)
  calls = calls or {}
  options = options or {}
  return {
    available = function()
      return available == true
    end,
    rescan_plugins = function()
      calls[#calls + 1] = { action = "rescan" }
      return options.rescan_ok ~= false
    end,
    wait_for_plugin = function(id)
      calls[#calls + 1] = { action = "wait", id = id }
      return options.discover_ok ~= false
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

local function active_state(home)
  return assert(install_state.read(paths.join(home, ".local", "state", "hyprland_config", "active.state")))
end

t.test("plain Hyprland install succeeds without Omarchy and installs managed UI", function()
  local root = temp_dir("launcher-generic")
  local home = paths.join(root, "home")
  local repo = paths.join(root, "repo")
  fake_repo(repo)

  local result = installer.install({
    home = home,
    repo_root = repo,
    timestamp = "first",
    runtime = generic_runtime(true),
    omarchy_runtime = omarchy_runtime(false),
  })

  t.eq(result.changed, true)
  t.eq(
    command.realpath(paths.join(home, ".local", "bin", "hyprland-workstation-launcher")),
    command.realpath(paths.join(repo, "bin", "hyprland-workstation-launcher"))
  )
  t.eq(
    command.realpath(paths.join(home, ".config", "quickshell", "gendbyte-project-launcher")),
    command.realpath(paths.join(repo, "quickshell", "gendbyte-project-launcher"))
  )
  t.eq(
    command.realpath(paths.join(home, ".local", "bin", "hyprland-workspace-overview")),
    command.realpath(paths.join(repo, "bin", "hyprland-workspace-overview"))
  )
  t.eq(
    command.realpath(paths.join(home, ".config", "quickshell", "gendbyte-workspace-overview")),
    command.realpath(paths.join(repo, "quickshell", "gendbyte-workspace-overview"))
  )
  t.eq(command.exists_or_symlink(paths.join(home, ".config", "omarchy")), false)

  local state = active_state(home)
  t.eq(state.version, 3)
  t.eq(state.launcher, true)
  t.eq(state.workspace_overview, true)
  t.eq(state.omarchy_hud, false)
  t.eq(state.omarchy_system_monitor, false)

  command.remove_tree(root)
end)

t.test("Omarchy install records managed components in v3 state", function()
  local root = temp_dir("launcher-omarchy")
  local home = paths.join(root, "home")
  local repo = paths.join(root, "repo")
  local calls = {}
  fake_repo(repo)

  installer.install({
    home = home,
    repo_root = repo,
    timestamp = "first",
    runtime = generic_runtime(true),
    omarchy_runtime = omarchy_runtime(true, calls),
  })

  local state = active_state(home)
  t.eq(state.version, 3)
  t.eq(state.launcher, true)
  t.eq(state.workspace_overview, true)
  t.eq(state.omarchy_hud, true)
  t.eq(state.omarchy_system_monitor, true)
  t.truthy(command.is_symlink(paths.join(home, ".config", "omarchy", "plugins", "gendbyte.mouse-hud")))
  t.truthy(command.is_symlink(paths.join(home, ".config", "omarchy", "plugins", "gendbyte.system-monitor")))

  command.remove_tree(root)
end)

t.test("installer requires qs before touching generic targets", function()
  local root = temp_dir("launcher-no-qs")
  local home = paths.join(root, "home")
  local repo = paths.join(root, "repo")
  fake_repo(repo)
  write(paths.join(home, ".config", "hypr", "bindings.lua"), "-- original\n")

  local ok, err = pcall(function()
    installer.install({
      home = home,
      repo_root = repo,
      timestamp = "first",
      runtime = generic_runtime(false),
      omarchy_runtime = omarchy_runtime(false),
    })
  end)

  t.eq(ok, false)
  t.truthy(tostring(err):lower():find("quickshell", 1, true))
  local file = assert(io.open(paths.join(home, ".config", "hypr", "bindings.lua"), "r"))
  t.eq(file:read("*a"), "-- original\n")
  file:close()
  t.eq(command.exists_or_symlink(paths.join(home, ".local", "bin", "hyprland-workstation-launcher")), false)
  t.eq(command.exists_or_symlink(paths.join(home, ".local", "state", "hyprland_config", "active.state")), false)

  command.remove_tree(root)
end)

t.test("installer refuses an unrelated launcher target", function()
  local root = temp_dir("launcher-conflict")
  local home = paths.join(root, "home")
  local repo = paths.join(root, "repo")
  fake_repo(repo)
  write(paths.join(home, ".local", "bin", "hyprland-workstation-launcher"), "#!/bin/sh\necho unrelated\n")

  local ok = pcall(function()
    installer.install({
      home = home,
      repo_root = repo,
      timestamp = "first",
      runtime = generic_runtime(true),
      omarchy_runtime = omarchy_runtime(false),
    })
  end)

  t.eq(ok, false)
  local file = assert(io.open(paths.join(home, ".local", "bin", "hyprland-workstation-launcher"), "r"))
  t.truthy(file:read("*a"):find("unrelated", 1, true))
  file:close()

  command.remove_tree(root)
end)

t.test("v1 active install upgrades in place to v3 and adds managed UI", function()
  local root = temp_dir("launcher-v1-upgrade")
  local home = paths.join(root, "home")
  local repo = paths.join(root, "repo")
  fake_repo(repo)

  -- Build a real v1-style active install with the current legacy shape.
  local config_dir = paths.join(home, ".config", "hypr")
  local plugin_dir = paths.join(home, ".config", "omarchy", "plugins")
  local state_dir = paths.join(home, ".local", "state", "hyprland_config")
  assert(command.mkdir_p(config_dir))
  assert(command.mkdir_p(plugin_dir))
  assert(command.mkdir_p(state_dir))
  assert(command.symlink(paths.join(repo, "hypr", "bindings.lua"), paths.join(config_dir, "bindings.lua")))
  assert(command.symlink(paths.join(repo, "hypr", "workstation"), paths.join(config_dir, "workstation")))
  assert(command.symlink(paths.join(repo, "omarchy", "plugins", "gendbyte.mouse-hud"), paths.join(plugin_dir, "gendbyte.mouse-hud")))
  assert(command.symlink(paths.join(repo, "omarchy", "plugins", "gendbyte.system-monitor"), paths.join(plugin_dir, "gendbyte.system-monitor")))
  install_state.write(paths.join(state_dir, "active.state"), {
    version = 1,
    repo_root = assert(command.realpath(repo)),
    backup_dir = "",
    preserved_bindings = false,
    preserved_workstation = false,
  })

  local result = installer.install({
    home = home,
    repo_root = repo,
    timestamp = "upgrade",
    runtime = generic_runtime(true),
    omarchy_runtime = omarchy_runtime(false),
  })

  t.eq(result.changed, true)
  local state = active_state(home)
  t.eq(state.version, 3)
  t.eq(state.launcher, true)
  t.eq(state.workspace_overview, true)
  t.eq(state.omarchy_hud, true)
  t.eq(state.omarchy_system_monitor, true)
  t.truthy(command.is_symlink(paths.join(plugin_dir, "gendbyte.mouse-hud")))
  t.truthy(command.is_symlink(paths.join(plugin_dir, "gendbyte.system-monitor")))
  t.truthy(command.is_symlink(paths.join(home, ".local", "bin", "hyprland-workstation-launcher")))
  t.truthy(command.is_symlink(paths.join(home, ".config", "quickshell", "gendbyte-project-launcher")))
  t.truthy(command.is_symlink(paths.join(home, ".local", "bin", "hyprland-workspace-overview")))
  t.truthy(command.is_symlink(paths.join(home, ".config", "quickshell", "gendbyte-workspace-overview")))

  command.remove_tree(root)
end)

t.test("v2 active install upgrades in place to v3 and adds workspace overview", function()
  local root = temp_dir("overview-v2-upgrade")
  local home = paths.join(root, "home")
  local repo = paths.join(root, "repo")
  fake_repo(repo)

  local config_dir = paths.join(home, ".config", "hypr")
  local state_dir = paths.join(home, ".local", "state", "hyprland_config")
  assert(command.mkdir_p(config_dir))
  assert(command.mkdir_p(state_dir))
  assert(command.mkdir_p(paths.join(home, ".local", "bin")))
  assert(command.mkdir_p(paths.join(home, ".config", "quickshell")))

  assert(command.symlink(paths.join(repo, "hypr", "bindings.lua"), paths.join(config_dir, "bindings.lua")))
  assert(command.symlink(paths.join(repo, "hypr", "workstation"), paths.join(config_dir, "workstation")))
  assert(command.symlink(
    paths.join(repo, "bin", "hyprland-workstation-launcher"),
    paths.join(home, ".local", "bin", "hyprland-workstation-launcher")
  ))
  assert(command.symlink(
    paths.join(repo, "quickshell", "gendbyte-project-launcher"),
    paths.join(home, ".config", "quickshell", "gendbyte-project-launcher")
  ))

  install_state.write(paths.join(state_dir, "active.state"), {
    version = 2,
    repo_root = assert(command.realpath(repo)),
    backup_dir = "",
    preserved_bindings = false,
    preserved_workstation = false,
    launcher = true,
    omarchy_hud = false,
    omarchy_system_monitor = false,
  })

  local result = installer.install({
    home = home,
    repo_root = repo,
    timestamp = "upgrade",
    runtime = generic_runtime(true),
    omarchy_runtime = omarchy_runtime(false),
  })

  t.eq(result.changed, true)
  local state = active_state(home)
  t.eq(state.version, 3)
  t.eq(state.workspace_overview, true)
  t.truthy(command.is_symlink(paths.join(home, ".local", "bin", "hyprland-workspace-overview")))
  t.truthy(command.is_symlink(paths.join(home, ".config", "quickshell", "gendbyte-workspace-overview")))

  command.remove_tree(root)
end)

t.test("failed optional Omarchy enable rolls back newly added managed UI on fresh install", function()
  local root = temp_dir("launcher-rollback")
  local home = paths.join(root, "home")
  local repo = paths.join(root, "repo")
  fake_repo(repo)

  local ok = pcall(function()
    installer.install({
      home = home,
      repo_root = repo,
      timestamp = "first",
      runtime = generic_runtime(true),
      omarchy_runtime = omarchy_runtime(true, {}, { enable_ok = false }),
    })
  end)

  t.eq(ok, false)
  t.eq(command.exists_or_symlink(paths.join(home, ".local", "bin", "hyprland-workstation-launcher")), false)
  t.eq(command.exists_or_symlink(paths.join(home, ".config", "quickshell", "gendbyte-project-launcher")), false)
  t.eq(command.exists_or_symlink(paths.join(home, ".local", "bin", "hyprland-workspace-overview")), false)
  t.eq(command.exists_or_symlink(paths.join(home, ".config", "quickshell", "gendbyte-workspace-overview")), false)
  t.eq(command.exists_or_symlink(paths.join(home, ".local", "state", "hyprland_config", "active.state")), false)

  command.remove_tree(root)
end)

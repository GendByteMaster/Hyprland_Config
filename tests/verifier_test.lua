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
  write(paths.join(root, "hypr", "workstation", "hud.lua"), "return {}\n")
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
  write(paths.join(root, "quickshell", "gendbyte-workspace-overview", "components", "ThemePalette.qml"), "import QtQuick\nItem {}\n")
  write(paths.join(root, "lua", "workstation", "overview_model.lua"), "return {}\n")
  write(paths.join(root, "omarchy", "plugins", "gendbyte.mouse-hud", "manifest.json"), "{}\n")
  write(paths.join(root, "omarchy", "plugins", "gendbyte.mouse-hud", "Panel.qml"), "import QtQuick\nItem {}\n")
  write(paths.join(root, "omarchy", "plugins", "gendbyte.system-monitor", "manifest.json"), "{}\n")
  write(paths.join(root, "omarchy", "plugins", "gendbyte.system-monitor", "Service.qml"), "import QtQuick\nItem {}\n")
  write(paths.join(root, "omarchy", "plugins", "gendbyte.system-monitor", "BarWidget.qml"), "import QtQuick\nItem {}\n")
  write(paths.join(root, "omarchy", "plugins", "gendbyte.system-monitor", "ServiceHost.js"), "function hostedService() {}\n")
  write(paths.join(root, "omarchy", "plugins", "gendbyte.system-monitor", "telemetry-collector.lua"), "return true\n")
  write(paths.join(root, "lua", "workstation", "telemetry.lua"), "return {}\n")
  write(paths.join(root, "lua", "workstation", "telemetry_collector.lua"), "return {}\n")
  write(paths.join(root, "telemetry-collector.lua"), "return true\n")
  write(paths.join(root, "install.lua"), "return true\n")
  write(paths.join(root, "uninstall.lua"), "return true\n")
  write(paths.join(root, "verify.lua"), "return true\n")
end

local function fake_omarchy_runtime(available)
  return {
    available = function() return available ~= false end,
    enable_plugin = function() return true end,
    disable_plugin = function() return true end,
  }
end

local function fake_runtime()
  return {
    command_exists = function() return true end,
    syntax_check = function() return true end,
    plugin_validate = function() return true end,
  }
end

local function check(result, name)
  for _, item in ipairs(result.checks) do
    if item.name == name then return item end
  end
end

local function install(options)
  options.runtime = fake_runtime()
  options.omarchy_runtime = fake_omarchy_runtime()
  return installer.install(options)
end

t.test("verifier accepts a consistent installation with project plugins", function()
  local root = temp_dir("verify-ok")
  local home = paths.join(root, "home")
  local repo = paths.join(root, "repo")
  fake_repo(repo)
  install({ home = home, repo_root = repo, timestamp = "backup" })

  local result = verifier.verify({ home = home, repo_root = repo, runtime = fake_runtime() })
  t.eq(result.ok, true)
  t.eq(check(result, "bindings link").ok, true)
  t.eq(check(result, "workstation link").ok, true)
  t.eq(check(result, "Workspace Overview wrapper link").ok, true)
  t.eq(check(result, "Workspace Overview Quickshell config link").ok, true)
  t.eq(check(result, "HUD plugin link").ok, true)
  t.eq(check(result, "system monitor plugin link").ok, true)
  t.eq(check(result, "system monitor manifest").ok, true)
  t.eq(check(result, "system monitor service").ok, true)
  t.eq(check(result, "system monitor bar widget").ok, true)
  t.eq(check(result, "system monitor service host").ok, true)
  t.eq(check(result, "system monitor collector launcher").ok, true)
  t.eq(check(result, "Omarchy CLI").ok, true)
  t.eq(check(result, "Omarchy plugin validation").ok, true)
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
  install({ home = home, repo_root = repo, timestamp = "backup" })

  local workstation = paths.join(home, ".config", "hypr", "workstation")
  assert(command.remove(workstation))
  assert(command.symlink(other, workstation))

  local result = verifier.verify({ home = home, repo_root = repo, runtime = fake_runtime() })
  t.eq(result.ok, false)
  t.eq(check(result, "workstation link").ok, false)

  command.remove_tree(root)
end)

t.test("verifier reports a misdirected HUD plugin", function()
  local root = temp_dir("verify-bad-hud")
  local home = paths.join(root, "home")
  local repo = paths.join(root, "repo")
  local other = paths.join(root, "other-hud")
  fake_repo(repo)
  write(paths.join(other, "manifest.json"), "{}\n")
  install({ home = home, repo_root = repo, timestamp = "backup" })

  local hud = paths.join(home, ".config", "omarchy", "plugins", "gendbyte.mouse-hud")
  assert(command.remove(hud))
  assert(command.symlink(other, hud))

  local result = verifier.verify({ home = home, repo_root = repo, runtime = fake_runtime() })
  t.eq(result.ok, false)
  t.eq(check(result, "HUD plugin link").ok, false)
  command.remove_tree(root)
end)

t.test("verifier reports a misdirected system monitor plugin", function()
  local root = temp_dir("verify-bad-monitor")
  local home = paths.join(root, "home")
  local repo = paths.join(root, "repo")
  local other = paths.join(root, "other-monitor")
  fake_repo(repo)
  write(paths.join(other, "manifest.json"), "{}\n")
  install({ home = home, repo_root = repo, timestamp = "backup" })

  local monitor = paths.join(home, ".config", "omarchy", "plugins", "gendbyte.system-monitor")
  assert(command.remove(monitor))
  assert(command.symlink(other, monitor))

  local result = verifier.verify({ home = home, repo_root = repo, runtime = fake_runtime() })
  t.eq(result.ok, false)
  t.eq(check(result, "system monitor plugin link").ok, false)
  command.remove_tree(root)
end)

t.test("verifier reports failed Omarchy plugin validation", function()
  local root = temp_dir("verify-plugin-validation")
  local home = paths.join(root, "home")
  local repo = paths.join(root, "repo")
  fake_repo(repo)
  install({ home = home, repo_root = repo, timestamp = "backup" })

  local runtime = fake_runtime()
  runtime.plugin_validate = function() return false end
  local result = verifier.verify({ home = home, repo_root = repo, runtime = runtime })
  t.eq(result.ok, false)
  t.eq(check(result, "Omarchy plugin validation").ok, false)
  command.remove_tree(root)
end)

t.test("verifier reports missing Lua runtime", function()
  local root = temp_dir("verify-runtime")
  local home = paths.join(root, "home")
  local repo = paths.join(root, "repo")
  fake_repo(repo)
  install({ home = home, repo_root = repo, timestamp = "backup" })

  local runtime = fake_runtime()
  runtime.command_exists = function(name) return name ~= "luac5.1" end
  local result = verifier.verify({ home = home, repo_root = repo, runtime = runtime })
  t.eq(result.ok, false)
  t.eq(check(result, "luac5.1").ok, false)

  command.remove_tree(root)
end)

t.test("generic verification passes without Omarchy and validates launcher", function()
  local root = temp_dir("verify-generic")
  local home = paths.join(root, "home")
  local repo = paths.join(root, "repo")
  fake_repo(repo)

  local install_runtime = fake_runtime()
  installer.install({
    home = home,
    repo_root = repo,
    timestamp = "backup",
    runtime = install_runtime,
    omarchy_runtime = fake_omarchy_runtime(false),
  })

  local plugin_calls = 0
  local runtime = fake_runtime()
  runtime.command_exists = function(name)
    return name ~= "omarchy" and name ~= "omarchy-shell"
  end
  runtime.plugin_validate = function()
    plugin_calls = plugin_calls + 1
    return true
  end

  local result = verifier.verify({ home = home, repo_root = repo, runtime = runtime })
  t.eq(result.ok, true)
  t.eq(check(result, "Quickshell").ok, true)
  t.eq(check(result, "Project Launcher wrapper link").ok, true)
  t.eq(check(result, "Project Launcher Quickshell config link").ok, true)
  t.eq(check(result, "Workspace Overview wrapper link").ok, true)
  t.eq(check(result, "Workspace Overview Quickshell config link").ok, true)
  t.eq(check(result, "Omarchy CLI").ok, true)
  t.eq(check(result, "Omarchy CLI").skipped, true)
  t.eq(check(result, "Omarchy plugin validation").ok, true)
  t.eq(check(result, "Omarchy plugin validation").skipped, true)
  t.eq(plugin_calls, 0)

  command.remove_tree(root)
end)

t.test("verifier fails installed launcher when qs disappears", function()
  local root = temp_dir("verify-no-qs")
  local home = paths.join(root, "home")
  local repo = paths.join(root, "repo")
  fake_repo(repo)

  installer.install({
    home = home,
    repo_root = repo,
    timestamp = "backup",
    runtime = fake_runtime(),
    omarchy_runtime = fake_omarchy_runtime(false),
  })

  local runtime = fake_runtime()
  runtime.command_exists = function(name)
    if name == "qs" then
      return false
    end
    return name ~= "omarchy" and name ~= "omarchy-shell"
  end

  local result = verifier.verify({ home = home, repo_root = repo, runtime = runtime })
  t.eq(result.ok, false)
  t.eq(check(result, "Quickshell").ok, false)

  command.remove_tree(root)
end)

t.test("verifier detects replaced workspace overview target", function()
  local root = temp_dir("verify-overview-replaced")
  local home = paths.join(root, "home")
  local repo = paths.join(root, "repo")
  fake_repo(repo)

  installer.install({
    home = home,
    repo_root = repo,
    timestamp = "backup",
    runtime = fake_runtime(),
    omarchy_runtime = fake_omarchy_runtime(false),
  })

  local overview = paths.join(home, ".local", "bin", "hyprland-workspace-overview")
  assert(command.remove(overview))
  write(overview, "#!/bin/sh\necho replacement\n")

  local runtime = fake_runtime()
  runtime.command_exists = function(name)
    return name ~= "omarchy" and name ~= "omarchy-shell"
  end

  local result = verifier.verify({ home = home, repo_root = repo, runtime = runtime })
  t.eq(result.ok, false)
  t.eq(check(result, "Workspace Overview wrapper link").ok, false)

  command.remove_tree(root)
end)

t.test("verifier detects replaced launcher target", function()
  local root = temp_dir("verify-launcher-replaced")
  local home = paths.join(root, "home")
  local repo = paths.join(root, "repo")
  fake_repo(repo)

  installer.install({
    home = home,
    repo_root = repo,
    timestamp = "backup",
    runtime = fake_runtime(),
    omarchy_runtime = fake_omarchy_runtime(false),
  })

  local launcher = paths.join(home, ".local", "bin", "hyprland-workstation-launcher")
  assert(command.remove(launcher))
  write(launcher, "#!/bin/sh\necho replacement\n")

  local runtime = fake_runtime()
  runtime.command_exists = function(name)
    return name ~= "omarchy" and name ~= "omarchy-shell"
  end

  local result = verifier.verify({ home = home, repo_root = repo, runtime = runtime })
  t.eq(result.ok, false)
  t.eq(check(result, "Project Launcher wrapper link").ok, false)

  command.remove_tree(root)
end)

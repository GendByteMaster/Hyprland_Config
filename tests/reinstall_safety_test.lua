local t = require("tests.testlib")
local installer = require("workstation.installer")
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
  write(paths.join(root, "quickshell", "gendbyte-project-launcher", "components", "ThemePalette.qml"), "import QtQuick\nItem {}\n")
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
  write(paths.join(root, "omarchy", "plugins", "gendbyte.system-monitor", "manifest.json"), "{}\n")
  write(paths.join(root, "omarchy", "plugins", "gendbyte.system-monitor", "Service.qml"), "import QtQuick\nItem {}\n")
  write(paths.join(root, "omarchy", "plugins", "gendbyte.system-monitor", "BarWidget.qml"), "import QtQuick\nItem {}\n")
  write(paths.join(root, "omarchy", "plugins", "gendbyte.system-monitor", "ServiceHost.js"), "function hostedService() {}\n")
  write(paths.join(root, "omarchy", "plugins", "gendbyte.system-monitor", "telemetry-collector.lua"), "return true\n")
end

local function generic_runtime()
  return {
    command_exists = function()
      return true
    end,
  }
end

local function runtime(calls, options)
  options = options or {}
  return {
    available = function() return true end,
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
      return true
    end,
    disable_plugin = function() return true end,
  }
end

t.test("installer rescans and waits for Omarchy discovery before enabling system monitor", function()
  local root = temp_dir("rescan-order")
  local home = paths.join(root, "home")
  local repo = paths.join(root, "repo")
  local calls = {}
  fake_repo(repo)

  installer.install({
    home = home,
    repo_root = repo,
    timestamp = "first",
    runtime = generic_runtime(),
    omarchy_runtime = runtime(calls),
  })

  t.eq(#calls, 3)
  t.eq(calls[1].action, "rescan")
  t.eq(calls[2].action, "wait")
  t.eq(calls[2].id, "gendbyte.system-monitor")
  t.eq(calls[3].action, "enable")
  command.remove_tree(root)
end)

t.test("installer restores previous Hyprland config when plugin rescan fails", function()
  local root = temp_dir("rescan-rollback")
  local home = paths.join(root, "home")
  local repo = paths.join(root, "repo")
  local calls = {}
  fake_repo(repo)
  write(paths.join(home, ".config", "hypr", "bindings.lua"), "-- original bindings\n")
  write(paths.join(home, ".config", "hypr", "workstation", "local.lua"), "return 'original'\n")

  local ok = pcall(function()
    installer.install({
      home = home,
      repo_root = repo,
      timestamp = "first",
      runtime = generic_runtime(),
      omarchy_runtime = runtime(calls, { rescan_ok = false }),
    })
  end)

  t.eq(ok, false)
  t.eq(read(paths.join(home, ".config", "hypr", "bindings.lua")), "-- original bindings\n")
  t.eq(read(paths.join(home, ".config", "hypr", "workstation", "local.lua")), "return 'original'\n")
  t.eq(command.exists_or_symlink(paths.join(home, ".config", "omarchy", "plugins", "gendbyte.system-monitor")), false)
  command.remove_tree(root)
end)

t.test("installer restores previous Hyprland config when plugin discovery times out", function()
  local root = temp_dir("discovery-timeout")
  local home = paths.join(root, "home")
  local repo = paths.join(root, "repo")
  local calls = {}
  fake_repo(repo)
  write(paths.join(home, ".config", "hypr", "bindings.lua"), "-- original bindings\n")
  write(paths.join(home, ".config", "hypr", "workstation", "local.lua"), "return 'original'\n")

  local ok = pcall(function()
    installer.install({
      home = home,
      repo_root = repo,
      timestamp = "first",
      runtime = generic_runtime(),
      omarchy_runtime = runtime(calls, { discover_ok = false }),
    })
  end)

  t.eq(ok, false)
  t.eq(calls[1].action, "rescan")
  t.eq(calls[2].action, "wait")
  t.eq(#calls, 2)
  t.eq(read(paths.join(home, ".config", "hypr", "bindings.lua")), "-- original bindings\n")
  t.eq(read(paths.join(home, ".config", "hypr", "workstation", "local.lua")), "return 'original'\n")
  t.eq(command.exists_or_symlink(paths.join(home, ".config", "omarchy", "plugins", "gendbyte.system-monitor")), false)
  command.remove_tree(root)
end)

t.test("reinstall is non-destructive and does not uninstall a working managed config first", function()
  local script = read("reinstall.lua")
  t.eq(script:find("uninstaller.uninstall", 1, true), nil)
  t.truthy(script:find("installer.install", 1, true))
end)

t.test("default Omarchy plugin commands avoid unsupported yes flags", function()
  local source = read("lua/workstation/installer.lua")
  t.eq(source:find("--yes", 1, true), nil)
  t.truthy(source:find("omarchy plugin enable ", 1, true))
  t.truthy(source:find("--section", 1, true))
  t.truthy(source:find("omarchy plugin disable ", 1, true))
end)

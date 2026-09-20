local command = require("workstation.command")
local paths = require("workstation.paths")
local install_state = require("workstation.install_state")

local M = {}

local HUD_PLUGIN_ID = "gendbyte.mouse-hud"
local SYSTEM_MONITOR_PLUGIN_ID = "gendbyte.system-monitor"

local function target_is(target, source)
  if not command.is_symlink(target) then
    return false
  end

  local target_real = command.realpath(target)
  local source_real = command.realpath(source)
  return target_real ~= nil and source_real ~= nil and target_real == source_real
end

local function default_runtime()
  return {
    command_exists = command.command_exists,
    syntax_check = function(repo_root)
      local quoted_root = command.quote(repo_root)
      return command.run(
        "find " .. quoted_root
          .. " -name '*.lua' -type f -print0 | xargs -0 -r -n1 luac5.1 -p"
      )
    end,
    plugin_validate = function(plugin_path)
      return command.run("omarchy plugin validate " .. command.quote(plugin_path))
    end,
  }
end

function M.verify(options)
  options = options or {}

  local home = assert(options.home, "home is required")
  local repo_root = command.realpath(assert(options.repo_root, "repo_root is required"))
  local runtime = options.runtime or default_runtime()
  local checks = {}
  local overall = true

  local function add(name, ok, detail, skipped)
    ok = not not ok
    local check = {
      name = name,
      ok = ok,
      detail = detail,
      skipped = skipped == true,
    }
    checks[#checks + 1] = check
    if not ok then
      overall = false
    end
    return check
  end

  add("repository root", repo_root ~= nil, repo_root or "repository does not exist")
  if not repo_root then
    return { ok = false, checks = checks }
  end

  add(
    "repository safety",
    repo_root:sub(1, #"/usr/share/omarchy") ~= "/usr/share/omarchy",
    repo_root
  )
  add("lua5.1", runtime.command_exists("lua5.1"), "lua5.1 must be installed")
  add("luac5.1", runtime.command_exists("luac5.1"), "luac5.1 must be installed")

  local state_dir = paths.join(home, ".local", "state", "hyprland_config")
  local state_path = paths.join(state_dir, "active.state")
  local preserved_bindings_link = paths.join(state_dir, "preserved_bindings.lua")
  local state, state_error = install_state.read(state_path)
  add("install state", state ~= nil and state_error == nil, state_error or state_path)

  local launcher_expected = state ~= nil and state.version >= 2 and state.launcher == true
  local overview_expected = state ~= nil and state.version >= 3 and state.workspace_overview == true
  local hud_expected = state ~= nil and (
    (state.version >= 2 and state.omarchy_hud == true)
  )
  local monitor_expected = state ~= nil and (
    (state.version >= 2 and state.omarchy_system_monitor == true)
  )

  local source_bindings = paths.join(repo_root, "hypr", "bindings.lua")
  local source_workstation = paths.join(repo_root, "hypr", "workstation")
  local source_launcher = paths.join(repo_root, "bin", "hyprland-workstation-launcher")
  local source_quickshell = paths.join(repo_root, "quickshell", "gendbyte-project-launcher")
  local source_backend = paths.join(repo_root, "project-launcher.lua")
  local source_overview_launcher = paths.join(repo_root, "bin", "hyprland-workspace-overview")
  local source_overview_quickshell = paths.join(repo_root, "quickshell", "gendbyte-workspace-overview")
  local hud_source = paths.join(repo_root, "omarchy", "plugins", HUD_PLUGIN_ID)
  local hud_manifest = paths.join(hud_source, "manifest.json")
  local hud_panel = paths.join(hud_source, "Panel.qml")
  local monitor_source = paths.join(repo_root, "omarchy", "plugins", SYSTEM_MONITOR_PLUGIN_ID)
  local monitor_manifest = paths.join(monitor_source, "manifest.json")
  local monitor_service = paths.join(monitor_source, "Service.qml")
  local monitor_widget = paths.join(monitor_source, "BarWidget.qml")
  local monitor_host = paths.join(monitor_source, "ServiceHost.js")
  local monitor_launcher = paths.join(monitor_source, "telemetry-collector.lua")

  local required = {
    source_bindings,
    paths.join(repo_root, "hypr", "workstation", "mouse.lua"),
    paths.join(repo_root, "hypr", "workstation", "mouse_state.lua"),
    paths.join(repo_root, "hypr", "workstation", "hud.lua"),
    paths.join(repo_root, "hypr", "workstation", "project_launcher.lua"),
    paths.join(repo_root, "hypr", "workstation", "workspace_overview.lua"),
    source_launcher,
    source_quickshell,
    paths.join(source_quickshell, "shell.qml"),
    paths.join(source_quickshell, "ProjectLauncher.qml"),
    paths.join(source_quickshell, "components", "ThemePalette.qml"),
    source_backend,
    source_overview_launcher,
    source_overview_quickshell,
    paths.join(source_overview_quickshell, "shell.qml"),
    paths.join(source_overview_quickshell, "Overview.qml"),
    paths.join(source_overview_quickshell, "components", "WindowPreview.qml"),
    paths.join(source_overview_quickshell, "components", "WorkspaceStrip.qml"),
    paths.join(source_overview_quickshell, "components", "ThemePalette.qml"),
    paths.join(repo_root, "lua", "workstation", "overview_model.lua"),
    paths.join(repo_root, "lua", "workstation", "telemetry.lua"),
    paths.join(repo_root, "lua", "workstation", "telemetry_collector.lua"),
    paths.join(repo_root, "telemetry-collector.lua"),
    paths.join(repo_root, "lua", "workstation", "omarchy_plugins.lua"),
    paths.join(repo_root, "omarchy", "external-plugins.lua"),
    paths.join(repo_root, "omarchy-plugins.lua"),
    paths.join(repo_root, "install.lua"),
    paths.join(repo_root, "uninstall.lua"),
    paths.join(repo_root, "verify.lua"),
  }

  for _, path in ipairs(required) do
    add("file: " .. path:sub(#repo_root + 2), command.exists(path), path)
  end

  if launcher_expected or overview_expected then
    add(
      "Quickshell",
      runtime.command_exists("qs"),
      "qs must be installed for managed workstation UI"
    )
  else
    add("Quickshell", true, "managed Quickshell UI is not installed", true)
  end

  -- Plugin source files remain part of the repository and are checked even on
  -- generic Hyprland. Runtime Omarchy checks are conditional on state ownership.
  add("HUD manifest", command.exists(hud_manifest), hud_manifest)
  add("HUD panel", command.exists(hud_panel), hud_panel)
  add("system monitor manifest", command.exists(monitor_manifest), monitor_manifest)
  add("system monitor service", command.exists(monitor_service), monitor_service)
  add("system monitor bar widget", command.exists(monitor_widget), monitor_widget)
  add("system monitor service host", command.exists(monitor_host), monitor_host)
  add("system monitor collector launcher", command.exists(monitor_launcher), monitor_launcher)

  local omarchy_expected = hud_expected or monitor_expected
  local has_omarchy = runtime.command_exists("omarchy")
  if omarchy_expected then
    add(
      "Omarchy CLI",
      has_omarchy,
      "omarchy must be installed for managed plugin validation"
    )
    add(
      "Omarchy plugin validation",
      has_omarchy
        and command.exists(monitor_manifest)
        and type(runtime.plugin_validate) == "function"
        and runtime.plugin_validate(monitor_source),
      monitor_source
    )
  else
    add("Omarchy CLI", true, "no managed Omarchy components", true)
    add("Omarchy plugin validation", true, "no managed Omarchy components", true)
  end

  if state then
    add("state repository", state.repo_root == repo_root, state.repo_root)

    local target_bindings = paths.join(home, ".config", "hypr", "bindings.lua")
    local target_workstation = paths.join(home, ".config", "hypr", "workstation")
    local target_launcher = paths.join(home, ".local", "bin", "hyprland-workstation-launcher")
    local target_quickshell = paths.join(
      home,
      ".config",
      "quickshell",
      "gendbyte-project-launcher"
    )
    local target_overview_launcher = paths.join(
      home,
      ".local",
      "bin",
      "hyprland-workspace-overview"
    )
    local target_overview_quickshell = paths.join(
      home,
      ".config",
      "quickshell",
      "gendbyte-workspace-overview"
    )
    local target_hud = paths.join(
      home,
      ".config",
      "omarchy",
      "plugins",
      HUD_PLUGIN_ID
    )
    local target_monitor = paths.join(
      home,
      ".config",
      "omarchy",
      "plugins",
      SYSTEM_MONITOR_PLUGIN_ID
    )

    add("bindings link", target_is(target_bindings, source_bindings), target_bindings)
    add(
      "workstation link",
      target_is(target_workstation, source_workstation),
      target_workstation
    )

    if launcher_expected then
      add(
        "Project Launcher wrapper link",
        target_is(target_launcher, source_launcher),
        target_launcher
      )
      add(
        "Project Launcher Quickshell config link",
        target_is(target_quickshell, source_quickshell),
        target_quickshell
      )
    else
      add(
        "Project Launcher wrapper link",
        true,
        "Project Launcher is not installed",
        true
      )
      add(
        "Project Launcher Quickshell config link",
        true,
        "Project Launcher is not installed",
        true
      )
    end

    if overview_expected then
      add(
        "Workspace Overview wrapper link",
        target_is(target_overview_launcher, source_overview_launcher),
        target_overview_launcher
      )
      add(
        "Workspace Overview Quickshell config link",
        target_is(target_overview_quickshell, source_overview_quickshell),
        target_overview_quickshell
      )
    else
      add(
        "Workspace Overview wrapper link",
        true,
        "Workspace Overview is not installed",
        true
      )
      add(
        "Workspace Overview Quickshell config link",
        true,
        "Workspace Overview is not installed",
        true
      )
    end

    if state.version == 1 then
      -- Legacy state has no component flags. Validate only links that actually
      -- exist and point into this repository.
      hud_expected = target_is(target_hud, hud_source)
      monitor_expected = target_is(target_monitor, monitor_source)
    end

    if hud_expected then
      add("HUD plugin link", target_is(target_hud, hud_source), target_hud)
    else
      add("HUD plugin link", true, "HUD plugin is not managed", true)
    end

    if monitor_expected then
      add(
        "system monitor plugin link",
        target_is(target_monitor, monitor_source),
        target_monitor
      )
    else
      add(
        "system monitor plugin link",
        true,
        "System Monitor plugin is not managed",
        true
      )
    end

    if state.preserved_bindings then
      local backup_bindings = paths.join(state.backup_dir, "hypr", "bindings.lua")
      add(
        "preserved bindings",
        command.exists_or_symlink(backup_bindings)
          and target_is(preserved_bindings_link, backup_bindings),
        backup_bindings
      )
    else
      add(
        "preserved bindings",
        not command.exists_or_symlink(preserved_bindings_link),
        preserved_bindings_link
      )
    end
  else
    add("bindings link", false, "cannot validate without install state")
    add("workstation link", false, "cannot validate without install state")
    add(
      "Project Launcher wrapper link",
      false,
      "cannot validate without install state"
    )
    add(
      "Project Launcher Quickshell config link",
      false,
      "cannot validate without install state"
    )
    add(
      "Workspace Overview wrapper link",
      false,
      "cannot validate without install state"
    )
    add(
      "Workspace Overview Quickshell config link",
      false,
      "cannot validate without install state"
    )
    add("HUD plugin link", false, "cannot validate without install state")
    add(
      "system monitor plugin link",
      false,
      "cannot validate without install state"
    )
  end

  add("Lua syntax", runtime.syntax_check(repo_root), "luac5.1 -p")
  return {
    ok = overall,
    checks = checks,
  }
end

return M

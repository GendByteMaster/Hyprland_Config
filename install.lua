local source = debug.getinfo(1, "S").source
if source:sub(1, 1) == "@" then
  source = source:sub(2)
end

local script_dir = source:match("^(.*)/[^/]+$") or "."
package.path = script_dir .. "/lua/?.lua;" .. script_dir .. "/lua/?/init.lua;" .. package.path

local command = require("workstation.command")
local installer = require("workstation.installer")
local sound_assets = require("workstation.sound_assets")
local omarchy_plugins = require("workstation.omarchy_plugins")

local HUD_PLUGIN_ID = "gendbyte.mouse-hud"
local home = assert(os.getenv("HOME"), "HOME is not set")
local repo_root = assert(command.realpath(script_dir), "cannot resolve repository root")
local result = installer.install({ home = home, repo_root = repo_root })

if result.changed then
  print("Hyprland_Config installed.")
  if result.backup_dir ~= "" then
    print("Previous configuration backed up to: " .. result.backup_dir)
  end
else
  print("Hyprland_Config is already installed and up to date.")
end

local sound_result = sound_assets.install({ home = home, repo_root = repo_root })
if sound_result.ok then
  print("Num Lock UI SFX installed locally: " .. sound_result.directory)
else
  print("Num Lock sound feedback is unavailable: " .. tostring(sound_result.error))
  print("Mouse Mode will continue to work without audio feedback.")
end

local hud_enabled = false
if command.command_exists("omarchy-shell") then
  local rescanned = command.capture("omarchy-shell shell rescanPlugins")
  if rescanned ~= nil then
    hud_enabled = command.capture("omarchy-shell shell setPluginEnabled " .. HUD_PLUGIN_ID .. " true") == "ok"
  end
end

if hud_enabled then
  print("Mouse Mode HUD plugin enabled in Omarchy Shell.")
else
  print("Mouse Mode HUD plugin is installed but could not be enabled automatically.")
  print("Run after Omarchy Shell is available:")
  print("  omarchy-shell shell rescanPlugins")
  print("  omarchy-shell shell setPluginEnabled " .. HUD_PLUGIN_ID .. " true")
end

local external_manifest, external_manifest_error = omarchy_plugins.load_manifest(
  repo_root .. "/omarchy/external-plugins.lua"
)
if not external_manifest then
  io.stderr:write(
    "External Omarchy plugins were not synced: "
      .. tostring(external_manifest_error)
      .. "\n"
  )
else
  local external_result = omarchy_plugins.sync({
    home = home,
    manifest = external_manifest,
  })
  if external_result.skipped then
    print("External Omarchy plugins skipped: " .. tostring(external_result.reason))
  elseif external_result.ok then
    print(
      external_result.changed
        and "External Omarchy plugins reconciled."
        or "External Omarchy plugins are already pinned and up to date."
    )
  else
    io.stderr:write("External Omarchy plugin sync completed with errors.\n")
    for _, item in ipairs(external_result.results or {}) do
      if not item.ok then
        io.stderr:write(
          "  " .. tostring(item.name) .. ": " .. tostring(item.error) .. "\n"
        )
      end
    end
    if external_result.error then
      io.stderr:write("  " .. tostring(external_result.error) .. "\n")
    end
    io.stderr:write("Core Hyprland_Config installation remains installed.\n")
  end
end

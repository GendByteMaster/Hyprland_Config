local source = debug.getinfo(1, "S").source
if source:sub(1, 1) == "@" then
  source = source:sub(2)
end

local script_dir = source:match("^(.*)/[^/]+$") or "."
package.path = script_dir .. "/lua/?.lua;" .. script_dir .. "/lua/?/init.lua;" .. package.path

local command = require("workstation.command")
local installer = require("workstation.installer")
local sound_assets = require("workstation.sound_assets")
local verifier = require("workstation.verifier")
local omarchy_plugins = require("workstation.omarchy_plugins")
local optional_apps = require("workstation.optional_apps")

local HUD_PLUGIN_ID = "gendbyte.mouse-hud"
local home = assert(os.getenv("HOME"), "HOME is not set")
local repo_root = assert(command.realpath(script_dir), "cannot resolve repository root")

print("Reconciling Hyprland_Config installation...")

local install_result = installer.install({ home = home, repo_root = repo_root })
if install_result.changed then
  print("Hyprland_Config installation updated.")
  if install_result.backup_dir ~= "" then
    print("Configuration backed up to: " .. install_result.backup_dir)
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

if command.command_exists("omarchy-shell") then
  command.capture("omarchy-shell shell rescanPlugins")
  local enabled = command.capture("omarchy-shell shell setPluginEnabled " .. HUD_PLUGIN_ID .. " true") == "ok"
  if enabled then
    print("Mouse Mode HUD plugin enabled.")
  else
    print("Mouse Mode HUD plugin could not be enabled automatically.")
  end
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
    io.stderr:write("External Omarchy plugin sync completed with errors; continuing core verification.\n")
    for _, item in ipairs(external_result.results or {}) do
      if not item.ok then
        io.stderr:write(
          "  " .. tostring(item.name) .. ": " .. tostring(item.error) .. "\n"
        )
      end
    end
  end
end

local amnezia_result = optional_apps.install_amneziavpn()
if amnezia_result.ok then
  if amnezia_result.skipped then
    print("AmneziaVPN auto-install skipped: " .. tostring(amnezia_result.reason))
  elseif amnezia_result.changed then
    print("AmneziaVPN " .. tostring(amnezia_result.version) .. " installed from the official release.")
  else
    print("AmneziaVPN is already installed.")
  end
else
  io.stderr:write(
    "Optional AmneziaVPN installation failed: "
      .. tostring(amnezia_result.error)
      .. "\n"
  )
  io.stderr:write("Continuing core Hyprland_Config verification.\n")
end

local verification = verifier.verify({ home = home, repo_root = repo_root })
for _, check in ipairs(verification.checks) do
  local marker = check.ok and "OK" or "FAIL"
  print(string.format("[%s] %s%s", marker, check.name, check.detail and (" - " .. tostring(check.detail)) or ""))
end

if not verification.ok then
  io.stderr:write("Hyprland_Config verification failed; Hyprland was not reloaded.\n")
  os.exit(1)
end

print("Hyprland_Config verification passed.")

if command.command_exists("hyprctl") then
  local reload_result = command.capture("hyprctl reload")
  if reload_result == nil then
    io.stderr:write("Hyprland reload failed.\n")
    os.exit(1)
  end

  print("Hyprland configuration reloaded.")

  local config_errors = command.capture("hyprctl configerrors")
  if config_errors == nil then
    io.stderr:write("Unable to query Hyprland runtime config errors.\n")
    os.exit(1)
  end

  if config_errors ~= "" and config_errors ~= "ok" then
    io.stderr:write("Hyprland runtime config errors remain:\n" .. config_errors .. "\n")
    os.exit(1)
  end

  print("Hyprland runtime config check passed.")
end

print("Reinstall complete.")

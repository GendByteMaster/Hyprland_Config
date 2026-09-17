local source = debug.getinfo(1, "S").source
if source:sub(1, 1) == "@" then
  source = source:sub(2)
end

local script_dir = source:match("^(.*)/[^/]+$") or "."
package.path = script_dir .. "/lua/?.lua;" .. script_dir .. "/lua/?/init.lua;" .. package.path

local command = require("workstation.command")
local installer = require("workstation.installer")
local uninstaller = require("workstation.uninstaller")
local verifier = require("workstation.verifier")

local HUD_PLUGIN_ID = "gendbyte.mouse-hud"
local home = assert(os.getenv("HOME"), "HOME is not set")
local repo_root = assert(command.realpath(script_dir), "cannot resolve repository root")

print("Reinstalling Hyprland_Config...")

if command.command_exists("omarchy-shell") then
  command.capture("omarchy-shell shell setPluginEnabled " .. HUD_PLUGIN_ID .. " false")
end

local uninstall_result = uninstaller.uninstall({ home = home })
if uninstall_result.changed then
  print("Existing Hyprland_Config installation removed.")
  if uninstall_result.restored_from ~= "" then
    print("Previous configuration temporarily restored from: " .. uninstall_result.restored_from)
  end
else
  print("No existing managed installation found; continuing with a fresh install.")
end

local install_result = installer.install({ home = home, repo_root = repo_root })
if install_result.changed then
  print("Fresh Hyprland_Config installation completed.")
  if install_result.backup_dir ~= "" then
    print("Configuration backed up to: " .. install_result.backup_dir)
  end
else
  print("Hyprland_Config is already installed and up to date.")
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
